import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../shared/widgets/indicador_conexion.dart';
import '../../usuarios_catalogo/application/session_controller.dart';
import '../application/catalogo_offline_controller.dart';
import '../application/reserva_offline_controller.dart';
import '../domain/catalogo_local.dart';
import 'offline_widgets.dart';

class CatalogoOfflineScreen extends ConsumerWidget {
  const CatalogoOfflineScreen({super.key});
  Future<void> _variantes(
    BuildContext context,
    WidgetRef ref,
    ProductoVista producto,
  ) async {
    final estado = ref.read(catalogoOfflineProvider);
    final permitido = puedeOperarOffline(ref.read(sessionProvider).usuario);
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (hoja) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                producto.producto.nombre,
                style: Theme.of(hoja).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              const Text('Elegí talla y color · existencia local conocida'),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: producto.variantes
                      .map(
                        (v) => ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text('${v.talla} · ${v.color}'),
                          subtitle: Text(
                            '${montoLocal(v.precio ?? producto.producto.precio)} · Stock ${estado.datos.stock(v.id)}',
                          ),
                          trailing: IconButton(
                            tooltip: 'Agregar a la reserva',
                            onPressed: permitido
                                ? () async {
                                    final error = ref
                                        .read(reservaOfflineProvider.notifier)
                                        .agregar(v);
                                    Navigator.pop(hoja);
                                    if (error != null && context.mounted) {
                                      final stock = estado.datos.stock(v.id);
                                      final sucursales = estado.datos.sucursales
                                          .where(
                                            (s) => s.id == estado.sucursalId,
                                          );
                                      await showModalBottomSheet<void>(
                                        context: context,
                                        showDragHandle: true,
                                        builder: (c) => SafeArea(
                                          child: Padding(
                                            padding: const EdgeInsets.all(20),
                                            child: Column(
                                              mainAxisSize: MainAxisSize.min,
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.stretch,
                                              children: [
                                                const Icon(
                                                  Icons.block,
                                                  color: Colors.red,
                                                  size: 32,
                                                ),
                                                const SizedBox(height: 14),
                                                Text(
                                                  error,
                                                  style: Theme.of(
                                                    c,
                                                  ).textTheme.titleMedium,
                                                ),
                                                const SizedBox(height: 12),
                                                Text(
                                                  '«${producto.producto.nombre} · ${v.talla}» tiene $stock unidades conocidas en ${sucursales.isEmpty ? 'la sucursal' : sucursales.first.nombre}.',
                                                ),
                                                const SizedBox(height: 16),
                                                FilledButton(
                                                  onPressed: () =>
                                                      Navigator.pop(c),
                                                  child: const Text(
                                                    'Elegir otra talla',
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      );
                                    }
                                  }
                                : null,
                            icon: const Icon(Icons.add_circle_outline),
                          ),
                        ),
                      )
                      .toList(),
                ),
              ),
              if (!permitido)
                const AvisoOffline(
                  'Tu suscripción permite consultar el catálogo. No puedes registrar reservas.',
                  peligro: true,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _filtros(BuildContext context, WidgetRef ref) async {
    final estado = ref.read(catalogoOfflineProvider);
    var f = estado.filtros;
    final minimo = TextEditingController(text: f.precioMin?.toString() ?? '');
    final maximo = TextEditingController(text: f.precioMax?.toString() ?? '');
    final categorias =
        estado.datos.productos
            .map((p) => p.categoria)
            .where((s) => s.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    final tallas = estado.datos.variantes.map((v) => v.talla).toSet().toList()
      ..sort();
    final colores = estado.datos.variantes.map((v) => v.color).toSet().toList()
      ..sort();
    final nuevo = await showModalBottomSheet<FiltrosOffline>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (hoja) => StatefulBuilder(
        builder: (c, set) => SafeArea(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              20,
              0,
              20,
              20 + MediaQuery.viewInsetsOf(c).bottom,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Filtros', style: Theme.of(c).textTheme.titleLarge),
                const SizedBox(height: 14),
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: f.categoria,
                  decoration: const InputDecoration(labelText: 'Categoría'),
                  items: [
                    const DropdownMenuItem(value: '', child: Text('Todas')),
                    ...categorias.map(
                      (v) => DropdownMenuItem(value: v, child: Text(v)),
                    ),
                  ],
                  onChanged: (v) => set(() => f = f.copyWith(categoria: v)),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        isExpanded: true,
                        initialValue: f.talla,
                        decoration: const InputDecoration(labelText: 'Talla'),
                        items: [
                          const DropdownMenuItem(
                            value: '',
                            child: Text('Todas'),
                          ),
                          ...tallas.map(
                            (v) => DropdownMenuItem(value: v, child: Text(v)),
                          ),
                        ],
                        onChanged: (v) => set(() => f = f.copyWith(talla: v)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        isExpanded: true,
                        initialValue: f.color,
                        decoration: const InputDecoration(labelText: 'Color'),
                        items: [
                          const DropdownMenuItem(
                            value: '',
                            child: Text('Todos'),
                          ),
                          ...colores.map(
                            (v) => DropdownMenuItem(value: v, child: Text(v)),
                          ),
                        ],
                        onChanged: (v) => set(() => f = f.copyWith(color: v)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: minimo,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Desde Bs',
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: maximo,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Hasta Bs',
                        ),
                      ),
                    ),
                  ],
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Solo en oferta'),
                  value: f.soloOferta,
                  onChanged: (v) => set(() => f = f.copyWith(soloOferta: v)),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Solo con stock local'),
                  value: f.soloConStock,
                  onChanged: (v) => set(() => f = f.copyWith(soloConStock: v)),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(
                    hoja,
                    FiltrosOffline(
                      texto: f.texto,
                      categoria: f.categoria,
                      talla: f.talla,
                      color: f.color,
                      precioMin: double.tryParse(
                        minimo.text.replaceAll(',', '.'),
                      ),
                      precioMax: double.tryParse(
                        maximo.text.replaceAll(',', '.'),
                      ),
                      soloOferta: f.soloOferta,
                      soloConStock: f.soloConStock,
                    ),
                  ),
                  child: const Text('Aplicar filtros'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(hoja, const FiltrosOffline()),
                  child: const Text('Limpiar filtros'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    // Los controladores siguen vivos hasta que termina la animación de la hoja.
    Future<void>.delayed(const Duration(milliseconds: 400), () {
      minimo.dispose();
      maximo.dispose();
    });
    if (nuevo != null) {
      ref.read(catalogoOfflineProvider.notifier).aplicarFiltros(nuevo);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final estado = ref.watch(catalogoOfflineProvider);
    final reserva = ref.watch(reservaOfflineProvider);
    final control = ref.read(catalogoOfflineProvider.notifier);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Catálogo'),
        actions: [
          IconButton(
            tooltip: 'Preparar modo sin conexión',
            onPressed: () => context.push('/sin-conexion'),
            icon: const Icon(Icons.download_outlined),
          ),
          const IndicadorConexion(),
        ],
      ),
      floatingActionButton: reserva.items.isEmpty
          ? null
          : FloatingActionButton.extended(
              onPressed: () => context.push('/sin-conexion/reservar'),
              icon: const Icon(Icons.event_available),
              label: Text(
                'Reserva (${reserva.items.fold<int>(0, (n, i) => n + i.cantidad)})',
              ),
            ),
      body: estado.cargando
          ? const Center(child: CircularProgressIndicator())
          : estado.version == null
          ? EstadoVacioOffline(accion: () => context.push('/sin-conexion'))
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
              children: [
                if (estado.desactualizado)
                  AvisoOffline(
                    'La información puede estar desactualizada\nPasaron ${DateTime.now().difference(estado.descargadoEn!).inHours} horas desde la última descarga.',
                  ),
                Text(
                  'Última descarga: ${fechaLocal(estado.descargadoEn)}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 10),
                TextField(
                  decoration: const InputDecoration(
                    hintText: 'Buscar prendas',
                    prefixIcon: Icon(Icons.search),
                  ),
                  onChanged: (v) =>
                      control.aplicarFiltros(estado.filtros.copyWith(texto: v)),
                ),
                const SizedBox(height: 10),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      ActionChip(
                        label: const Text('Todas'),
                        onPressed: () =>
                            control.aplicarFiltros(const FiltrosOffline()),
                      ),
                      const SizedBox(width: 6),
                      FilterChip(
                        label: const Text('En oferta'),
                        selected: estado.filtros.soloOferta,
                        onSelected: (v) => control.aplicarFiltros(
                          estado.filtros.copyWith(soloOferta: v),
                        ),
                      ),
                      const SizedBox(width: 6),
                      ActionChip(
                        avatar: const Icon(Icons.tune, size: 16),
                        label: Text(
                          estado.filtros.talla.isEmpty
                              ? 'Filtros'
                              : 'Talla ${estado.filtros.talla}',
                        ),
                        onPressed: () => _filtros(context, ref),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                if (estado.vista.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(32),
                    child: Text(
                      'No hay prendas para esos filtros.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                for (final p in estado.vista)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Card(
                      margin: EdgeInsets.zero,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () => _variantes(context, ref, p),
                        child: Padding(
                          padding: const EdgeInsets.all(10),
                          child: Row(
                            children: [
                              ImagenPrendaOffline(p.producto.imagenUrl),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      p.producto.nombre,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Tallas ${p.variantes.map((v) => v.talla).toSet().join(' · ')}',
                                      style: Theme.of(
                                        context,
                                      ).textTheme.bodySmall,
                                    ),
                                    const SizedBox(height: 5),
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            montoLocal(p.producto.precio),
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                        Text(
                                          '● Stock ${p.stock}',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: p.stock == 0
                                                ? Theme.of(
                                                    context,
                                                  ).colorScheme.onSurfaceVariant
                                                : p.stock <= 4
                                                ? const Color(0xFFA86A12)
                                                : const Color(0xFF2F7D55),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}
