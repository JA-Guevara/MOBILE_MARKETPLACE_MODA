import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../offline/base_local.dart';
import '../../app/router.dart';
import '../../features/usuarios_catalogo/application/session_controller.dart';
import 'app_notices.dart';

class NoticesHost extends ConsumerStatefulWidget {
  const NoticesHost({super.key, required this.child});
  final Widget child;
  @override
  ConsumerState<NoticesHost> createState() => _NoticesHostState();
}

class _NoticesHostState extends ConsumerState<NoticesHost>
    with WidgetsBindingObserver {
  Timer? _timer;
  bool _showing = false;
  String _identity = '';
  BuildContext? _dialogContext;
  final _seenFeed = <String>{};
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _timer = Timer.periodic(const Duration(seconds: 45), (_) => _refresh());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  void _refresh() {
    if (mounted &&
        ref.read(sessionProvider).autenticado &&
        WidgetsBinding.instance.lifecycleState != AppLifecycleState.paused) {
      ref.invalidate(notificationFeedProvider);
    }
  }

  String get _key => 'popup_events:$_identity';

  Future<void> _receive(
    List<Map<String, dynamic>> rows,
    String identity,
  ) async {
    if (rows.isEmpty) return;
    final base = ref.read(baseLocalProvider);
    try {
      final saved = await base.leerMeta(_key);
      if (!mounted || identity != _identity) return;
      if (saved != null) {
        _seenFeed.addAll((jsonDecode(saved) as List).cast<String>());
      }
    } catch (_) {
      /* caché opcional; no afecta pagos */
    }
    if (!mounted || identity != _identity) return;
    final recent = rows
        .where((row) {
          final date = DateTime.tryParse(row['fecha'] as String? ?? '');
          return row['importante'] == true &&
              date != null &&
              date.isAfter(DateTime.now().subtract(const Duration(days: 1)));
        })
        .take(3)
        .toList()
        .reversed;
    for (final row in recent) {
      final notice = AppNotice.fromJson(row);
      if (_seenFeed.add(notice.key)) {
        ref.read(appNoticesProvider.notifier).show(notice);
      }
    }
    while (_seenFeed.length > 200) {
      _seenFeed.remove(_seenFeed.first);
    }
    final values = jsonEncode(_seenFeed.toList());
    try {
      await base.guardarMeta('popup_events:$identity', values);
    } catch (_) {
      /* memoria de sesión */
    }
  }

  Future<void> _present() async {
    if (!mounted || _showing) return;
    final notices = ref.read(appNoticesProvider);
    if (notices.isEmpty) return;
    final root = appNavigatorKey.currentContext;
    if (root == null) return;
    _showing = true;
    final identity = _identity;
    final notice = notices.first;
    final color = notice.tone == 'success'
        ? Colors.green.shade700
        : notice.tone == 'error'
        ? Colors.red.shade700
        : Colors.amber.shade800;
    try {
      await showDialog<void>(
        context: root,
        barrierDismissible: !notice.important,
        builder: (context) {
          _dialogContext = context;
          return AlertDialog(
            icon: Icon(
              notice.tone == 'success'
                  ? Icons.check_circle_outline
                  : Icons.info_outline,
              color: color,
              size: 52,
            ),
            title: Text(notice.title),
            content: Text(notice.detail),
            scrollable: true,
            actions: [
              if (notice.link != null)
                TextButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                    if (identity == _identity) _open(notice.link!);
                  },
                  child: const Text('Ver detalle'),
                ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Entendido'),
              ),
            ],
          );
        },
      );
    } finally {
      _dialogContext = null;
      _showing = false;
      if (mounted && identity == _identity) {
        ref.read(appNoticesProvider.notifier).dismiss(notice.key);
      }
      if (mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _present());
      }
    }
  }

  void _open(String link) {
    final uri = Uri.tryParse(link);
    if (uri == null ||
        uri.hasScheme ||
        uri.hasAuthority ||
        !link.startsWith('/')) {
      return;
    }
    // Los enlaces del feed web se traducen a rutas reales de la app.
    if (uri.path == '/mi-cuenta/pedidos') {
      final id = uri.queryParameters['pedido'];
      ref
          .read(routerProvider)
          .go(id == null ? '/mi-cuenta/pedidos' : '/mi-cuenta/pedidos/$id');
    } else if (uri.path.startsWith('/admin')) {
      ref.read(routerProvider).go('/mi-cuenta');
    } else {
      ref.read(routerProvider).go(uri.path);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(identidadSesionProvider, (_, identity) {
      _identity = '${identity.$1 ?? ''}:${identity.$2 ?? ''}';
      _seenFeed.clear();
      final dialog = _dialogContext;
      if (dialog != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (dialog.mounted) Navigator.of(dialog).pop();
        });
      }
    });
    final identity = ref.watch(identidadSesionProvider);
    _identity = '${identity.$1 ?? ''}:${identity.$2 ?? ''}';
    ref.listen(notificationFeedProvider, (_, next) {
      final rows = next.asData?.value;
      if (rows != null) unawaited(_receive(rows, _identity));
    });
    ref.watch(notificationFeedProvider);
    ref.listen(appNoticesProvider, (_, next) {
      if (next.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _present());
      }
    });
    if (ref.watch(appNoticesProvider).isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _present());
    }
    return widget.child;
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
