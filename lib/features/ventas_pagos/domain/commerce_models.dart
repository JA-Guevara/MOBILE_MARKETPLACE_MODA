/// Modelos de ventas y pagos — réplica de `commerce.models.ts` de la web.
/// Los nombres de campo coinciden uno a uno con el contrato del backend.
library;

double _monto(dynamic valor) => valor is num
    ? valor.toDouble()
    : (double.tryParse('$valor') ?? 0);

Map<String, int> _unidades(dynamic valor) {
  if (valor is! Map) return const {};
  return valor.map(
    (clave, cantidad) => MapEntry('$clave', (cantidad as num?)?.toInt() ?? 0),
  );
}

/// Sucursal disponible para una compra o una operación de caja.
class Sucursal {
  const Sucursal({required this.id, required this.nombre, required this.direccion});

  final String id;
  final String nombre;
  final String direccion;

  factory Sucursal.desdeJson(Map<String, dynamic> json) => Sucursal(
        id: json['id'] as String? ?? '',
        nombre: json['name'] as String? ?? '',
        direccion: json['address'] as String? ?? '',
      );
}

/// Caja habilitada dentro de una sucursal.
class PuntoCaja {
  const PuntoCaja({
    required this.id,
    required this.codigo,
    required this.nombre,
    required this.sucursalId,
  });

  final String id;
  final String codigo;
  final String nombre;
  final String sucursalId;

  factory PuntoCaja.desdeJson(Map<String, dynamic> json) => PuntoCaja(
        id: json['id'] as String? ?? '',
        codigo: json['code'] as String? ?? '',
        nombre: json['name'] as String? ?? '',
        sucursalId: json['branch_id'] as String? ?? '',
      );
}

/// Ítem del carrito (web `CartItem`).
class ItemCarrito {
  const ItemCarrito({
    required this.variantId,
    required this.productId,
    required this.name,
    required this.sku,
    required this.size,
    required this.color,
    required this.unitPrice,
    required this.quantity,
    required this.available,
    required this.lineTotal,
    this.imageUrl,
  });

  final String variantId;
  final String productId;
  final String name;
  final String sku;
  final String size;
  final String color;
  final String? imageUrl;
  final double unitPrice;
  final int quantity;
  final int available;
  final double lineTotal;

  factory ItemCarrito.desdeJson(Map<String, dynamic> json) => ItemCarrito(
        variantId: json['variant_id'] as String? ?? '',
        productId: json['product_id'] as String? ?? '',
        name: json['name'] as String? ?? '',
        sku: json['sku'] as String? ?? '',
        size: json['size'] as String? ?? '',
        color: json['color'] as String? ?? '',
        imageUrl: json['image_url'] as String?,
        unitPrice: _monto(json['unit_price']),
        quantity: (json['quantity'] as num?)?.toInt() ?? 0,
        available: (json['available'] as num?)?.toInt() ?? 0,
        lineTotal: _monto(json['line_total']),
      );
}

/// Descuento de promoción aplicado al carrito (web `CartDiscount`).
class DescuentoCarrito {
  const DescuentoCarrito({
    required this.promotionId,
    required this.name,
    required this.code,
    required this.type,
    required this.amount,
    this.message,
  });

  final String promotionId;
  final String name;
  final String? code;
  final String type;
  final double amount;
  final String? message;

  factory DescuentoCarrito.desdeJson(Map<String, dynamic> json) => DescuentoCarrito(
        promotionId: json['promotion_id'] as String? ?? '',
        name: json['name'] as String? ?? '',
        code: json['code'] as String?,
        type: json['type'] as String? ?? '',
        amount: _monto(json['amount']),
        message: json['message'] as String?,
      );
}

/// Carrito completo (web `Cart`).
class Carrito {
  const Carrito({
    required this.items,
    this.subtotal = 0,
    this.discountTotal = 0,
    this.discounts = const [],
    this.couponCode,
    this.total = 0,
    this.currency = 'BOB',
  });

  final List<ItemCarrito> items;
  final double subtotal;
  final double discountTotal;
  final List<DescuentoCarrito> discounts;
  final String? couponCode;
  final double total;
  final String currency;

  factory Carrito.desdeJson(Map<String, dynamic> json) => Carrito(
        items: (json['items'] as List<dynamic>? ?? const [])
            .map((e) => ItemCarrito.desdeJson(e as Map<String, dynamic>))
            .toList(),
        subtotal: _monto(json['subtotal']),
        discountTotal: _monto(json['discount_total']),
        discounts: (json['discounts'] as List<dynamic>? ?? const [])
            .map((e) => DescuentoCarrito.desdeJson(e as Map<String, dynamic>))
            .toList(),
        couponCode: json['coupon_code'] as String?,
        total: _monto(json['total']),
        currency: json['currency'] as String? ?? 'BOB',
      );

  bool get vacio => items.isEmpty;
}

/// Dirección de entrega dentro de un pedido (web `DeliveryAddress`).
class DireccionEntrega {
  const DireccionEntrega({
    this.recipient,
    this.phone,
    this.line1,
    this.city,
    this.country,
    this.postalCode,
  });

  final String? recipient;
  final String? phone;
  final String? line1;
  final String? city;
  final String? country;
  final String? postalCode;

  factory DireccionEntrega.desdeJson(Map<String, dynamic> json) => DireccionEntrega(
        recipient: json['recipient'] as String?,
        phone: json['phone'] as String?,
        line1: json['line1'] as String?,
        city: json['city'] as String?,
        country: json['country'] as String?,
        postalCode: json['postal_code'] as String?,
      );

  Map<String, dynamic> aJson() => {
        'recipient': recipient,
        'phone': phone,
        'line1': line1,
        'city': city,
        'country': country,
        'postal_code': postalCode,
      };
}

/// Ítem de un pedido (web `OrderItem`).
class ItemPedido {
  const ItemPedido({
    required this.variantId,
    required this.productId,
    required this.name,
    required this.sku,
    required this.size,
    required this.color,
    required this.unitPrice,
    required this.quantity,
    required this.available,
    required this.lineTotal,
    this.imageUrl,
  });

  final String variantId;
  final String productId;
  final String name;
  final String sku;
  final String size;
  final String color;
  final String? imageUrl;
  final double unitPrice;
  final int quantity;
  final int available;
  final double lineTotal;

  factory ItemPedido.desdeJson(Map<String, dynamic> json) => ItemPedido(
        variantId: json['variant_id'] as String? ?? '',
        productId: json['product_id'] as String? ?? '',
        name: json['name'] as String? ?? '',
        sku: json['sku'] as String? ?? '',
        size: json['size'] as String? ?? '',
        color: json['color'] as String? ?? '',
        imageUrl: json['image_url'] as String?,
        unitPrice: _monto(json['unit_price']),
        quantity: (json['quantity'] as num?)?.toInt() ?? 0,
        available: (json['available'] as num?)?.toInt() ?? 0,
        lineTotal: _monto(json['line_total']),
      );
}

/// Dto de un pedido completo (web `Order`).
class Pedido {
  const Pedido({
    required this.id,
    required this.number,
    required this.customerEmail,
    required this.branchId,
    required this.status,
    required this.paymentStatus,
    required this.paymentMethod,
    required this.total,
    required this.currency,
    required this.address,
    required this.items,
    required this.tracking,
    required this.createdAt,
    this.salesChannel,
    this.paymentReference,
    this.subtotal,
    this.discountTotal,
    this.discounts = const [],
    this.carrier,
    this.trackingNumber,
    this.hasOpenReturn = false,
  });

  final String id;
  final String number;
  final String customerEmail;
  final String branchId;
  final String status;
  final String paymentStatus;
  final String paymentMethod;
  final double total;
  final String currency;
  final DireccionEntrega address;
  final List<ItemPedido> items;
  final List<IngresoTracking> tracking;
  final String createdAt;
  final String? salesChannel;
  final String? paymentReference;
  final double? subtotal;
  final double? discountTotal;
  final List<DescuentoCarrito> discounts;
  final String? carrier;
  final String? trackingNumber;
  final bool hasOpenReturn;

  factory Pedido.desdeJson(Map<String, dynamic> json) => Pedido(
        id: json['id'] as String? ?? '',
        number: json['number'] as String? ?? '',
        customerEmail: json['customer_email'] as String? ?? '',
        branchId: json['branch_id'] as String? ?? '',
        status: json['status'] as String? ?? '',
        paymentStatus: json['payment_status'] as String? ?? '',
        paymentMethod: json['payment_method'] as String? ?? '',
        total: _monto(json['total']),
        currency: json['currency'] as String? ?? 'BOB',
        address: DireccionEntrega.desdeJson(
            json['address'] is Map<String, dynamic> ? json['address'] as Map<String, dynamic> : const {}),
        items: (json['items'] as List<dynamic>? ?? const [])
            .map((e) => ItemPedido.desdeJson(e as Map<String, dynamic>))
            .toList(),
        tracking: (json['tracking'] as List<dynamic>? ?? const [])
            .map((e) => IngresoTracking.desdeJson(e as Map<String, dynamic>))
            .toList(),
        createdAt: json['created_at'] as String? ?? '',
        salesChannel: json['sales_channel'] as String?,
        paymentReference: json['payment_reference'] as String?,
        subtotal: json['subtotal'] != null ? _monto(json['subtotal']) : null,
        discountTotal: json['discount_total'] != null ? _monto(json['discount_total']) : null,
        discounts: (json['discounts'] as List<dynamic>? ?? const [])
            .map((e) => DescuentoCarrito.desdeJson(e as Map<String, dynamic>))
            .toList(),
        carrier: json['carrier'] as String?,
        trackingNumber: json['tracking_number'] as String?,
        hasOpenReturn: json['has_open_return'] as bool? ?? false,
      );

  String get etiquetaEstado => etiquetaPedido(status);
  String get etiquetaPago => etiquetaPagoStatus(paymentStatus);
  String get etiquetaMetodo => etiquetaMetodoPago(paymentMethod);
}

/// Devolución de un pedido (web `OrderReturn`).
class Devolucion {
  const Devolucion({
    required this.id,
    required this.orderId,
    required this.branchId,
    required this.status,
    required this.reason,
    required this.items,
    required this.refundAmount,
    required this.currency,
    required this.createdAt,
    this.resolutionNote,
    this.resolvedAt,
    this.orderNumber,
    this.customerEmail,
    this.customerName,
    this.branchName,
    this.salesChannel,
  });

  final String id;
  final String orderId;
  final String branchId;
  final String status;
  final String reason;
  final List<ItemPedido> items;
  final double refundAmount;
  final String currency;
  final String? resolutionNote;
  final String? resolvedAt;
  final String createdAt;
  final String? orderNumber;
  final String? customerEmail;
  final String? customerName;
  final String? branchName;
  final String? salesChannel;

  factory Devolucion.desdeJson(Map<String, dynamic> json) => Devolucion(
        id: json['id'] as String? ?? '',
        orderId: json['order_id'] as String? ?? '',
        branchId: json['branch_id'] as String? ?? '',
        status: json['status'] as String? ?? '',
        reason: json['reason'] as String? ?? '',
        items: (json['items'] as List<dynamic>? ?? const [])
            .map((e) => ItemPedido.desdeJson(e as Map<String, dynamic>))
            .toList(),
        refundAmount: _monto(json['refund_amount']),
        currency: json['currency'] as String? ?? 'BOB',
        resolutionNote: json['resolution_note'] as String?,
        resolvedAt: json['resolved_at'] as String?,
        createdAt: json['created_at'] as String? ?? '',
        orderNumber: json['order_number'] as String?,
        customerEmail: json['customer_email'] as String?,
        customerName: json['customer_name'] as String?,
        branchName: json['branch_name'] as String?,
        salesChannel: json['sales_channel'] as String?,
      );
}

/// Promoción (web `Promotion`).
class Promocion {
  const Promocion({
    required this.id,
    required this.name,
    required this.description,
    required this.discountType,
    required this.discountValue,
    required this.minimumOrder,
    required this.isActive,
    this.code,
    this.categoryId,
    this.productId,
    this.customerScope = 'all',
    this.minimumPaidOrders = 0,
    this.startsAt,
    this.endsAt,
    this.maxUses,
    this.usesCount = 0,
    this.perUserLimit,
  });

  final String id;
  final String name;
  final String description;
  final String discountType;
  final double discountValue;
  final double minimumOrder;
  final bool isActive;
  final String? code;
  final String? categoryId;
  final String? productId;
  final String customerScope;
  final int minimumPaidOrders;
  final String? startsAt;
  final String? endsAt;
  final int? maxUses;
  final int usesCount;
  final int? perUserLimit;

  factory Promocion.desdeJson(Map<String, dynamic> json) => Promocion(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? '',
        description: json['description'] as String? ?? '',
        discountType: json['discount_type'] as String? ?? '',
        discountValue: _monto(json['discount_value']),
        minimumOrder: _monto(json['minimum_order']),
        isActive: json['is_active'] as bool? ?? false,
        code: json['code'] as String?,
        categoryId: json['category_id'] as String?,
        productId: json['product_id'] as String?,
        customerScope: json['customer_scope'] as String? ?? 'all',
        minimumPaidOrders: (json['minimum_paid_orders'] as num?)?.toInt() ?? 0,
        startsAt: json['starts_at'] as String?,
        endsAt: json['ends_at'] as String?,
        maxUses: json['max_uses'] != null ? (json['max_uses'] as num).toInt() : null,
        usesCount: (json['uses_count'] as num?)?.toInt() ?? 0,
        perUserLimit: json['per_user_limit'] != null ? (json['per_user_limit'] as num).toInt() : null,
      );

  String get etiquetaTipo => switch (discountType) {
        'percent' => 'Porcentaje',
        'fixed' => 'Monto fijo',
        'free_shipping' => 'Envío gratis',
        _ => discountType,
      };
}

/// Favorito (web `Favorite`).
class Favorito {
  const Favorito({
    required this.id,
    required this.productId,
    required this.slug,
    required this.name,
    required this.basePrice,
    required this.stockAlert,
    required this.priceAlert,
    this.imageUrl,
  });

  final String id;
  final String productId;
  final String slug;
  final String name;
  final double basePrice;
  final bool stockAlert;
  final bool priceAlert;
  final String? imageUrl;

  factory Favorito.desdeJson(Map<String, dynamic> json) => Favorito(
        id: json['id'] as String? ?? '',
        productId: json['product_id'] as String? ?? '',
        slug: json['slug'] as String? ?? '',
        name: json['name'] as String? ?? '',
        basePrice: _monto(json['base_price']),
        stockAlert: json['stock_alert'] as bool? ?? false,
        priceAlert: json['price_alert'] as bool? ?? false,
        imageUrl: json['image_url'] as String?,
      );
}

/// Estado de favorito (web `FavoriteState`).
class EstadoFavorito {
  const EstadoFavorito({
    required this.isFavorite,
    required this.stockAlert,
    required this.priceAlert,
  });

  final bool isFavorite;
  final bool stockAlert;
  final bool priceAlert;

  factory EstadoFavorito.desdeJson(Map<String, dynamic> json) => EstadoFavorito(
        isFavorite: json['is_favorite'] as bool? ?? false,
        stockAlert: json['stock_alert'] as bool? ?? false,
        priceAlert: json['price_alert'] as bool? ?? false,
      );
}

/// Ítem de tracking de un pedido (web `OrderTrackingItem`).
class IngresoTracking {
  const IngresoTracking({
    required this.status,
    required this.note,
    required this.date,
  });

  final String status;
  final String note;
  final String date;

  factory IngresoTracking.desdeJson(Map<String, dynamic> json) => IngresoTracking(
        status: json['status'] as String? ?? '',
        note: json['note'] as String? ?? '',
        date: json['date'] as String? ?? '',
      );

  String get etiqueta => etiquetaPedido(status);
}

/// Estado de una devolución que el cliente puede solicitar para un pedido.
class DisponibilidadDevolucion {
  const DisponibilidadDevolucion({
    required this.puedeSolicitar,
    required this.unidades,
    required this.devoluciones,
    this.motivo,
  });

  final bool puedeSolicitar;
  final String? motivo;
  final Map<String, int> unidades;
  final List<Devolucion> devoluciones;

  factory DisponibilidadDevolucion.desdeJson(Map<String, dynamic> json) =>
      DisponibilidadDevolucion(
        puedeSolicitar: json['can_request'] as bool? ?? false,
        motivo: json['reason'] as String?,
        unidades: _unidades(json['units']),
        devoluciones: (json['returns'] as List<dynamic>? ?? const [])
            .map((fila) => Devolucion.desdeJson(fila as Map<String, dynamic>))
            .toList(),
      );
}

/// Resultado de buscar un pedido en el mostrador para atender una devolución.
class BusquedaMostrador {
  const BusquedaMostrador({
    required this.pedido,
    required this.puedeSolicitar,
    required this.unidades,
    required this.devoluciones,
    this.motivo,
  });

  final Pedido pedido;
  final bool puedeSolicitar;
  final String? motivo;
  final Map<String, int> unidades;
  final List<Devolucion> devoluciones;

  factory BusquedaMostrador.desdeJson(Map<String, dynamic> json) =>
      BusquedaMostrador(
        pedido: Pedido.desdeJson(json['order'] as Map<String, dynamic>? ?? const {}),
        puedeSolicitar: json['can_request'] as bool? ?? false,
        motivo: json['reason'] as String?,
        unidades: _unidades(json['units']),
        devoluciones: (json['returns'] as List<dynamic>? ?? const [])
            .map((fila) => Devolucion.desdeJson(fila as Map<String, dynamic>))
            .toList(),
      );
}

// --- Etiquetas (mismas palabras que la web) ---

const Map<String, String> _pedidos = {
  'pending_payment': 'Pendiente de pago',
  'paid': 'Pagado',
  'processing': 'En preparación',
  'shipped': 'En camino',
  'delivered': 'Entregado',
  'cancelled': 'Cancelado',
  'expired': 'Vencido',
};

const Map<String, String> _pagos = {
  'pending': 'Pendiente',
  'paid': 'Pagado',
  'failed': 'Fallado',
  'refunded': 'Reintegrado',
};

const Map<String, String> _metodos = {
  'stripe': 'Tarjeta · Stripe',
  'manual': 'Pago coordinado',
  'cash': 'Efectivo',
  'qr': 'Pago con QR',
  'card': 'Tarjeta en el local',
  'transfer': 'Transferencia',
};

const Map<String, String> _devoluciones = {
  'requested': 'Devolución solicitada',
  'approved': 'Devolución aprobada',
  'rejected': 'Devolución rechazada',
  'completed': 'Devolución cerrada',
};

String etiquetaPedido(String valor) => _pedidos[valor] ?? valor;
String etiquetaPagoStatus(String valor) => _pagos[valor] ?? valor;
String etiquetaMetodoPago(String valor) => _metodos[valor] ?? valor;
String etiquetaDevolucion(String valor) => _devoluciones[valor] ?? valor;
