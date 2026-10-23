import 'dart:async';
import 'dart:math';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../domain/commerce_models.dart';

/// Cliente de ventas y pagos. Réplica de `commerce.service.ts` + la parte
/// POS/devoluciones que la web vive en el mismo dominio. Como en la web, el
/// prefijo de recurso (`/commerce`) se arma acá; la pantalla no lo conoce.
class CommerceApi {
  const CommerceApi(this._api);

  final ApiClient _api;

  static String nuevaClaveSolicitud() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }

  // --- Sucursales / puntos de caja ---

  Future<List<Sucursal>> sucursales() async {
    final filas = await _api.get<List<dynamic>>('/commerce/branches');
    return filas
        .map((e) => Sucursal.desdeJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<PuntoCaja>> puntosCaja(String branchId) async {
    final filas = await _api.get<List<dynamic>>(
      '/commerce/admin/cash-points',
      query: {'branch_id': branchId},
    );
    return filas
        .map((e) => PuntoCaja.desdeJson(e as Map<String, dynamic>))
        .toList();
  }

  // --- Carrito ---

  Future<Carrito> carrito({String? branchId, String? couponCode}) async {
    final json = await _api.get<Map<String, dynamic>>(
      '/commerce/cart',
      query: {
        if (branchId != null) 'branch_id': branchId,
        if (couponCode != null) 'coupon_code': couponCode,
      },
    );
    return Carrito.desdeJson(json);
  }

  /// El backend confirma el cambio sin devolver el carrito. Después de esta
  /// operación el controlador vuelve a leerlo para mostrar los totales y el
  /// stock vigentes de la sucursal elegida.
  Future<void> cambiarCantidad(String variantId, int cantidad) {
    return _api.putSinContenido(
      '/commerce/cart/items/$variantId',
      body: {'quantity': cantidad},
    );
  }

  /// Suma una unidad sin bajar a uno una prenda que ya estaba en el carrito.
  /// El endpoint es de tipo «establecer cantidad», por eso primero se consulta
  /// el valor actual y recién después se lo actualiza.
  Future<void> agregarUno(String variantId) async {
    final actual = await carrito();
    final item = actual.items.where((item) => item.variantId == variantId);
    final cantidad = item.isEmpty ? 1 : item.first.quantity + 1;
    await cambiarCantidad(variantId, cantidad);
  }

  Future<void> quitarItem(String variantId) =>
      _api.deleteSinContenido('/commerce/cart/items/$variantId');

  /// Recalcula el carrito con el cupón (solo lo valida), web `POST /cart/validate-coupon`.
  Future<Map<String, dynamic>> validarCupon(
    String codigo, {
    String? branchId,
  }) async {
    return _api.post<Map<String, dynamic>>(
      '/commerce/cart/validate-coupon',
      body: {'code': codigo, if (branchId != null) 'branch_id': branchId},
    );
  }

  Future<void> vaciarCarrito() => _api.deleteSinContenido('/commerce/cart');

  // --- Pedidos ---

  Future<Pedido> crearPedido({
    required String branchId,
    required DireccionEntrega direccion,
    required String metodoPago,
    String? cuponCode,
  }) async {
    final json = await _api.post<Map<String, dynamic>>(
      '/commerce/orders',
      body: {
        'branch_id': branchId,
        'address': direccion.aJson(),
        'payment_method': metodoPago,
        'channel': 'mobile',
        if (cuponCode != null && cuponCode.isNotEmpty) 'coupon_code': cuponCode,
      },
    );
    return Pedido.desdeJson(json);
  }

  Future<List<Pedido>> pedidos({int limit = 20, int offset = 0}) async {
    // El contrato cliente del backend devuelve una lista directa; los paneles
    // administrativos usan objetos paginados, pero no este endpoint.
    final filas = await _api.get<List<dynamic>>(
      '/commerce/orders',
      query: {'limit': limit, 'offset': offset},
    );
    return filas
        .whereType<Map<String, dynamic>>()
        .map(Pedido.desdeJson)
        .toList();
  }

  Future<Pedido> pedidoDetalle(String id) async {
    final json = await _api.get<Map<String, dynamic>>('/commerce/orders/$id');
    return Pedido.desdeJson(json);
  }

  /// Arranca la sesión Stripe y devuelve la URL a la que redirigir.
  ///
  /// El pedido ya existe cuando se llega aquí y el backend usa una clave de
  /// idempotencia por pedido para Stripe. Por eso es seguro reintentar una vez
  /// cuando Railway devuelve 502 o corta la conexión: no se duplica ni el
  /// pedido ni el cobro; sólo se recupera la URL de la misma sesión.
  Future<({String? url, String? status})> checkout(String pedidoId) async {
    for (var intento = 0; intento < 2; intento++) {
      try {
        final json = await _api.post<Map<String, dynamic>>(
          '/commerce/orders/$pedidoId/checkout',
          body: const <String, dynamic>{},
        );
        return (url: json['url'] as String?, status: json['status'] as String?);
      } on ApiException catch (error) {
        final esTransitorio =
            error.statusCode == null || error.statusCode == 502;
        if (!esTransitorio || intento == 1) rethrow;
        await Future<void>.delayed(const Duration(milliseconds: 1200));
      }
    }
    // El ciclo siempre retorna o relanza, pero Dart no puede inferirlo.
    throw StateError('No se pudo iniciar Stripe.');
  }

  Future<void> cancelarPedido(String id, {required String razon}) async {
    await _api.post<void>(
      '/commerce/orders/$id/cancel',
      body: {'reason': razon},
    );
  }

  /// Consulta Stripe desde el servidor y devuelve el pedido con su estado
  /// vigente. El navegador nunca acredita un pago por sí mismo.
  Future<Pedido> reconciliarPagoPedido(String id) async {
    final json = await _api.post<Map<String, dynamic>>(
      '/commerce/orders/$id/payment-status',
      body: const <String, dynamic>{},
    );
    return Pedido.desdeJson(json);
  }

  // --- Devoluciones (cliente) ---

  Future<DisponibilidadDevolucion> disponibilidadDevolucion(
    String orderId,
  ) async {
    final json = await _api.get<Map<String, dynamic>>(
      '/commerce/orders/$orderId/returns',
    );
    return DisponibilidadDevolucion.desdeJson(json);
  }

  Future<Devolucion> solicitarDevolucion(
    String orderId, {
    required Map<String, int> units,
    required String razon,
    required String clientRequestId,
  }) async {
    final json = await _api.post<Map<String, dynamic>>(
      '/commerce/orders/$orderId/returns',
      body: {
        'items': [
          for (final entry in units.entries)
            {'variant_id': entry.key, 'quantity': entry.value},
        ],
        'reason': razon,
        'client_request_id': clientRequestId,
      },
    );
    return Devolucion.desdeJson(json);
  }

  Future<List<OpcionCambio>> opcionesCambio(
    String orderId,
    String variantId,
  ) async {
    final rows = await _api.get<List<dynamic>>(
      '/commerce/orders/$orderId/exchange-options',
      query: {'variant_id': variantId},
    );
    return rows
        .map((row) => OpcionCambio.desdeJson(row as Map<String, dynamic>))
        .toList();
  }

  Future<Devolucion> solicitarCambio(
    String orderId, {
    required String variantId,
    required String replacementVariantId,
    required int quantity,
    required String reason,
    required String clientRequestId,
  }) async {
    final json = await _api.post<Map<String, dynamic>>(
      '/commerce/orders/$orderId/exchanges',
      body: {
        'variant_id': variantId,
        'replacement_variant_id': replacementVariantId,
        'quantity': quantity,
        'reason': reason,
        'client_request_id': clientRequestId,
      },
    );
    return Devolucion.desdeJson(json);
  }

  // --- Mostrador / POS ---

  Future<BusquedaMostrador> buscarMostrador({
    required String orderNumber,
    String? branchId,
  }) async {
    final json = await _api.get<Map<String, dynamic>>(
      '/commerce/admin/pos/orders',
      query: {
        'number': orderNumber,
        if (branchId != null) 'branch_id': branchId,
      },
    );
    return BusquedaMostrador.desdeJson(json);
  }

  Future<Devolucion> registrarVentaMostrador({
    required String orderId,
    required Map<String, int> units,
    required String razon,
    required String metodoReintegro,
    String? nota,
  }) async {
    final json = await _api.post<Map<String, dynamic>>(
      '/commerce/admin/pos/returns',
      body: {
        'order_id': orderId,
        'units': units,
        'reason': razon,
        'refund_method': metodoReintegro,
        if (nota != null) 'note': nota,
      },
    );
    return Devolucion.desdeJson(json);
  }

  /// Cobra una venta nueva en el mostrador (web `POST /admin/pos/sales`).
  Future<Pedido> venderMostrador({
    required String branchId,
    required String cashPointId,
    required Map<String, int> items,
    required String metodoPago,
    double? amountReceived,
  }) async {
    final json = await _api.post<Map<String, dynamic>>(
      '/commerce/admin/pos/sales',
      body: {
        'branch_id': branchId,
        'cash_point_id': cashPointId,
        'items': items,
        'payment_method': metodoPago,
        if (amountReceived != null) 'amount_received': amountReceived,
      },
    );
    return Pedido.desdeJson(json);
  }

  // --- Favoritos (web `engagement.service.ts`) ---

  Future<List<Favorito>> favoritos() async {
    final filas = await _api.get<List<dynamic>>('/commerce/favorites');
    return filas
        .map((e) => Favorito.desdeJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<EstadoFavorito> estadoFavorito(String productId) async {
    final json = await _api.get<Map<String, dynamic>>(
      '/commerce/favorites/$productId',
    );
    return EstadoFavorito.desdeJson(json);
  }

  Future<EstadoFavorito> guardarFavorito(
    String productId, {
    bool stockAlert = true,
    bool priceAlert = true,
  }) async {
    final json = await _api.put<Map<String, dynamic>>(
      '/commerce/favorites/$productId',
      body: {'stock_alert': stockAlert, 'price_alert': priceAlert},
    );
    return EstadoFavorito.desdeJson(json);
  }

  Future<void> quitarFavorito(String productId) =>
      _api.delete<void>('/commerce/favorites/$productId');

  // --- Promociones (web `engagement.service.ts` admin) ---

  Future<List<Promocion>> promociones() async {
    final filas = await _api.get<List<dynamic>>('/commerce/admin/promotions');
    return filas
        .map((e) => Promocion.desdeJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<Promocion> crearPromocion(Map<String, dynamic> datos) async {
    final json = await _api.post<Map<String, dynamic>>(
      '/commerce/admin/promotions',
      body: datos,
    );
    return Promocion.desdeJson(json);
  }

  Future<Promocion> actualizarPromocion(
    String id,
    Map<String, dynamic> datos,
  ) async {
    final json = await _api.patch<Map<String, dynamic>>(
      '/commerce/admin/promotions/$id',
      body: datos,
    );
    return Promocion.desdeJson(json);
  }

  Future<void> togglePromocion(String id) async {
    await _api.patch<void>(
      '/commerce/admin/promotions/$id',
      body: {'toggle': true},
    );
  }

  Future<void> eliminarPromocion(String id) =>
      _api.delete<void>('/commerce/admin/promotions/$id');
}
