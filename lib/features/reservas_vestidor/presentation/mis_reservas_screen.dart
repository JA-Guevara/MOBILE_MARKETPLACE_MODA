import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../shared/formato.dart';
import '../../../shared/widgets/estado_vista.dart';
import '../application/reservas_controller.dart';
import '../domain/reserva.dart';

/// «Mis reservas» (`/mi-cuenta/reservas`), réplica de `mis-reservas.component.ts`.
class MisReservasScreen extends ConsumerStatefulWidget {
  const MisReservasScreen({super.key});

  @override
  ConsumerState<MisReservasScreen> createState() => _MisReservasScreenState();
}

class _MisReservasScreenState extends ConsumerState<MisReservasScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(reservasProvider.notifier).cargar());
  }

  Future<void> _confirmarCancelacion(Reserva reserva) async {
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('¿Cancelar la visita?'),
        content: const Text(
          'Se liberan las prendas que la sucursal tenía separadas para vos.',
        ),
        actions: [
          TextButton(
            onPressed: () => context.pop(false),
            child: const Text('Volver'),
          ),
          FilledButton(
            onPressed: () => context.pop(true),
            child: const Text('Cancelar visita'),
          ),
        ],
      ),
    );
    if (confirmado == true) {
      await ref.read(reservasProvider.notifier).cancelar(reserva);
    }
  }

  @override
  Widget build(BuildContext context) {
    final estado = ref.watch(reservasProvider);
    final control = ref.read(reservasProvider.notifier);
    final tema = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Mis reservas')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/reservar'),
        icon: const Icon(Icons.add),
        label: const Text('Agendar'),
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: control.cargar,
          child: Builder(builder: (context) {
            if (estado.cargando && estado.reservas.isEmpty) {
              return const VistaCargando(mensaje: 'Buscando tus visitas…');
            }
            if (estado.error != null && estado.reservas.isEmpty) {
              return VistaError(mensaje: estado.error!, onReintentar: control.cargar);
            }
            if (estado.reservas.isEmpty) {
              return VistaVacia(
                icono: Icons.event_outlined,
                titulo: 'Todavía no agendaste ninguna visita',
                mensaje: 'Elegí prendas del catálogo y reservá un horario para '
                    'probártelas en la sucursal.',
                accionIcono: Icons.event_available_outlined,
                accionTexto: 'Agendar una visita',
                onAccion: () => context.push('/reservar'),
              );
            }
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
              children: [
                if (estado.mensaje != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(estado.mensaje!,
                        style: TextStyle(color: tema.colorScheme.primary)),
                  ),
                if (estado.error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(estado.error!,
                        style: TextStyle(color: tema.colorScheme.error)),
                  ),
                for (final reserva in estado.reservas)
                  _TarjetaReserva(
                    reserva: reserva,
                    ocupado: estado.ocupado,
                    onCancelar: () => _confirmarCancelacion(reserva),
                  ),
              ],
            );
          }),
        ),
      ),
    );
  }
}

class _TarjetaReserva extends StatelessWidget {
  const _TarjetaReserva({
    required this.reserva,
    required this.ocupado,
    required this.onCancelar,
  });

  final Reserva reserva;
  final bool ocupado;
  final VoidCallback onCancelar;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        border: Border.all(color: tema.colorScheme.outline),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  Formato.fechaHora(reserva.agendadaPara),
                  style: tema.textTheme.titleSmall,
                ),
              ),
              ChipEstado(
                etiqueta: reserva.etiquetaEstado,
                exportacion: colorDeEstadoReserva(reserva.estado),
                compacto: true,
              ),
            ],
          ),
          if (reserva.sucursal?.isNotEmpty == true) ...[
            const SizedBox(height: 4),
            Text(reserva.sucursal!, style: tema.textTheme.bodySmall),
          ],
          const SizedBox(height: 8),
          Text(
            '${reserva.unidades} ${reserva.unidades == 1 ? 'prenda' : 'prendas'} '
            'para probarte',
            style: tema.textTheme.bodySmall,
          ),
          if (reserva.inventarioApartado)
            Text(
              'Apartadas del inventario de esta sucursal',
              style: tema.textTheme.bodySmall?.copyWith(
                color: tema.colorScheme.primary,
              ),
            ),
          for (final item in reserva.items)
            if (item.producto.isNotEmpty)
              Text('· ${item.producto} ${item.etiqueta} × ${item.cantidad}',
                  style: tema.textTheme.bodySmall),
          if (reserva.notas?.isNotEmpty == true) ...[
            const SizedBox(height: 6),
            Text(reserva.notas!, style: tema.textTheme.bodySmall),
          ],
          if (reserva.tracking.isNotEmpty) ...[
            const SizedBox(height: 8),
            for (final paso in reserva.tracking)
              Text(
                '${paso.etiqueta}${paso.fecha.isEmpty ? '' : ' · ${Formato.fechaHora(paso.fecha)}'}',
                style: tema.textTheme.bodySmall,
              ),
          ],
          if (reserva.sePuedeCancelar) ...[
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: ocupado ? null : onCancelar,
                child: Text('Cancelar visita',
                    style: TextStyle(color: tema.colorScheme.error)),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
