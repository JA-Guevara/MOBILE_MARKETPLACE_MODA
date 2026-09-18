import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../application/catalog_controller.dart';
import '../domain/producto.dart';

/// Portada de la app: el catálogo (RF07).
///
/// Es la página de inicio de la web (`catalog-page.component.ts`) adaptada a un
/// teléfono: en vez de una grilla con paginado, carga de a páginas mientras se
/// hace scroll. La búsqueda y los filtros quedan arriba y se aplican de una.
class CatalogScreen extends ConsumerStatefulWidget {
  const CatalogScreen({super.key});

  @override
  ConsumerState<CatalogScreen> createState() => _CatalogScreenState();
}

class _CatalogScreenState extends ConsumerState<CatalogScreen> {
  final _scroll = ScrollController();
  final _busqueda = TextEditingController();
  bool _filtrosVisibles = false;

  @override
  void initState() {
    super.initState();
    _busqueda.text = ref.read(catalogProvider).filtros.busqueda;
    _scroll.addListener(_alLlegarAbajo);
    Future.microtask(() => ref.read(catalogProvider.notifier).iniciar());
  }

  @override
  void dispose() {
    _scroll
      ..removeListener(_alLlegarAbajo)
      ..dispose();
    _busqueda.dispose();
    super.dispose();
  }

  void _alLlegarAbajo() {
    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 400) {
      ref.read(catalogProvider.notifier).cargarMas();
    }
  }

  void _aplicarFiltros({FiltrosCatalogo? cambios}) {
    final actuales = ref.read(catalogProvider).filtros;
    ref.read(catalogProvider.notifier).aplicarFiltros(
          cambios ?? actuales.copyWith(busqueda: _busqueda.text.trim()),
        );
  }

  void _limpiar() {
    _busqueda.clear();
    ref.read(catalogProvider.notifier).aplicarFiltros(const FiltrosCatalogo());
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final estado = ref.watch(catalogProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('FashionStore')),
      body: RefreshIndicator(
        onRefresh: () => ref.read(catalogProvider.notifier).cargarInicial(),
        child: CustomScrollView(
          controller: _scroll,
          slivers: [
            SliverToBoxAdapter(child: _Hero(tema: tema, total: estado.total)),
            SliverToBoxAdapter(
              child: _Filtros(
                busqueda: _busqueda,
                estado: estado,
                visibles: _filtrosVisibles,
                alternarVisibles: () =>
                    setState(() => _filtrosVisibles = !_filtrosVisibles),
                onBuscar: () => _aplicarFiltros(),
                onLimpiar: _limpiar,
                onCategoria: (id) => _aplicarFiltros(
                  cambios: estado.filtros.copyWith(categoriaId: id),
                ),
                onDestacadas: (valor) => _aplicarFiltros(
                  cambios: estado.filtros.copyWith(soloDestacadas: valor),
                ),
              ),
            ),
            if (estado.cargando)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(child: CircularProgressIndicator()),
              )
            else if (estado.error != null && estado.productos.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: _Error(
                  mensaje: estado.error!,
                  onReintentar: () => ref.read(catalogProvider.notifier).reintentar(),
                ),
              )
            else if (estado.productos.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: _Vacio(onLimpiar: _limpiar),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                sliver: SliverGrid(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: 16,
                    crossAxisSpacing: 12,
                    childAspectRatio: 0.62,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (context, indice) => _TarjetaProducto(producto: estado.productos[indice]),
                    childCount: estado.productos.length,
                  ),
                ),
              ),
            if (estado.cargandoMas)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                ),
              ),
            if (estado.error != null && estado.productos.isNotEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: _Error(
                    mensaje: estado.error!,
                    onReintentar: () => ref.read(catalogProvider.notifier).cargarMas(),
                  ),
                ),
              ),
            if (estado.recomendados.isNotEmpty)
              SliverToBoxAdapter(child: _Recomendados(items: estado.recomendados)),
            const SliverToBoxAdapter(child: SizedBox(height: 24)),
          ],
        ),
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({required this.tema, required this.total});

  final ThemeData tema;
  final int total;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: tema.colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('FASHIONSTORE · HECHO PARA TU DÍA', style: tema.textTheme.labelSmall),
          const SizedBox(height: 8),
          Text('Vestí tu propia historia.', style: tema.textTheme.headlineSmall),
          const SizedBox(height: 8),
          const Text('Prendas que acompañan tu ritmo. Encontrá lo que va con vos.'),
        ],
      ),
    );
  }
}

class _Filtros extends StatelessWidget {
  const _Filtros({
    required this.busqueda,
    required this.estado,
    required this.visibles,
    required this.alternarVisibles,
    required this.onBuscar,
    required this.onLimpiar,
    required this.onCategoria,
    required this.onDestacadas,
  });

  final TextEditingController busqueda;
  final EstadoCatalogo estado;
  final bool visibles;
  final VoidCallback alternarVisibles;
  final VoidCallback onBuscar;
  final VoidCallback onLimpiar;
  final ValueChanged<String> onCategoria;
  final ValueChanged<bool> onDestacadas;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: busqueda,
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => onBuscar(),
                  decoration: InputDecoration(
                    hintText: 'Buscar una prenda',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: IconButton(
                      onPressed: onBuscar,
                      icon: const Icon(Icons.arrow_forward),
                      tooltip: 'Buscar',
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                onPressed: alternarVisibles,
                icon: Icon(visibles ? Icons.filter_list_off : Icons.filter_list),
                tooltip: visibles ? 'Ocultar filtros' : 'Buscar y filtrar',
              ),
            ],
          ),
          TextButton(
            onPressed: alternarVisibles,
            child: Text(visibles ? 'Ocultar filtros' : 'Categorías y filtros'),
          ),
          if (visibles) ...[
            if (estado.categorias.isNotEmpty)
              SizedBox(
                height: 40,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: estado.categorias.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (context, indice) {
                    final categoria = estado.categorias[indice];
                    final elegida = estado.filtros.categoriaId == categoria.id;
                    return ChoiceChip(
                      label: Text(categoria.nombre),
                      selected: elegida,
                      onSelected: (_) => onCategoria(elegida ? '' : categoria.id),
                    );
                  },
                ),
              ),
            const SizedBox(height: 4),
            Row(
              children: [
                FilterChip(
                  label: const Text('Solo destacadas'),
                  selected: estado.filtros.soloDestacadas,
                  onSelected: onDestacadas,
                ),
                const Spacer(),
                TextButton(onPressed: onLimpiar, child: const Text('Limpiar')),
              ],
            ),
          ],
          const SizedBox(height: 8),
          Row(
            children: [
              Text('El catálogo', style: tema.textTheme.titleLarge),
              const Spacer(),
              Text('${estado.total} prendas', style: tema.textTheme.bodySmall),
            ],
          ),
        ],
      ),
    );
  }
}

class _TarjetaProducto extends StatelessWidget {
  const _TarjetaProducto({required this.producto});

  final Producto producto;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return InkWell(
      onTap: () => context.push('/prendas/${producto.slug}'),
      borderRadius: BorderRadius.circular(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (producto.imagenUrl != null)
                    CachedNetworkImage(
                      imageUrl: producto.imagenUrl!,
                      fit: BoxFit.cover,
                      placeholder: (_, __) => Container(color: tema.colorScheme.surfaceContainerHighest),
                      errorWidget: (_, __, ___) => _SinImagen(tema: tema),
                    )
                  else
                    _SinImagen(tema: tema),
                  if (producto.destacado)
                    const Positioned(
                      top: 8,
                      left: 8,
                      child: _Etiqueta(texto: 'Destacada'),
                    ),
                  if (producto.tieneVestidor)
                    const Positioned(
                      top: 8,
                      right: 8,
                      child: _Etiqueta(texto: 'Probador'),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(producto.categoria.toUpperCase(), style: tema.textTheme.labelSmall),
          Text(
            producto.nombre,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: tema.textTheme.titleSmall,
          ),
          const SizedBox(height: 4),
          Text('Bs ${producto.precioBase.toStringAsFixed(2)}',
              style: tema.textTheme.bodyMedium),
        ],
      ),
    );
  }
}

class _SinImagen extends StatelessWidget {
  const _SinImagen({required this.tema});

  final ThemeData tema;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: tema.colorScheme.surfaceContainerHighest,
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('F.', style: tema.textTheme.headlineMedium),
          Text('Imagen no disponible', style: tema.textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _Etiqueta extends StatelessWidget {
  const _Etiqueta({required this.texto});

  final String texto;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: tema.colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(30),
      ),
      child: Text(texto, style: tema.textTheme.labelSmall),
    );
  }
}

class _Recomendados extends StatelessWidget {
  const _Recomendados({required this.items});

  final List<Recomendado> items;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
          child: Text('Recomendado para vos', style: tema.textTheme.titleLarge),
        ),
        SizedBox(
          height: 220,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (context, indice) {
              final item = items[indice];
              return SizedBox(
                width: 140,
                child: InkWell(
                  onTap: () => context.push('/prendas/${item.slug}'),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: SizedBox(
                          height: 140,
                          width: 140,
                          child: item.imagenUrl != null
                              ? CachedNetworkImage(
                                  imageUrl: item.imagenUrl!,
                                  fit: BoxFit.cover,
                                  errorWidget: (_, __, ___) => _SinImagen(tema: tema),
                                )
                              : _SinImagen(tema: tema),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(item.categoria.toUpperCase(), style: tema.textTheme.labelSmall),
                      Text(item.nombre,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: tema.textTheme.titleSmall),
                      Text('Bs ${item.precioBase.toStringAsFixed(2)}',
                          style: tema.textTheme.bodySmall),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _Error extends StatelessWidget {
  const _Error({required this.mensaje, required this.onReintentar});

  final String mensaje;
  final VoidCallback onReintentar;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(mensaje, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton.tonal(
              onPressed: onReintentar,
              child: Text('Reintentar',
                  style: TextStyle(color: tema.colorScheme.error)),
            ),
          ],
        ),
      ),
    );
  }
}

class _Vacio extends StatelessWidget {
  const _Vacio({required this.onLimpiar});

  final VoidCallback onLimpiar;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Todavía no hay prendas para mostrar'),
            const SizedBox(height: 8),
            const Text('Probá cambiar los filtros o volvé más tarde.'),
            const SizedBox(height: 12),
            FilledButton.tonal(onPressed: onLimpiar, child: const Text('Ver todo')),
          ],
        ),
      ),
    );
  }
}