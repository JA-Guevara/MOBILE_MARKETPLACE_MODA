import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../shared/widgets/indicador_conexion.dart';
import '../application/reserva_offline_controller.dart';
import '../domain/reserva_local.dart';
import 'offline_widgets.dart';

Future<void> cancelarReservaLocal(
  BuildContext context,
  WidgetRef ref,
  ReservaLocalVista vista,
) async {
  final corto = vista.reserva.id.substring(0, 8);
  final confirmado = await showDialog<bool>(
    context: context,
    builder: (dialogo) => AlertDialog(
      title: Text('¿Cancelar la reserva $corto?'),
      content: Text(
        'Se devolverán ${vista.unidades} unidades a las existencias locales.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogo, false),
          child: const Text('Volver'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogo, true),
          child: const Text('Cancelar reserva'),
        ),
      ],
    ),
  );
  if (confirmado == true) {
    try {
      await ref
          .read(reservaOfflineProvider.notifier)
          .cancelar(vista.reserva.id);
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$error')));
      }
    }
  }
}

String etiquetaReserva(EstadoReservaLocal estado) => switch (estado) {
  EstadoReservaLocal.pendienteConfirmacion => 'Pendiente de sincronizar',
  EstadoReservaLocal.anuladaLocal => 'Anulada localmente',
  EstadoReservaLocal.confirmada => 'Confirmada',
  EstadoReservaLocal.rechazada => 'Rechazada',
};

class ReservasLocalesScreen extends ConsumerStatefulWidget {
  const ReservasLocalesScreen({super.key});
  @override
  ConsumerState<ReservasLocalesScreen> createState() =>
      _ReservasLocalesScreenState();
}

class _ReservasLocalesScreenState extends ConsumerState<ReservasLocalesScreen> {
  bool _soloPendientes = false;
  @override
  Widget build(BuildContext context) {
    final reservas = ref.watch(reservasLocalesProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mis reservas'),
        actions: const [IndicadorConexion()],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                FilterChip(
                  label: const Text('En el teléfono'),
                  selected: !_soloPendientes,
                  onSelected: (_) => setState(() => _soloPendientes = false),
                ),
                const SizedBox(width: 8),
                FilterChip(
                  label: const Text('Pendientes'),
                  selected: _soloPendientes,
                  onSelected: (v) => setState(() => _soloPendientes = v),
                ),
              ],
            ),
          ),
          Expanded(
            child: reservas.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, st) =>
                  Center(child: Text('No se pudieron leer las reservas. $e')),
              data: (lista) {
                final visibles = lista
                    .where(
                      (r) =>
                          !_soloPendientes ||
                          r.operacion.estado == EstadoOperacion.pendiente,
                    )
                    .toList();
                if (visibles.isEmpty) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'Todavía no hay reservas locales para este perfil.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  );
                }
                return ListView(
                  padding: const EdgeInsets.all(16),
                  children: visibles
                      .map(
                        (v) => PanelOffline(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              InkWell(
                                onTap: () => context.push(
                                  '/sin-conexion/reservas/${v.reserva.id}',
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            '${v.reserva.id.substring(0, 8)}…',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                        Icon(
                                          v.operacion.estado ==
                                                  EstadoOperacion.pendiente
                                              ? Icons.schedule
                                              : Icons.check_circle_outline,
                                          size: 18,
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      etiquetaReserva(v.reserva.estado),
                                      style: TextStyle(
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.primary,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      '${v.sucursalNombre ?? 'Sucursal guardada'} · ${fechaLocal(v.reserva.agendadaPara)} · ${v.unidades} u.',
                                    ),
                                  ],
                                ),
                              ),
                              if (puedeCancelarLocal(v.operacion))
                                TextButton(
                                  onPressed: () =>
                                      cancelarReservaLocal(context, ref, v),
                                  child: const Text('Cancelar'),
                                ),
                            ],
                          ),
                        ),
                      )
                      .toList(),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
