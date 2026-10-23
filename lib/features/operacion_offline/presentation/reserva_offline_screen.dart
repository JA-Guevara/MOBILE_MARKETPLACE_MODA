import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../shared/widgets/indicador_conexion.dart';
import '../../usuarios_catalogo/application/session_controller.dart';
import '../application/catalogo_offline_controller.dart';
import '../application/reserva_offline_controller.dart';
import 'offline_widgets.dart';

class ReservaOfflineScreen extends ConsumerWidget {
  const ReservaOfflineScreen({super.key});
  Future<void> _fecha(BuildContext context, WidgetRef ref) async {
    final actual =
        ref.read(reservaOfflineProvider).agendadaPara ??
        DateTime.now().add(const Duration(days: 1));
    final ahora = DateTime.now();
    final fecha = await showDatePicker(
      context: context,
      initialDate: actual.isBefore(ahora) ? ahora : actual,
      firstDate: DateTime(ahora.year, ahora.month, ahora.day),
      lastDate: ahora.add(const Duration(days: 365)),
    );
    if (fecha == null || !context.mounted) return;
    final hora = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(actual),
    );
    if (hora != null) {
      ref
          .read(reservaOfflineProvider.notifier)
          .configurar(
            visita: DateTime(
              fecha.year,
              fecha.month,
              fecha.day,
              hora.hour,
              hora.minute,
            ),
          );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final r = ref.watch(reservaOfflineProvider);
    final c = ref.watch(catalogoOfflineProvider);
    final usuario = ref.watch(sessionProvider).usuario;
    final control = ref.read(reservaOfflineProvider.notifier);
    final puede =
        puedeOperarOffline(usuario) &&
        usuario?.suscripcion?.permite('reservations') == true;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Nueva reserva'),
        actions: const [IndicadorConexion()],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (!puede)
            const AvisoOffline(
              'Tu suscripción permite consultar, pero no registrar reservas.',
              peligro: true,
            ),
          for (final item in r.items)
            Builder(
              builder: (context) {
                final variantes = c.datos.variantes.where(
                  (v) => v.id == item.varianteId,
                );
                final v = variantes.isEmpty ? null : variantes.first;
                final productos = c.datos.productos.where(
                  (p) => p.id == v?.productoId,
                );
                final p = productos.isEmpty ? null : productos.first;
                return PanelOffline(
                  child: Row(
                    children: [
                      ImagenPrendaOffline(p?.imagenUrl),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              p?.nombre ?? item.varianteId,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 5),
                            Text(
                              '${v?.talla ?? ''} · ${v?.color ?? ''}\nStock local ${c.datos.stock(item.varianteId)}',
                            ),
                            Text(
                              '× ${item.cantidad}',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Quitar prenda',
                        onPressed: r.guardando
                            ? null
                            : () => control.quitar(item.varianteId),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                );
              },
            ),
          OutlinedButton.icon(
            onPressed: r.guardando
                ? null
                : () => context.push('/sin-conexion/catalogo'),
            icon: const Icon(Icons.add),
            label: const Text('Elegir más prendas'),
          ),
          const SizedBox(height: 12),
          PanelOffline(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: c.sucursalId,
                  decoration: const InputDecoration(labelText: 'Sucursal'),
                  items: c.datos.sucursales
                      .map(
                        (s) => DropdownMenuItem(
                          value: s.id,
                          child: Text(s.nombre),
                        ),
                      )
                      .toList(),
                  onChanged: r.guardando
                      ? null
                      : (id) async {
                          if (id == null || id == c.sucursalId) return;
                          final confirmado = await showDialog<bool>(
                            context: context,
                            builder: (dialogo) => AlertDialog(
                              title: const Text('¿Cambiar de sucursal?'),
                              content: const Text(
                                'Vas a elegir nuevamente las prendas con las existencias de esa sucursal.',
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () =>
                                      Navigator.pop(dialogo, false),
                                  child: const Text('Volver'),
                                ),
                                FilledButton(
                                  onPressed: () => Navigator.pop(dialogo, true),
                                  child: const Text('Cambiar'),
                                ),
                              ],
                            ),
                          );
                          if (confirmado == true) {
                            control.vaciar();
                            await ref
                                .read(catalogoOfflineProvider.notifier)
                                .elegirSucursal(id);
                            if (context.mounted) {
                              context.go('/sin-conexion/catalogo');
                            }
                          }
                        },
                ),
                const SizedBox(height: 12),
                InkWell(
                  onTap: r.guardando ? null : () => _fecha(context, ref),
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'Fecha y hora de visita',
                      suffixIcon: Icon(Icons.calendar_month),
                    ),
                    child: Text(
                      r.agendadaPara == null
                          ? 'Elegir fecha y hora'
                          : fechaLocal(r.agendadaPara),
                    ),
                  ),
                ),
                if (usuario?.puede('reservations.write') == true) ...[
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    isExpanded: true,
                    initialValue: r.clienteId ?? '',
                    decoration: const InputDecoration(labelText: 'Cliente'),
                    items: [
                      const DropdownMenuItem(value: '', child: Text('Para mí')),
                      ...c.datos.clientes.map(
                        (cliente) => DropdownMenuItem(
                          value: cliente.id,
                          child: Text(
                            '${cliente.nombre} · …${cliente.documentoFinal ?? ''}',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ],
                    onChanged: r.guardando
                        ? null
                        : (id) => control.configurar(
                            clienteId: id,
                            limpiarCliente: id == null || id.isEmpty,
                          ),
                  ),
                ],
                const SizedBox(height: 12),
                TextFormField(
                  initialValue: r.notas,
                  maxLength: 1000,
                  maxLines: 3,
                  enabled: !r.guardando,
                  decoration: const InputDecoration(
                    labelText: 'Notas (opcional)',
                  ),
                  onChanged: (v) => control.configurar(notas: v),
                ),
              ],
            ),
          ),
          const AvisoOffline(
            'Se guardará en este teléfono. Está pendiente de sincronización y de confirmación por la tienda.',
            info: true,
          ),
          if (r.error != null) AvisoOffline(r.error!, peligro: true),
          FilledButton(
            onPressed: !puede || r.guardando || r.items.isEmpty
                ? null
                : () async {
                    final id = await control.confirmar();
                    if (id != null && context.mounted) {
                      context.go('/sin-conexion/reservas/$id');
                    }
                  },
            child: Text(
              r.guardando ? 'Guardando…' : 'Confirmar reserva sin conexión',
            ),
          ),
        ],
      ),
    );
  }
}
