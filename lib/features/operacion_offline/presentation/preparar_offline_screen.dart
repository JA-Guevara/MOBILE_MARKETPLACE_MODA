import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/offline/base_local.dart';
import '../../../core/offline/conectividad.dart';
import '../../../shared/widgets/indicador_conexion.dart';
import '../../usuarios_catalogo/application/session_controller.dart';
import '../application/catalogo_auto_sync.dart';
import '../application/catalogo_offline_controller.dart';
import '../application/sincronizacion_controller.dart';
import 'offline_widgets.dart';

final descargaAutomaticaProvider = FutureProvider<bool>(
  (ref) async =>
      (await ref.watch(baseLocalProvider).leerMeta('descarga_automatica')) !=
      'false',
);

final imagenesConDatosProvider = FutureProvider<bool>(
  (ref) async =>
      (await ref.watch(baseLocalProvider).leerMeta('imagenes_con_datos')) ==
      'true',
);

class PrepararOfflineScreen extends ConsumerWidget {
  const PrepararOfflineScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final estado = ref.watch(catalogoOfflineProvider);
    final usuario = ref.watch(sessionProvider).usuario;
    final sync = usuario?.puede('sync.write') == true
        ? ref.watch(sincronizacionControllerProvider)
        : null;
    final online = ref.watch(conectividadProvider).valueOrNull ?? true;
    final control = ref.read(catalogoOfflineProvider.notifier);

    final sinSucursales =
        estado.error?.toLowerCase().contains('no tiene sucursales') == true ||
        estado.error?.toLowerCase().contains('no_authorized_branches') == true;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Datos sin conexión'),
        actions: const [IndicadorConexion()],
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(36),
          child: IndicadorSincronizacion(),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (usuario?.empresa != null)
            Text(
              usuario!.empresa!.nombre,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          const SizedBox(height: 12),
          if (sync != null)
            PanelOffline(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('${sync.pendientes} operaciones pendientes'),
                  if (sync.ultimoError != null) Text(sync.ultimoError!),
                  FilledButton.icon(
                    onPressed:
                        !online ||
                            sync.sincronizando ||
                            sync.reintentarEn != null
                        ? null
                        : () => ref
                              .read(sincronizacionControllerProvider.notifier)
                              .sincronizarAhora(),
                    icon: const Icon(Icons.sync),
                    label: Text(
                      sync.sincronizando
                          ? 'Sincronizando…'
                          : 'Sincronizar pendientes',
                    ),
                  ),
                ],
              ),
            ),
          if (usuario == null) ...[
            const AvisoOffline(
              'Iniciá sesión con conexión para descargar el catálogo de tu empresa.',
              info: true,
            ),
            const SizedBox(height: 8),
            FilledButton.tonalIcon(
              onPressed: () =>
                  context.push('/iniciar-sesion?volverA=/sin-conexion'),
              icon: const Icon(Icons.login),
              label: const Text('Iniciar sesión en mi tienda'),
            ),
            const SizedBox(height: 12),
          ],
          if (usuario != null && !puedeOperarOffline(usuario))
            const AvisoOffline(
              'Tu plan no incluye la operación sin conexión.',
              peligro: true,
            ),
          if (sinSucursales)
            const AvisoOffline(
              'Tu usuario no tiene sucursales asignadas. Pedile al administrador que te asigne una.',
              peligro: true,
            ),
          if (estado.error != null &&
              !sinSucursales &&
              estado.descargadoEn != null)
            AvisoOffline(
              'No se pudo actualizar. Seguís usando los datos del ${fechaLocal(estado.descargadoEn)}. Se reintentará solo.',
              info: true,
            )
          else if (estado.error != null && !sinSucursales)
            AvisoOffline(estado.error!, peligro: true),
          PanelOffline(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        estado.descargando
                            ? 'Descargando…'
                            : estado.version != null
                            ? 'Listo para usar sin conexión'
                            : 'Aún no preparado',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              color: estado.version != null
                                  ? Colors.green.shade700
                                  : null,
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                    ),
                    const Text(
                      'Se actualiza solo con red',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  'Última descarga: ${fechaLocal(estado.descargadoEn)}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  '${estado.datos.productos.length} prendas · ${estado.datos.variantes.length} variantes · ${estado.datos.clientes.length} clientes',
                ),
                if (estado.datos.sucursales.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: DropdownButtonFormField<String>(
                      isExpanded: true,
                      initialValue: estado.sucursalId,
                      decoration: const InputDecoration(
                        labelText: 'Sucursal para descargar',
                      ),
                      items: estado.datos.sucursales
                          .map(
                            (s) => DropdownMenuItem(
                              value: s.id,
                              child: Text(s.nombre),
                            ),
                          )
                          .toList(),
                      onChanged: estado.descargando || !online
                          ? null
                          : (id) {
                              if (id != null) control.descargar(sucursalId: id);
                            },
                    ),
                  ),
                const SizedBox(height: 14),
                OutlinedButton.icon(
                  onPressed:
                      estado.descargando ||
                          !online ||
                          !puedeOperarOffline(usuario)
                      ? null
                      : () => ref
                            .read(catalogoAutoSyncProvider)
                            .notificar('manual'),
                  icon: const Icon(Icons.download),
                  label: Text(
                    estado.descargando ? 'Descargando…' : 'Actualizar ahora',
                  ),
                ),
                if (estado.descargando) ...[
                  const SizedBox(height: 12),
                  const Text('Descargando el catálogo de tu empresa…'),
                  const SizedBox(height: 4),
                  LinearProgressIndicator(value: estado.progreso),
                  Text('${(estado.progreso * 100).round()} %'),
                ],
              ],
            ),
          ),
          PanelOffline(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Descarga automática',
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    'Actualizar catálogo con Wi-Fi o datos móviles',
                    style: TextStyle(fontSize: 14),
                  ),
                  subtitle: const Text(
                    'Al iniciar sesión, volver a la app, reconectar y cada 5 minutos.',
                  ),
                  value:
                      ref.watch(descargaAutomaticaProvider).asData?.value ??
                      true,
                  onChanged: (valor) async {
                    await ref
                        .read(baseLocalProvider)
                        .guardarMeta('descarga_automatica', '$valor');
                    ref.invalidate(descargaAutomaticaProvider);
                  },
                ),
                const Divider(),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    'Descargar imágenes también con datos móviles',
                    style: TextStyle(fontSize: 14),
                  ),
                  subtitle: const Text(
                    'Controla las imágenes; el catálogo puede actualizarse con cualquier red.',
                  ),
                  value:
                      ref.watch(imagenesConDatosProvider).asData?.value ??
                      false,
                  onChanged: (valor) async {
                    await ref
                        .read(baseLocalProvider)
                        .guardarMeta('imagenes_con_datos', '$valor');
                    ref.invalidate(imagenesConDatosProvider);
                  },
                ),
              ],
            ),
          ),
          PanelOffline(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Datos guardados',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Prendas'),
                  trailing: Text('${estado.datos.productos.length}'),
                ),
                const Divider(height: 1),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Variantes'),
                  trailing: Text('${estado.datos.variantes.length}'),
                ),
                const Divider(height: 1),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Clientes'),
                  trailing: Text('${estado.datos.clientes.length}'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () => context.push('/sin-conexion/catalogo'),
            icon: const Icon(Icons.grid_view),
            label: const Text('Abrir catálogo →'),
          ),
          if (usuario?.puede('commerce.write') == true) ...[
            const SizedBox(height: 6),
            FilledButton.icon(
              onPressed: () => context.push('/sin-conexion/venta'),
              icon: const Icon(Icons.point_of_sale),
              label: const Text('Caja de tienda · contado →'),
            ),
          ],
          const SizedBox(height: 6),
          FilledButton.tonalIcon(
            onPressed: () => context.push('/sin-conexion/reservas'),
            icon: const Icon(Icons.event_available),
            label: const Text('Reservas en el teléfono'),
          ),
          const SizedBox(height: 6),
          OutlinedButton.icon(
            onPressed: () => context.push('/sin-conexion/operaciones'),
            icon: const Icon(Icons.sync_problem_outlined),
            label: const Text('Operaciones →'),
          ),
        ],
      ),
    );
  }
}
