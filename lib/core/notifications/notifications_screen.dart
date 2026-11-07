import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/router.dart';
import 'app_notices.dart';

/// El historial conserva los avisos aunque la ventana ya se haya cerrado.
class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final feed = ref.watch(notificationFeedProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Avisos y pagos'),
        actions: [
          IconButton(
            tooltip: 'Actualizar avisos',
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(notificationFeedProvider),
          ),
        ],
      ),
      body: feed.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'No pudimos consultar tus avisos. El estado de tus pagos no cambió. Volvé a intentar con conexión.',
                ),
                TextButton(
                  onPressed: () => ref.invalidate(notificationFeedProvider),
                  child: const Text('Reintentar'),
                ),
              ],
            ),
          ),
        ),
        data: (rows) => RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(notificationFeedProvider);
            await ref.read(notificationFeedProvider.future);
          },
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            children: [
              if (rows.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('Todavía no tenés avisos en esta empresa.'),
                ),
              for (final row in rows)
                Card(
                  child: ListTile(
                    leading: Icon(
                      row['tono'] == 'success'
                          ? Icons.check_circle_outline
                          : Icons.notifications_outlined,
                    ),
                    title: Text(row['titulo'] as String),
                    subtitle: Text('${row['referencia']} · ${row['detalle']}'),
                    isThreeLine: true,
                    onTap: () =>
                        openAccountNotice(ref, row['enlace'] as String),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

void openAccountNotice(WidgetRef ref, String link) {
  final uri = Uri.tryParse(link);
  if (uri == null || uri.hasScheme || uri.hasAuthority || !link.startsWith('/')) {
    return;
  }
  String route = uri.path;
  if (route == '/mi-cuenta/pedidos' && uri.queryParameters['pedido'] != null) {
    route += '/${uri.queryParameters['pedido']}';
  }
  if (route.startsWith('/admin')) route = '/mi-cuenta';
  ref.read(routerProvider).go(route);
}
