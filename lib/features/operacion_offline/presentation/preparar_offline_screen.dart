import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/offline/base_local.dart';
import '../../../core/offline/conectividad.dart';
import '../../../shared/widgets/indicador_conexion.dart';
import '../../usuarios_catalogo/application/session_controller.dart';
import '../application/catalogo_offline_controller.dart';
import 'offline_widgets.dart';

final descargaAutomaticaProvider = FutureProvider<bool>(
  (ref) async =>
      (await ref.watch(baseLocalProvider).leerMeta('descarga_automatica')) !=
      'false',
);

class PrepararOfflineScreen extends ConsumerWidget {
  const PrepararOfflineScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final estado = ref.watch(catalogoOfflineProvider);
    final usuario = ref.watch(sessionProvider).usuario;
    final online = ref.watch(conectividadProvider).asData?.value == true;
    final control = ref.read(catalogoOfflineProvider.notifier);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sin conexión'),
        actions: const [IndicadorConexion()],
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
          if (usuario == null)
            AvisoOffline(
              'Iniciá sesión con conexión para preparar el catálogo de tu empresa.',
              info: true,
            ),
          if (usuario != null && !puedeOperarOffline(usuario))
            const AvisoOffline(
              'Tu suscripción permite consultar el catálogo guardado, pero no actualizarlo.',
              peligro: true,
            ),
          PanelOffline(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  estado.version == null
                      ? 'Preparar modo sin conexión'
                      : '● Listo para usar sin conexión',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                Text(
                  'Última descarga: ${fechaLocal(estado.descargadoEn)}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  '${estado.datos.productos.length} prendas · ${estado.datos.variantes.length} variantes',
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
                FilledButton.icon(
                  onPressed:
                      estado.descargando ||
                          !online ||
                          !puedeOperarOffline(usuario)
                      ? null
                      : () => control.descargar(),
                  icon: const Icon(Icons.download),
                  label: Text(
                    estado.descargando
                        ? 'Descargando…'
                        : estado.version == null
                        ? 'Descargar catálogo'
                        : 'Actualizar ahora',
                  ),
                ),
                if (estado.descargando) ...[
                  const SizedBox(height: 12),
                  LinearProgressIndicator(value: estado.progreso),
                  Text('${(estado.progreso * 100).round()} %'),
                ],
              ],
            ),
          ),
          if (estado.error != null) AvisoOffline(estado.error!, peligro: true),
          PanelOffline(
            child: SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text(
                'Descarga automática',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: const Text('Al iniciar sesión con Wi-Fi'),
              value:
                  ref.watch(descargaAutomaticaProvider).asData?.value ?? true,
              onChanged: (valor) async {
                await ref
                    .read(baseLocalProvider)
                    .guardarMeta('descarga_automatica', '$valor');
                ref.invalidate(descargaAutomaticaProvider);
              },
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
          OutlinedButton.icon(
            onPressed: () => context.push('/sin-conexion/catalogo'),
            icon: const Icon(Icons.grid_view),
            label: const Text('Ver catálogo guardado'),
          ),
          TextButton(
            onPressed: () => context.push('/sin-conexion/reservas'),
            child: const Text('Reservas en el teléfono'),
          ),
        ],
      ),
    );
  }
}
