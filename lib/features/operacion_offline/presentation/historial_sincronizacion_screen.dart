import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../application/historial_sincronizacion_provider.dart';
import '../domain/sincronizacion.dart';
import 'offline_widgets.dart';

/// CU-19 · Consultar el resultado de la sincronización.
class HistorialSincronizacionScreen extends ConsumerWidget {
  const HistorialSincronizacionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final historial = ref.watch(historialSincronizacionProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Historial de sincronización')),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(historialSincronizacionProvider.future),
        child: historial.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                'No se pudo leer el historial local: $error',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ),
          data: (registros) => registros.isEmpty
              ? ListView(
                  padding: const EdgeInsets.all(24),
                  children: const [
                    Icon(Icons.history, size: 48),
                    SizedBox(height: 12),
                    Text(
                      'Todavía no hay sincronizaciones registradas en este dispositivo.',
                      textAlign: TextAlign.center,
                    ),
                    SizedBox(height: 8),
                    Text(
                      'Cuando sincronices tus operaciones locales, aquí verás cuántas se enviaron y su resultado.',
                      textAlign: TextAlign.center,
                    ),
                  ],
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: registros.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, i) =>
                      _TarjetaSincronizacion(registros[i]),
                ),
        ),
      ),
    );
  }
}

class _TarjetaSincronizacion extends StatelessWidget {
  const _TarjetaSincronizacion(this.registro);
  final RegistroSincronizacion registro;

  @override
  Widget build(BuildContext context) {
    final esquema = Theme.of(context).colorScheme;
    final error = registro.mensajeError;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  error == null ? Icons.cloud_done : Icons.cloud_off,
                  color: error == null ? esquema.primary : esquema.error,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    fechaLocal(registro.iniciadoEn),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 12,
              runSpacing: 4,
              children: [
                Text('Enviadas: ${registro.enviadas}'),
                Text('Aceptadas: ${registro.confirmadas}'),
                Text('Rechazadas: ${registro.rechazadas}'),
                Text('En conflicto: ${registro.conflictos}'),
              ],
            ),
            if (error != null) ...[
              const SizedBox(height: 8),
              Text('Error: $error', style: TextStyle(color: esquema.error)),
            ],
          ],
        ),
      ),
    );
  }
}
