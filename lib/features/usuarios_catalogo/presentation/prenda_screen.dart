import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../reservas_vestidor/application/reservas_controller.dart';
import '../../reservas_vestidor/domain/reserva.dart';
import '../../../shared/formato.dart';
import '../../../shared/widgets/estado_vista.dart';
import '../application/prenda_controller.dart';
import '../domain/producto.dart';

/// Detalle de una prenda (`/prendas/:slug`).
///
/// Es `product-page.component.ts` de la web adaptado al teléfono: la web pone
/// la galería a la izquierda y los datos a la derecha; acá va todo en una
/// columna, con las fotos arriba y las acciones fijas abajo para que estén
/// siempre al alcance del pulgar sin tener que volver a subir.
class PrendaScreen extends ConsumerWidget {
  const PrendaScreen({super.key, required this.slug, this.paraReserva = false});

  final String slug;
  final bool paraReserva;

  /// Las tres acciones que exigen cuenta mandan al login guardando a dónde
  /// volver, igual que el `returnUrl` de la web.
  void _pedirSesion(BuildContext context) {
    final destino = Uri.encodeComponent('/prendas/$slug');
    context.push('/iniciar-sesion?volverA=$destino');
  }

  /// Ejecuta una acción y avisa el resultado **encima** de la pantalla.
  ///
  /// El botón de comprar vive en la barra fija de abajo, así que un mensaje
  /// dibujado en el cuerpo de la ficha cae fuera de la vista: se toca el botón
  /// y parece que no pasó nada. Un `SnackBar` siempre se ve.
  Future<void> _conAviso(
    BuildContext context,
    WidgetRef ref,
    Future<bool> Function() accion, {
    required String exito,
    SnackBarAction Function(BuildContext)? luego,
  }) async {
    if (!await accion()) {
      if (context.mounted) _pedirSesion(context);
      return;
    }
    if (!context.mounted) return;
    final error = ref.read(prendaProvider(slug)).errorAccion;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(error ?? exito),
          action: error == null ? luego?.call(context) : null,
        ),
      );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final estado = ref.watch(prendaProvider(slug));
    final control = ref.read(prendaProvider(slug).notifier);
    final producto = estado.producto;

    if (estado.cargando && producto == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Prenda')),
        body: const VistaCargando(mensaje: 'Buscando la prenda…'),
      );
    }

    if (producto == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Prenda')),
        body: VistaError(
          mensaje: estado.error ?? 'No encontramos esta prenda.',
          onReintentar: () => control.cargar(slug),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(
          producto.nombre,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            onPressed: () => context.go('/carrito'),
            icon: const Icon(Icons.shopping_bag_outlined),
            tooltip: 'Ver carrito',
          ),
          IconButton(
            onPressed: estado.ocupado
                ? null
                : () => _conAviso(
                    context,
                    ref,
                    control.alternarFavorito,
                    exito: estado.favorito
                        ? 'La quitamos de tus favoritos.'
                        : 'La guardamos en favoritos.',
                  ),
            icon: Icon(
              estado.favorito ? Icons.favorite : Icons.favorite_border,
            ),
            tooltip: estado.favorito
                ? 'Quitar de favoritos'
                : 'Guardar en favoritos',
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            _Galeria(
              imagenes: producto.imagenes,
              actual: estado.imagen,
              onVer: control.verImagen,
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: _Ficha(
                estado: estado,
                producto: producto,
                control: control,
                paraReserva: paraReserva,
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: _Acciones(
        estado: estado,
        slug: slug,
        onAgregar: () => _conAviso(
          context,
          ref,
          control.agregarAlCarrito,
          exito: 'Agregamos la prenda a tu carrito.',
          luego: (context) => SnackBarAction(
            label: 'Ver carrito',
            onPressed: () => context.go('/carrito'),
          ),
        ),
      ),
    );
  }
}

/// Carrusel de fotos. Sin fotos muestra el mismo marcador que el catálogo, en
/// vez de dejar un hueco que parece un error de carga.
class _Galeria extends StatefulWidget {
  const _Galeria({
    required this.imagenes,
    required this.actual,
    required this.onVer,
  });

  final List<String> imagenes;
  final int actual;
  final ValueChanged<int> onVer;

  @override
  State<_Galeria> createState() => _GaleriaState();
}

class _GaleriaState extends State<_Galeria> {
  late final PageController _paginas = PageController(
    initialPage: widget.actual,
  );

  @override
  void didUpdateWidget(_Galeria anterior) {
    super.didUpdateWidget(anterior);
    // La foto puede cambiar desde las miniaturas, no solo deslizando.
    if (widget.actual != anterior.actual && _paginas.hasClients) {
      _paginas.animateToPage(
        widget.actual,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  void dispose() {
    _paginas.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    if (widget.imagenes.isEmpty) {
      return SizedBox(
        height: 360,
        child: Container(
          color: tema.colorScheme.surfaceContainerHighest,
          alignment: Alignment.center,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('F.', style: tema.textTheme.headlineMedium),
              Text('Imagen no disponible', style: tema.textTheme.bodySmall),
            ],
          ),
        ),
      );
    }

    return Column(
      children: [
        SizedBox(
          height: 360,
          child: PageView.builder(
            controller: _paginas,
            onPageChanged: widget.onVer,
            itemCount: widget.imagenes.length,
            itemBuilder: (context, indice) => CachedNetworkImage(
              imageUrl: widget.imagenes[indice],
              fit: BoxFit.cover,
              placeholder: (_, __) =>
                  Container(color: tema.colorScheme.surfaceContainerHighest),
              errorWidget: (_, __, ___) => Container(
                color: tema.colorScheme.surfaceContainerHighest,
                alignment: Alignment.center,
                child: const Icon(Icons.broken_image_outlined),
              ),
            ),
          ),
        ),
        if (widget.imagenes.length > 1)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < widget.imagenes.length; i++)
                  GestureDetector(
                    onTap: () => widget.onVer(i),
                    child: Container(
                      width: i == widget.actual ? 20 : 8,
                      height: 8,
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      decoration: BoxDecoration(
                        color: i == widget.actual
                            ? tema.colorScheme.primary
                            : tema.colorScheme.outline,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Nombre, precio, selectores de talla y color, descripción y datos.
class _Ficha extends ConsumerWidget {
  const _Ficha({
    required this.estado,
    required this.producto,
    required this.control,
    required this.paraReserva,
  });

  final EstadoPrenda estado;
  final Producto producto;
  final PrendaController control;
  final bool paraReserva;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tema = Theme.of(context);
    final variante = estado.variante;
    final sinCombinacion =
        estado.talla.isNotEmpty && estado.color.isNotEmpty && variante == null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (producto.categoria.isNotEmpty)
          Text(
            producto.categoria.toUpperCase(),
            style: tema.textTheme.labelSmall,
          ),
        Text(producto.nombre, style: tema.textTheme.headlineSmall),
        if (producto.marca.isNotEmpty)
          Text(producto.marca, style: tema.textTheme.bodySmall),
        const SizedBox(height: 10),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              Formato.moneda(estado.precio),
              style: tema.textTheme.headlineSmall,
            ),
            // Si la variante cuesta distinto del precio base, se muestran los
            // dos: si no, el cambio de número al elegir talla parece un error.
            if (variante?.precio != null &&
                variante!.precio != producto.precioBase) ...[
              const SizedBox(width: 10),
              Text(
                Formato.moneda(producto.precioBase),
                style: tema.textTheme.bodyMedium?.copyWith(
                  decoration: TextDecoration.lineThrough,
                  color: tema.colorScheme.outline,
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 20),

        if (producto.tallas.isNotEmpty) ...[
          Text('Talla', style: tema.textTheme.titleSmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final talla in producto.tallas)
                ChoiceChip(
                  label: Text(talla),
                  selected: estado.talla == talla,
                  onSelected: (_) => control.elegirTalla(talla),
                ),
            ],
          ),
          const SizedBox(height: 18),
        ],

        if (producto.colores.isNotEmpty) ...[
          Text('Color', style: tema.textTheme.titleSmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final color in producto.colores)
                ChoiceChip(
                  avatar: _PuntoColor(hex: _hexDe(producto, color)),
                  label: Text(color),
                  selected: estado.color == color,
                  onSelected: (_) => control.elegirColor(color),
                ),
            ],
          ),
          const SizedBox(height: 18),
        ],

        if (producto.variantesDisponibles.isEmpty)
          BloqueAyuda(
            titulo: 'Sin stock publicado',
            detalle:
                'Esta prenda todavía no tiene tallas ni colores a la venta. '
                'Guardala en favoritos y te avisamos cuando vuelva.',
          )
        else if (sinCombinacion)
          BloqueAyuda(
            titulo: 'Combinación no disponible',
            detalle:
                '${estado.talla} en ${estado.color} no está a la venta. '
                'Probá con otra talla o con otro color.',
          ),

        // Reservar para probarse en sucursal (RF09). La selección se junta en
        // el teléfono y se confirma en `/reservar`, igual que en la web.
        if (variante != null) ...[
          OutlinedButton.icon(
            onPressed: () {
              final problema = ref
                  .read(nuevaReservaProvider.notifier)
                  .agregar(
                    ItemReserva(
                      variantId: variante.id,
                      cantidad: 1,
                      producto: producto.nombre,
                      talla: variante.talla,
                      color: variante.color,
                      imagenUrl: producto.imagenUrl,
                    ),
                  );
              if (problema == null && paraReserva) {
                if (context.canPop()) {
                  context.pop(true);
                } else {
                  context.go('/reservar');
                }
                return;
              }
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    problema ??
                        'La sumamos a tu selección. Agendá el horario cuando quieras.',
                  ),
                  action: problema != null
                      ? null
                      : SnackBarAction(
                          label: 'Agendar',
                          onPressed: () => context.push('/reservar'),
                        ),
                ),
              );
            },
            icon: const Icon(Icons.event_available_outlined),
            label: const Text('Reservar para probarme en sucursal'),
          ),
          const SizedBox(height: 4),
        ],

        if (producto.descripcion.isNotEmpty) ...[
          const Divider(height: 36),
          Text('Descripción', style: tema.textTheme.titleSmall),
          const SizedBox(height: 6),
          Text(producto.descripcion),
        ],

        const Divider(height: 36),
        Text('Detalles', style: tema.textTheme.titleSmall),
        const SizedBox(height: 6),
        for (final dato in _datos(producto, variante))
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 110,
                  child: Text(dato.$1, style: tema.textTheme.bodySmall),
                ),
                Expanded(child: Text(dato.$2)),
              ],
            ),
          ),
      ],
    );
  }

  /// El hex del primer variante que use ese color, para el punto del chip.
  static String? _hexDe(Producto producto, String color) {
    for (final variante in producto.variantesDisponibles) {
      if (variante.color == color) return variante.hexColor;
    }
    return null;
  }

  static List<(String, String)> _datos(
    Producto producto,
    Variante? variante,
  ) => [
    if (producto.genero.isNotEmpty) ('Género', producto.genero),
    if (producto.temporada.isNotEmpty) ('Temporada', producto.temporada),
    if (producto.coleccion.isNotEmpty) ('Colección', producto.coleccion),
    if (variante != null && variante.sku.isNotEmpty) ('Código', variante.sku),
  ];
}

/// Punto redondo con el color real de la variante.
class _PuntoColor extends StatelessWidget {
  const _PuntoColor({this.hex});

  final String? hex;

  @override
  Widget build(BuildContext context) {
    final color = _parsear(hex);
    if (color == null) return const Icon(Icons.circle_outlined, size: 16);
    return Container(
      width: 16,
      height: 16,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Theme.of(context).colorScheme.outline),
      ),
    );
  }

  /// `#1E2A44` → color. Devuelve `null` ante cualquier texto que no sea un hex
  /// de 6 dígitos: el backend lo carga a mano y puede venir vacío o mal.
  static Color? _parsear(String? hex) {
    if (hex == null) return null;
    final limpio = hex.replaceAll('#', '').trim();
    if (limpio.length != 6) return null;
    final valor = int.tryParse(limpio, radix: 16);
    return valor == null ? null : Color(0xFF000000 | valor);
  }
}

/// Barra fija con lo único que la persona vino a hacer: comprar o probarse.
class _Acciones extends StatelessWidget {
  const _Acciones({
    required this.estado,
    required this.slug,
    required this.onAgregar,
  });

  final EstadoPrenda estado;
  final String slug;
  final VoidCallback onAgregar;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final producto = estado.producto;
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
        decoration: BoxDecoration(
          color: tema.colorScheme.surface,
          border: Border(top: BorderSide(color: tema.colorScheme.outline)),
        ),
        child: Row(
          children: [
            if (producto?.tieneVestidor == true) ...[
              OutlinedButton.icon(
                onPressed: () {
                  final color = estado.variante?.colorId;
                  final destino = color == null || color.isEmpty
                      ? '/prendas/$slug/vestidor'
                      : '/prendas/$slug/vestidor?color=${Uri.encodeQueryComponent(color)}';
                  context.push(destino);
                },
                icon: const Icon(Icons.camera_alt_outlined),
                label: const Text('Probarme'),
              ),
              const SizedBox(width: 10),
            ],
            Expanded(
              child: FilledButton(
                onPressed: estado.sePuedeComprar ? onAgregar : null,
                child: estado.ocupado
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Agregar al carrito'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
