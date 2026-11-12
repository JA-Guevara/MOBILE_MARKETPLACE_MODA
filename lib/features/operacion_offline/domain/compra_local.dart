class ItemCompraLocal {
  const ItemCompraLocal({
    required this.varianteId,
    required this.productoNombre,
    required this.varianteDesc,
    required this.cantidad,
    required this.precioUnitario,
    this.stockDisponible = 0,
  });

  final String varianteId, productoNombre, varianteDesc;
  final int cantidad, stockDisponible;
  final double precioUnitario;
  double get total => (precioUnitario * 100).round() * cantidad / 100;

  ItemCompraLocal copyWith({int? cantidad}) => ItemCompraLocal(
    varianteId: varianteId,
    productoNombre: productoNombre,
    varianteDesc: varianteDesc,
    cantidad: cantidad ?? this.cantidad,
    precioUnitario: precioUnitario,
    stockDisponible: stockDisponible,
  );
}

class CompraLocal {
  const CompraLocal({
    required this.id,
    required this.tenantId,
    required this.sucursalId,
    required this.usuarioId,
    required this.contactoNombre,
    required this.contactoTelefono,
    required this.formaPago,
    required this.subtotal,
    required this.total,
    required this.estado,
    required this.catalogoDescargadoEn,
    required this.creadaEn,
    this.notas,
    this.pedidoId,
    this.pedidoNumero,
    this.pagoVenceEn,
  });

  final String id, tenantId, sucursalId, usuarioId;
  final String contactoNombre, contactoTelefono, formaPago, estado;
  final String catalogoDescargadoEn, creadaEn;
  final String? notas, pedidoId, pedidoNumero, pagoVenceEn;
  final double subtotal, total;

  String get folio => 'CMP-${id.replaceAll('-', '').substring(0, 8).toUpperCase()}';

  factory CompraLocal.desdeFila(Map<String, Object?> f) => CompraLocal(
    id: f['id'] as String,
    tenantId: f['tenant_id'] as String,
    sucursalId: f['sucursal_id'] as String,
    usuarioId: f['usuario_id'] as String,
    contactoNombre: f['contacto_nombre'] as String,
    contactoTelefono: f['contacto_telefono'] as String,
    formaPago: f['forma_pago'] as String,
    notas: f['notas'] as String?,
    subtotal: (f['subtotal'] as num).toDouble(),
    total: (f['total'] as num).toDouble(),
    estado: f['estado'] as String,
    catalogoDescargadoEn: f['catalogo_descargado_en'] as String,
    creadaEn: f['creada_en'] as String,
    pedidoId: f['pedido_id'] as String?,
    pedidoNumero: f['pedido_numero'] as String?,
    pagoVenceEn: f['pago_vence_en'] as String?,
  );
}

Map<String, dynamic> payloadCompra({
  required List<ItemCompraLocal> items,
  required String contactoNombre,
  required String contactoTelefono,
  required String formaPago,
  String? notas,
  required String deviceId,
}) => {
  'items': [
    for (final item in items)
      {
        'variant_id': item.varianteId,
        'quantity': item.cantidad,
        'unit_price': item.precioUnitario.toStringAsFixed(2),
      },
  ],
  'customer_name': contactoNombre.trim(),
  'customer_phone': contactoTelefono.trim(),
  'payment_method': formaPago == 'TARJETA_AL_RECONECTAR' ? 'stripe' : 'manual',
  'notes': notas?.trim().isEmpty == true ? null : notas?.trim(),
  'channel': 'mobile',
  'device_id': deviceId,
};

String? validarItemsCompra(List<ItemCompraLocal> items) {
  if (items.isEmpty) return 'Agregá al menos una prenda.';
  if (items.length > 100) return 'La compra supera el límite de prendas.';
  if (items.any((item) => item.cantidad < 1 || item.cantidad > 10)) {
    return 'Elegí una cantidad entre 1 y 10 por prenda.';
  }
  if (items.any((item) => item.cantidad > item.stockDisponible)) {
    return 'La cantidad supera la existencia local conocida.';
  }
  return null;
}

