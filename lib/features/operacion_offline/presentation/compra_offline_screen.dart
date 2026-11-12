import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/offline/conectividad.dart';
import '../../../shared/widgets/indicador_conexion.dart';
import '../application/catalogo_offline_controller.dart';
import '../application/compra_offline_controller.dart';
import '../application/sincronizacion_controller.dart';
import '../domain/compra_local.dart';
import 'offline_widgets.dart';

String _bs(double amount) =>
    'Bs ${amount.toStringAsFixed(2).replaceAll('.', ',')}';

class CompraOfflineScreen extends ConsumerWidget {
  const CompraOfflineScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final estado = ref.watch(compraOfflineProvider);
    final catalogo = ref.watch(catalogoOfflineProvider);
    final control = ref.read(compraOfflineProvider.notifier);
    final online = ref.watch(conectividadProvider).valueOrNull ?? false;

    Future<void> guardar() async {
      final compra = await control.guardar();
      if (compra == null || !context.mounted) return;
      if (online) {
        unawaited(
          ref
              .read(sincronizacionControllerProvider.notifier)
              .sincronizarAhora(),
        );
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Comprar sin conexión'),
        actions: const [IndicadorConexion()],
      ),
      body: catalogo.cargando
          ? const Center(child: CircularProgressIndicator())
          : catalogo.version == null
          ? const Padding(
              padding: EdgeInsets.all(20),
              child: AvisoOffline(
                'Todavía no hay catálogo en este dispositivo. Se descargará solo cuando haya conexión.',
                info: true,
              ),
            )
          : estado.compraGuardada != null
          ? _CompraGuardada(
              compra: estado.compraGuardada!,
              nueva: control.nuevaCompra,
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  'Mi compra',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 10),
                if (estado.items.isEmpty)
                  const AvisoOffline(
                    'Todavía no agregaste prendas. Elegilas desde el catálogo.',
                    info: true,
                  )
                else
                  for (final item in estado.items)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    item.productoNombre,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  Text(
                                    '${item.varianteDesc} · ${_bs(item.precioUnitario)}',
                                  ),
                                  Text('Disponible ${item.stockDisponible}'),
                                ],
                              ),
                            ),
                            IconButton(
                              onPressed: () => control.cambiarCantidad(
                                item.varianteId,
                                item.cantidad - 1,
                              ),
                              icon: const Icon(Icons.remove),
                            ),
                            Text('${item.cantidad}'),
                            IconButton(
                              onPressed: () => control.cambiarCantidad(
                                item.varianteId,
                                item.cantidad + 1,
                              ),
                              icon: const Icon(Icons.add),
                            ),
                            IconButton(
                              tooltip: 'Quitar',
                              onPressed: () => control.quitar(item.varianteId),
                              icon: const Icon(Icons.delete_outline),
                            ),
                          ],
                        ),
                      ),
                    ),
                if (estado.items.isNotEmpty)
                  Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      'Total estimado  ${_bs(estado.total)}',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: estado.sucursalId,
                  decoration: const InputDecoration(labelText: 'Retiro en'),
                  items: catalogo.datos.sucursales
                      .map(
                        (s) => DropdownMenuItem(
                          value: s.id,
                          child: Text(s.nombre),
                        ),
                      )
                      .toList(),
                  onChanged: estado.guardando
                      ? null
                      : (id) async {
                          if (id == null) return;
                          await ref
                              .read(catalogoOfflineProvider.notifier)
                              .elegirSucursal(id);
                          control.configurar(sucursalId: id);
                        },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  initialValue: estado.contactoNombre,
                  decoration: const InputDecoration(labelText: 'Nombre'),
                  onChanged: (value) =>
                      control.configurar(contactoNombre: value),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  initialValue: estado.contactoTelefono,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(labelText: 'Teléfono'),
                  onChanged: (value) =>
                      control.configurar(contactoTelefono: value),
                ),
                const SizedBox(height: 12),
                const Text('Forma de pago'),
                RadioGroup<String>(
                  groupValue: estado.formaPago,
                  onChanged: (value) => control.configurar(formaPago: value),
                  child: Column(
                    children: [
                      const RadioListTile<String>(
                        contentPadding: EdgeInsets.zero,
                        title: Text('Tarjeta al reconectar'),
                        value: 'TARJETA_AL_RECONECTAR',
                      ),
                      const RadioListTile<String>(
                        contentPadding: EdgeInsets.zero,
                        title: Text('Efectivo al retirar'),
                        value: 'EFECTIVO_AL_RETIRAR',
                      ),
                    ],
                  ),
                ),
                TextFormField(
                  initialValue: estado.notas,
                  maxLength: 500,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Nota (opcional)',
                  ),
                  onChanged: (value) => control.configurar(notas: value),
                ),
                const AvisoOffline(
                  'Todavía no se cobra nada. Al volver la conexión confirmamos existencia y precio.',
                  info: true,
                ),
                if (estado.error != null)
                  AvisoOffline(estado.error!, peligro: true),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: estado.guardando || estado.items.isEmpty
                      ? null
                      : guardar,
                  icon: const Icon(Icons.save_outlined),
                  label: Text(
                    estado.guardando ? 'Guardando…' : 'Guardar mi compra',
                  ),
                ),
                TextButton(
                  onPressed: () => context.go('/sin-conexion/catalogo'),
                  child: const Text('Seguir viendo catálogo'),
                ),
              ],
            ),
    );
  }
}

class _CompraGuardada extends StatelessWidget {
  const _CompraGuardada({required this.compra, required this.nueva});
  final CompraLocal compra;
  final VoidCallback nueva;
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.check_circle_outline, size: 56, color: Colors.green),
          const SizedBox(height: 12),
          Text(
            'Compra guardada en este dispositivo · ${compra.folio}',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          const Text(
            'Se enviará sola cuando haya conexión.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          FilledButton.tonal(
            onPressed: () => context.go('/sin-conexion/operaciones'),
            child: const Text('Ver mis operaciones'),
          ),
          TextButton(onPressed: nueva, child: const Text('Nueva compra')),
        ],
      ),
    ),
  );
}
