import '../../usuarios_catalogo/domain/usuario.dart';

double numero(Object? valor) => valor == null ? 0 : double.parse('$valor');
bool bandera(Object? valor) => valor == true || valor == 1;

class ProductoLocal {
  const ProductoLocal({
    required this.id,
    required this.nombre,
    required this.slug,
    required this.precioBase,
    this.categoria = '',
    this.marca = '',
    this.precioOferta,
    this.imagenUrl,
    this.destacado = false,
    this.actualizadoEn,
  });
  final String id, nombre, slug, categoria, marca;
  final double precioBase;
  final double? precioOferta;
  final String? imagenUrl, actualizadoEn;
  final bool destacado;
  double get precio => precioOferta ?? precioBase;
  factory ProductoLocal.desdeJson(Map<String, dynamic> j) => ProductoLocal(
    id: '${j['id']}',
    nombre: j['name'] as String,
    slug: j['slug'] as String,
    categoria: '${j['category'] ?? ''}',
    marca: '${j['brand'] ?? ''}',
    precioBase: numero(j['base_price']),
    precioOferta: j['offer_price'] == null ? null : numero(j['offer_price']),
    imagenUrl: j['image_url'] as String?,
    destacado: bandera(j['is_featured']),
    actualizadoEn: j['updated_at'] as String?,
  );
  factory ProductoLocal.desdeFila(Map<String, Object?> f) => ProductoLocal(
    id: f['id'] as String,
    nombre: f['nombre'] as String,
    slug: f['slug'] as String,
    categoria: f['categoria'] as String? ?? '',
    marca: f['marca'] as String? ?? '',
    precioBase: numero(f['precio_base']),
    precioOferta: f['precio_oferta'] == null
        ? null
        : numero(f['precio_oferta']),
    imagenUrl: f['imagen_url'] as String?,
    destacado: bandera(f['destacado']),
    actualizadoEn: f['actualizado_en'] as String?,
  );
  Map<String, Object?> aFila() => {
    'id': id,
    'nombre': nombre,
    'slug': slug,
    'categoria': categoria,
    'marca': marca,
    'precio_base': precioBase,
    'precio_oferta': precioOferta,
    'imagen_url': imagenUrl,
    'destacado': destacado ? 1 : 0,
    'actualizado_en': actualizadoEn,
  };
}

class VarianteLocal {
  const VarianteLocal({
    required this.id,
    required this.productoId,
    required this.sku,
    required this.talla,
    required this.color,
    this.colorHex,
    this.precio,
    this.activa = true,
  });
  final String id, productoId, sku, talla, color;
  final String? colorHex;
  final double? precio;
  final bool activa;
  factory VarianteLocal.desdeJson(Map<String, dynamic> j) => VarianteLocal(
    id: '${j['id']}',
    productoId: '${j['product_id']}',
    sku: j['sku'] as String,
    talla: '${j['size']}',
    color: '${j['color']}',
    colorHex: j['color_hex'] as String?,
    precio: j['price'] == null ? null : numero(j['price']),
    activa: bandera(j['is_active']),
  );
  factory VarianteLocal.desdeFila(Map<String, Object?> f) => VarianteLocal(
    id: f['id'] as String,
    productoId: f['producto_id'] as String,
    sku: f['sku'] as String,
    talla: f['talla'] as String,
    color: f['color'] as String,
    colorHex: f['color_hex'] as String?,
    precio: f['precio'] == null ? null : numero(f['precio']),
    activa: bandera(f['activa']),
  );
  Map<String, Object?> aFila() => {
    'id': id,
    'producto_id': productoId,
    'sku': sku,
    'talla': talla,
    'color': color,
    'color_hex': colorHex,
    'precio': precio,
    'activa': activa ? 1 : 0,
  };
}

class ExistenciaLocal {
  const ExistenciaLocal({
    required this.varianteId,
    required this.sucursalId,
    required this.cantidad,
  });
  final String varianteId, sucursalId;
  final int cantidad;
  factory ExistenciaLocal.desdeJson(Map<String, dynamic> j) => ExistenciaLocal(
    varianteId: '${j['variant_id']}',
    sucursalId: '${j['branch_id']}',
    cantidad: (j['quantity'] as num).toInt(),
  );
  factory ExistenciaLocal.desdeFila(Map<String, Object?> f) => ExistenciaLocal(
    varianteId: f['variante_id'] as String,
    sucursalId: f['sucursal_id'] as String,
    cantidad: (f['cantidad'] as num).toInt(),
  );
  Map<String, Object?> aFila() => {
    'variante_id': varianteId,
    'sucursal_id': sucursalId,
    'cantidad': cantidad,
  };
}

class SucursalLocal {
  const SucursalLocal({
    required this.id,
    required this.codigo,
    required this.nombre,
    this.direccion,
  });
  final String id, codigo, nombre;
  final String? direccion;
  factory SucursalLocal.desdeJson(Map<String, dynamic> j) => SucursalLocal(
    id: '${j['id']}',
    codigo: j['code'] as String,
    nombre: j['name'] as String,
    direccion: j['address'] as String?,
  );
  factory SucursalLocal.desdeFila(Map<String, Object?> f) => SucursalLocal(
    id: f['id'] as String,
    codigo: f['codigo'] as String,
    nombre: f['nombre'] as String,
    direccion: f['direccion'] as String?,
  );
  Map<String, Object?> aFila() => {
    'id': id,
    'codigo': codigo,
    'nombre': nombre,
    'direccion': direccion,
  };
}

class ClienteLocal {
  const ClienteLocal({
    required this.id,
    required this.nombre,
    this.documentoFinal,
    this.telefono,
  });
  final String id, nombre;
  final String? documentoFinal, telefono;
  factory ClienteLocal.desdeJson(Map<String, dynamic> j) => ClienteLocal(
    id: '${j['id']}',
    nombre: j['name'] as String,
    documentoFinal: j['document_tail'] as String?,
    telefono: j['phone'] as String?,
  );
  factory ClienteLocal.desdeFila(Map<String, Object?> f) => ClienteLocal(
    id: f['id'] as String,
    nombre: f['nombre'] as String,
    documentoFinal: f['documento_final'] as String?,
    telefono: f['telefono'] as String?,
  );
  Map<String, Object?> aFila() => {
    'id': id,
    'nombre': nombre,
    'documento_final': documentoFinal,
    'telefono': telefono,
  };
}

class InstantaneaCatalogo {
  const InstantaneaCatalogo({
    required this.version,
    required this.generadaEn,
    required this.completa,
    required this.empresa,
    this.productos = const [],
    this.variantes = const [],
    this.existencias = const [],
    this.sucursales = const [],
    this.clientes = const [],
    this.productosEliminados = const [],
    this.variantesEliminadas = const [],
  });
  final String version;
  final DateTime generadaEn;
  final bool completa;
  final EmpresaResumen empresa;
  final List<ProductoLocal> productos;
  final List<VarianteLocal> variantes;
  final List<ExistenciaLocal> existencias;
  final List<SucursalLocal> sucursales;
  final List<ClienteLocal> clientes;
  final List<String> productosEliminados, variantesEliminadas;
  factory InstantaneaCatalogo.desdeJson(Map<String, dynamic> j) {
    List<T> lista<T>(String k, T Function(Map<String, dynamic>) parse) =>
        (j[k] as List<dynamic>? ?? [])
            .map((e) => parse(e as Map<String, dynamic>))
            .toList();
    final removed = j['removed'] as Map<String, dynamic>? ?? {};
    return InstantaneaCatalogo(
      version: j['version'] as String,
      generadaEn: DateTime.parse(j['generated_at'] as String),
      completa: j['full'] as bool,
      empresa: EmpresaResumen.desdeJson(j['tenant'] as Map<String, dynamic>),
      productos: lista('products', ProductoLocal.desdeJson),
      variantes: lista('variants', VarianteLocal.desdeJson),
      existencias: lista('stock', ExistenciaLocal.desdeJson),
      sucursales: lista('branches', SucursalLocal.desdeJson),
      clientes: lista('customers', ClienteLocal.desdeJson),
      productosEliminados: (removed['products'] as List<dynamic>? ?? [])
          .map((e) => '$e')
          .toList(),
      variantesEliminadas: (removed['variants'] as List<dynamic>? ?? [])
          .map((e) => '$e')
          .toList(),
    );
  }
}

class MetaOffline {
  const MetaOffline({
    this.version,
    this.descargadoEn,
    this.sucursalId,
    this.tenantId,
    this.usuarioId,
  });
  final String? version, sucursalId, tenantId, usuarioId;
  final DateTime? descargadoEn;
  bool get disponible => version != null;
}

class DatosLocales {
  const DatosLocales({
    this.productos = const [],
    this.variantes = const [],
    this.existencias = const [],
    this.sucursales = const [],
    this.clientes = const [],
  });
  final List<ProductoLocal> productos;
  final List<VarianteLocal> variantes;
  final List<ExistenciaLocal> existencias;
  final List<SucursalLocal> sucursales;
  final List<ClienteLocal> clientes;
  int stock(String varianteId) => existencias
      .where((e) => e.varianteId == varianteId)
      .fold(0, (n, e) => n + e.cantidad);
}

class FiltrosOffline {
  const FiltrosOffline({
    this.texto = '',
    this.categoria = '',
    this.talla = '',
    this.color = '',
    this.precioMin,
    this.precioMax,
    this.soloOferta = false,
    this.soloConStock = false,
  });
  final String texto, categoria, talla, color;
  final double? precioMin, precioMax;
  final bool soloOferta, soloConStock;
  FiltrosOffline copyWith({
    String? texto,
    String? categoria,
    String? talla,
    String? color,
    double? precioMin,
    double? precioMax,
    bool? soloOferta,
    bool? soloConStock,
  }) => FiltrosOffline(
    texto: texto ?? this.texto,
    categoria: categoria ?? this.categoria,
    talla: talla ?? this.talla,
    color: color ?? this.color,
    precioMin: precioMin ?? this.precioMin,
    precioMax: precioMax ?? this.precioMax,
    soloOferta: soloOferta ?? this.soloOferta,
    soloConStock: soloConStock ?? this.soloConStock,
  );
}

class ProductoVista {
  const ProductoVista(this.producto, this.variantes, this.stock);
  final ProductoLocal producto;
  final List<VarianteLocal> variantes;
  final int stock;
}

const vigenciaHoras = 24;
bool estaDesactualizado(
  DateTime? descargadoEn,
  DateTime ahora, {
  int horas = vigenciaHoras,
}) =>
    descargadoEn == null ||
    ahora.difference(descargadoEn) >= Duration(hours: horas);
List<ProductoVista> filtrar(DatosLocales datos, FiltrosOffline f) {
  final resultado = <ProductoVista>[];
  for (final p in datos.productos) {
    if (f.texto.isNotEmpty &&
        !'${p.nombre} ${p.marca}'.toLowerCase().contains(
          f.texto.toLowerCase(),
        )) {
      continue;
    }
    if (f.categoria.isNotEmpty && p.categoria != f.categoria ||
        f.soloOferta && p.precioOferta == null) {
      continue;
    }
    final variantes = datos.variantes
        .where(
          (v) =>
              v.productoId == p.id &&
              v.activa &&
              (f.talla.isEmpty || v.talla == f.talla) &&
              (f.color.isEmpty || v.color == f.color) &&
              (f.precioMin == null || (v.precio ?? p.precio) >= f.precioMin!) &&
              (f.precioMax == null || (v.precio ?? p.precio) <= f.precioMax!),
        )
        .toList();
    if (variantes.isEmpty) continue;
    final stock = variantes.fold<int>(0, (n, v) => n + datos.stock(v.id));
    if (f.soloConStock && stock == 0) continue;
    resultado.add(ProductoVista(p, variantes, stock));
  }
  return resultado;
}
