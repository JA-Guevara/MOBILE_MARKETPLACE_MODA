class ExchangePolicy {
  const ExchangePolicy({
    required this.tenantId,
    required this.exchangeDays,
  });

  factory ExchangePolicy.fromJson(Map<String, dynamic> json) => ExchangePolicy(
        tenantId: json['tenant_id'] as String,
        exchangeDays: json['exchange_days'] as int,
      );

  final String tenantId;
  final int exchangeDays;
}

class ExchangeOrderItem {
  const ExchangeOrderItem({
    required this.variantId,
    required this.productName,
    required this.originalQuantity,
    required this.alreadyExchangedQuantity,
    required this.availableForExchange,
    required this.unitPrice,
    this.size,
    this.color,
    this.sku,
  });

  factory ExchangeOrderItem.fromJson(Map<String, dynamic> json) => ExchangeOrderItem(
        variantId: json['variant_id'] as String,
        productName: json['product_name'] as String? ?? 'Prenda',
        size: json['size'] as String?,
        color: json['color'] as String?,
        sku: json['sku'] as String?,
        originalQuantity: json['original_quantity'] as int? ?? 1,
        alreadyExchangedQuantity: json['already_exchanged_quantity'] as int? ?? 0,
        availableForExchange: json['available_for_exchange'] as int? ?? 1,
        unitPrice: double.tryParse(json['unit_price']?.toString() ?? '0') ?? 0.0,
      );

  final String variantId;
  final String productName;
  final String? size;
  final String? color;
  final String? sku;
  final int originalQuantity;
  final int alreadyExchangedQuantity;
  final int availableForExchange;
  final double unitPrice;
}

class ExchangeOrderLookup {
  const ExchangeOrderLookup({
    required this.orderId,
    required this.orderNumber,
    required this.purchaseDate,
    required this.deadlineDays,
    required this.remainingDays,
    required this.canExchange,
    required this.customerEmail,
    required this.branchId,
    required this.items,
  });

  factory ExchangeOrderLookup.fromJson(Map<String, dynamic> json) => ExchangeOrderLookup(
        orderId: json['order_id'] as String,
        orderNumber: json['order_number'] as String,
        purchaseDate: json['purchase_date'] as String,
        deadlineDays: json['deadline_days'] as int? ?? 15,
        remainingDays: json['remaining_days'] as int? ?? 0,
        canExchange: json['can_exchange'] as bool? ?? false,
        customerEmail: json['customer_email'] as String? ?? '',
        branchId: json['branch_id'] as String? ?? '',
        items: (json['items'] as List<dynamic>? ?? [])
            .map((e) => ExchangeOrderItem.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  final String orderId;
  final String orderNumber;
  final String purchaseDate;
  final int deadlineDays;
  final int remainingDays;
  final bool canExchange;
  final String customerEmail;
  final String branchId;
  final List<ExchangeOrderItem> items;
}

class ExchangeCalculationResult {
  const ExchangeCalculationResult({
    required this.totalReturnedValue,
    required this.totalDeliveredValue,
    required this.differenceAmount,
    required this.tipoDiferencia,
  });

  factory ExchangeCalculationResult.fromJson(Map<String, dynamic> json) =>
      ExchangeCalculationResult(
        totalReturnedValue:
            double.tryParse(json['total_returned_value']?.toString() ?? '0') ?? 0.0,
        totalDeliveredValue:
            double.tryParse(json['total_delivered_value']?.toString() ?? '0') ?? 0.0,
        differenceAmount:
            double.tryParse(json['difference_amount']?.toString() ?? '0') ?? 0.0,
        tipoDiferencia: json['tipo_diferencia'] as String? ?? 'CAMBIO_DIRECTO',
      );

  final double totalReturnedValue;
  final double totalDeliveredValue;
  final double differenceAmount;
  final String tipoDiferencia;
}

class ExchangeDetail {
  const ExchangeDetail({
    required this.id,
    required this.originalOrderId,
    required this.differenceAmount,
    required this.paymentMethod,
    required this.status,
    required this.createdAt,
    this.originalOrderNumber,
  });

  factory ExchangeDetail.fromJson(Map<String, dynamic> json) => ExchangeDetail(
        id: json['id'] as String,
        originalOrderId: json['original_order_id'] as String,
        originalOrderNumber: json['original_order_number'] as String?,
        differenceAmount:
            double.tryParse(json['difference_amount']?.toString() ?? '0') ?? 0.0,
        paymentMethod: json['payment_method'] as String? ?? 'none',
        status: json['status'] as String? ?? 'COMPLETED',
        createdAt: json['created_at'] as String? ?? '',
      );

  final String id;
  final String originalOrderId;
  final String? originalOrderNumber;
  final double differenceAmount;
  final String paymentMethod;
  final String status;
  final String createdAt;
}
