import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../../shared/widgets/indicador_conexion.dart';
import '../application/reserva_offline_controller.dart';
import '../domain/reserva_local.dart';
import 'offline_widgets.dart';
import 'reservas_locales_screen.dart';

class ComprobanteReservaScreen extends ConsumerWidget {
  const ComprobanteReservaScreen({super.key, required this.id});
  final String id;
  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    appBar: AppBar(
      title: const Text('Reserva guardada'),
      actions: const [IndicadorConexion()],
    ),
    body: ref
        .watch(reservaLocalProvider(id))
        .when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, st) =>
              Center(child: Text('No se pudo leer el comprobante. $e')),
          data: (v) {
            if (v == null) {
              return const Center(
                child: Text('Reserva local no encontrada para este perfil.'),
              );
            }
            return ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: Theme.of(
                        context,
                      ).colorScheme.primary.withValues(alpha: .4),
                      width: 2,
                    ),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      AvisoOffline(
                        etiquetaReserva(v.reserva.estado),
                        info: true,
                      ),
                      Text(
                        'Comprobante provisional de reserva',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 12),
                      Center(
                        child: QrImageView(
                          data: v.reserva.id,
                          version: QrVersions.auto,
                          size: 160,
                          backgroundColor: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 12),
                      SelectableText(
                        v.reserva.id,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        '${v.sucursalNombre ?? 'Sucursal guardada'} · ${fechaLocal(v.reserva.agendadaPara)}',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${v.items.length} prendas · ${v.unidades} unidades',
                      ),
                      const SizedBox(height: 8),
                      Text('Guardada: ${fechaLocal(v.reserva.creadaEn)}'),
                      if (v.reserva.notas?.isNotEmpty == true)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Text(v.reserva.notas!),
                        ),
                      const SizedBox(height: 12),
                      const AvisoOffline(
                        'Esta reserva todavía no está confirmada por la tienda.',
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                if (puedeCancelarLocal(v.operacion))
                  OutlinedButton(
                    onPressed: () => cancelarReservaLocal(context, ref, v),
                    child: const Text('Cancelar reserva local'),
                  ),
                FilledButton(
                  onPressed: () => context.go('/sin-conexion/reservas'),
                  child: const Text('Ver reservas locales'),
                ),
              ],
            );
          },
        ),
  );
}
