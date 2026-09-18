/// Prenda del catálogo, tal como la devuelve `/catalog/products`.
///
/// Es el recorte de `Product` de `shared/models.ts` que necesita la tarjeta del
/// catálogo: nombre, precio, categoría, imagen principal y si tiene probador.
class Producto {
  const Producto({
    required this.id,
    required this.nombre,
    required this.slug,
    required this.precioBase,
    required this.categoria,
    this.marca = '',
    this.destacado = false,
    this.imagenUrl,
    this.tieneVestidor = false,
  });

  final String id;
  final String nombre;
  final String slug;
  final num precioBase;
  final String categoria;
  final String marca;
  final bool destacado;
  final String? imagenUrl;
  final bool tieneVestidor;

  factory Producto.desdeJson(Map<String, dynamic> json) {
    final imagenes = json['images'] as List<dynamic>? ?? const [];
    final principal = _principal(imagenes);
    final categoria = json['category'];
    final variantes = json['variants'] as List<dynamic>? ?? const [];
    return Producto(
      id: '${json['id']}',
      nombre: json['name'] as String? ?? '',
      slug: json['slug'] as String? ?? '',
      precioBase: num.tryParse('${json['base_price']}') ?? 0,
      categoria: categoria is Map ? '${categoria['name'] ?? ''}' : '',
      marca: json['brand'] as String? ?? '',
      destacado: json['is_featured'] as bool? ?? false,
      imagenUrl: principal,
      // Criterio único del probador: toda prenda con variantes activas se
      // puede probar (mismo que `hasVestidor` de la web).
      tieneVestidor:
          variantes.any((v) => v is Map && v['is_active'] != false),
    );
  }

  static String? _principal(List<dynamic> imagenes) {
    for (final imagen in imagenes) {
      if (imagen is Map && imagen['is_primary'] == true) {
        final url = imagen['url'] as String?;
        if (url != null && url.isNotEmpty) return url;
      }
    }
    for (final imagen in imagenes) {
      if (imagen is Map) {
        final url = imagen['url'] as String?;
        if (url != null && url.isNotEmpty) return url;
      }
    }
    return null;
  }
}

/// Opciones de los filtros (`/catalog/categories`, `/catalog/sizes`, …).
class Referencia {
  const Referencia({required this.id, required this.nombre});

  final String id;
  final String nombre;

  factory Referencia.desdeJson(Map<String, dynamic> json) =>
      Referencia(id: '${json['id']}', nombre: json['name'] as String? ?? '');
}

/// Prenda sugerida por la IA (`/commerce/recommendations`).
class Recomendado {
  const Recomendado({
    required this.id,
    required this.nombre,
    required this.slug,
    required this.precioBase,
    this.categoria = '',
    this.imagenUrl,
  });

  final String id;
  final String nombre;
  final String slug;
  final num precioBase;
  final String categoria;
  final String? imagenUrl;

  factory Recomendado.desdeJson(Map<String, dynamic> json) => Recomendado(
        id: '${json['id']}',
        nombre: json['name'] as String? ?? '',
        slug: json['slug'] as String? ?? '',
        precioBase: num.tryParse('${json['base_price']}') ?? 0,
        categoria: json['category'] as String? ?? '',
        imagenUrl: json['image_url'] as String?,
      );
}