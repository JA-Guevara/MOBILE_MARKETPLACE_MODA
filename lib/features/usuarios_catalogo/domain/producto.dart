/// Una combinación concreta de talla y color: lo que realmente se compra.
///
/// El carrito no recibe la prenda sino la variante (`PUT /commerce/cart/items/
/// {variant_id}`), así que sin esto el detalle no puede agregar nada. Es la
/// `Entity` que `product-page.component.ts` recorre para armar los selectores.
class Variante {
  const Variante({
    required this.id,
    required this.talla,
    required this.color,
    this.colorId,
    this.codigoTalla = '',
    this.hexColor,
    this.sku = '',
    this.precio,
    this.activa = true,
  });

  final String id;
  final String talla;
  final String color;
  /// Identificador de color que usa el backend para resolver el recurso del
  /// probador. El nombre sirve para la interfaz, el id evita probar la foto de
  /// otro color de la misma prenda.
  final String? colorId;
  final String codigoTalla;

  /// `#1E2A44`. Se usa para pintar el punto de color del selector.
  final String? hexColor;
  final String sku;

  /// `price_override` de la variante. `null` significa «vale el precio base».
  final num? precio;
  final bool activa;

  /// Lo que se le cobra a la persona por esta variante.
  num precioFinal(num precioBase) => precio ?? precioBase;

  String get etiqueta => [codigoTalla.isEmpty ? talla : codigoTalla, color]
      .where((t) => t.isNotEmpty)
      .join(' · ');

  factory Variante.desdeJson(Map<String, dynamic> json) {
    final talla = json['size'];
    final color = json['color'];
    return Variante(
      id: '${json['id']}',
      talla: talla is Map ? '${talla['name'] ?? ''}' : '',
      codigoTalla: talla is Map ? '${talla['code'] ?? ''}' : '',
      color: color is Map ? '${color['name'] ?? ''}' : '',
      colorId: color is Map && color['id'] != null ? '${color['id']}' : null,
      hexColor: color is Map ? color['hex_code'] as String? : null,
      sku: json['sku'] as String? ?? '',
      // `price_override` llega como texto (`"123.00"`) o como null.
      precio: num.tryParse('${json['price_override']}'),
      activa: json['is_active'] as bool? ?? true,
    );
  }
}

/// Prenda del catálogo, tal como la devuelve `/catalog/products`.
///
/// Es el recorte de `Product` de `shared/models.ts` que necesitan la tarjeta
/// del catálogo y la pantalla de detalle. La misma respuesta sirve para las
/// dos, así que no hay un modelo «de lista» y otro «de detalle» que se puedan
/// desincronizar.
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
    this.descripcion = '',
    this.genero = '',
    this.temporada = '',
    this.coleccion = '',
    this.imagenes = const <String>[],
    this.variantes = const <Variante>[],
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
  final String descripcion;
  final String genero;
  final String temporada;
  final String coleccion;

  /// Todas las fotos, con la principal primero.
  final List<String> imagenes;
  final List<Variante> variantes;

  /// Solo las activas: una variante dada de baja no se puede comprar y el
  /// backend rechazaría el pedido igual.
  List<Variante> get variantesDisponibles =>
      variantes.where((v) => v.activa).toList();

  /// Tallas y colores sin repetir, en el orden en que llegaron.
  List<String> get tallas => _unicos(variantesDisponibles.map((v) => v.talla));
  List<String> get colores => _unicos(variantesDisponibles.map((v) => v.color));

  /// La variante que corresponde a una talla y un color elegidos. `null` si esa
  /// combinación no existe, que es justamente lo que hay que avisarle a quien
  /// la buscó en vez de dejar el botón de comprar prendido.
  Variante? varianteDe(String talla, String color) {
    for (final variante in variantesDisponibles) {
      if (variante.talla == talla && variante.color == color) return variante;
    }
    return null;
  }

  static List<String> _unicos(Iterable<String> valores) {
    final vistos = <String>[];
    for (final valor in valores) {
      if (valor.isNotEmpty && !vistos.contains(valor)) vistos.add(valor);
    }
    return vistos;
  }

  factory Producto.desdeJson(Map<String, dynamic> json) {
    final imagenes = json['images'] as List<dynamic>? ?? const [];
    final ordenadas = _ordenadas(imagenes);
    final categoria = json['category'];
    final temporada = json['season'];
    final coleccion = json['collection'];
    final variantes = json['variants'] as List<dynamic>? ?? const [];
    return Producto(
      id: '${json['id']}',
      nombre: json['name'] as String? ?? '',
      slug: json['slug'] as String? ?? '',
      precioBase: num.tryParse('${json['base_price']}') ?? 0,
      categoria: categoria is Map ? '${categoria['name'] ?? ''}' : '',
      marca: json['brand'] as String? ?? '',
      destacado: json['is_featured'] as bool? ?? false,
      imagenUrl: ordenadas.isEmpty ? null : ordenadas.first,
      // Criterio único del probador: toda prenda con variantes activas se
      // puede probar (mismo que `hasVestidor` de la web).
      tieneVestidor: variantes.any((v) => v is Map && v['is_active'] != false),
      descripcion: json['description'] as String? ?? '',
      genero: json['gender'] as String? ?? '',
      temporada: temporada is Map ? '${temporada['name'] ?? ''}' : '',
      coleccion: coleccion is Map ? '${coleccion['name'] ?? ''}' : '',
      imagenes: ordenadas,
      variantes: variantes
          .whereType<Map<String, dynamic>>()
          .map(Variante.desdeJson)
          .toList(),
    );
  }

  /// Todas las URLs con la marcada `is_primary` adelante. El carrusel del
  /// detalle las muestra en ese orden y la tarjeta del catálogo usa la primera,
  /// así que las dos vistas coinciden en cuál es «la foto» de la prenda.
  static List<String> _ordenadas(List<dynamic> imagenes) {
    final principales = <String>[];
    final resto = <String>[];
    for (final imagen in imagenes) {
      if (imagen is! Map) continue;
      final url = imagen['url'] as String?;
      if (url == null || url.isEmpty) continue;
      (imagen['is_primary'] == true ? principales : resto).add(url);
    }
    return [...principales, ...resto];
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
