import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../features/usuarios_catalogo/application/session_controller.dart';

class AppNotice {
  const AppNotice({
    required this.key,
    required this.title,
    required this.detail,
    this.tone = 'info',
    this.important = false,
    this.link,
  });
  final String key, title, detail, tone;
  final bool important;
  final String? link;

  factory AppNotice.fromJson(Map<String, dynamic> json) => AppNotice(
    key: (json['event_key'] ?? json['id']) as String,
    title: json['titulo'] as String,
    detail: '${json['referencia']} · ${json['detalle']}',
    tone: json['tono'] as String? ?? 'info',
    important: json['importante'] == true,
    link: json['enlace'] as String?,
  );
}

class AppNotices extends StateNotifier<List<AppNotice>> {
  AppNotices() : super(const []);
  final _seen = <String>{};
  void show(AppNotice notice) {
    if (!mounted || !_seen.add(notice.key)) return;
    if (_seen.length > 200) _seen.remove(_seen.first);
    state = [...state, notice].take(10).toList();
  }

  void dismiss(String key) {
    if (mounted) state = state.where((notice) => notice.key != key).toList();
  }
}

final appNoticesProvider = StateNotifierProvider<AppNotices, List<AppNotice>>((
  ref,
) {
  ref.watch(identidadSesionProvider);
  return AppNotices();
});

final notificationFeedProvider = FutureProvider<List<Map<String, dynamic>>>((
  ref,
) async {
  ref.watch(identidadSesionProvider);
  if (!ref.read(sessionProvider).autenticado) return const [];
  final client = ref.read(apiClientProvider);
  final rows = await client.get<List<dynamic>>(
    '/notifications',
    query: {'limit': 30},
  );
  return rows.cast<Map<String, dynamic>>();
});

AppNotice paymentNotice({
  required String id,
  required String number,
  required double amount,
  required String currency,
  required String status,
}) => AppNotice(
  key: 'payment:$id:$status',
  title: status == 'paid'
      ? 'Pago confirmado'
      : 'Pago pendiente de confirmación',
  detail: status == 'paid'
      ? '$number · ${amount.toStringAsFixed(2)} ${currency.toUpperCase()}. El servidor confirmó el pago. Podés seguir la preparación o el retiro del pedido.'
      : '$number. Todavía no se confirmó el cobro. Conservamos el pedido; si ya pagaste, verificá de nuevo antes de repetir el pago.',
  tone: status == 'paid' ? 'success' : 'warning',
  important: true,
  link: '/mi-cuenta/pedidos/$id',
);
