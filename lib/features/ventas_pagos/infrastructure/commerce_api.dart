import 'package:dio/dio.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../../../shared/models/api_response.dart';
import 'domain/commerce_models.dart';

/// Cliente de ventas y pagos. Réplica de `commerce.service.ts` + la parte
/// POS/devoluciones que la web vive en el mismo dominio. Como en la web, el
/// prefijo de recurso (`/commerce`) se arma acá; la pantalla no lo conoce.
class CommerceApi {
  const CommerceApi(this._api);

  final ApiClient _api;

  // --- Sucursales / puntos de caja ---

  Future<List<Sucursal>> sucursales() async {
    final filas = await _api.get<List<dynamic>>('/commerce/branches');
    return filas.map((e) => Sucursal.desdeJson(e as Map<String, dynamic>)).toList();
  }

  Future<List<PuntoCaja>> puntosCaja(String branchId) async {
    final filas = await _api.get<List<dynamic>>('/commerce/admin/pos/cash-points',
        query: {'branch_id': branchId});
    return filas.map((e) => PuntoCaja.desdeJson(e as Map<String, dynamic>)).toList();
  }

  // --- Carrito ---

  Future<Carrito> carrito({String? branchId, String? couponCode}) async {
    final json = await _api.get<Map<String, dynamic>>('/commerce/cart', query: {
      if (branchId != null) 'branch_id': branchId,
      if (couponCode != null) 'coupon_code': couponCode,
    });
    return Carrito.desdeJson(json);
  }

  Future<Carrito> cambiarCantidad(String variantId, int cantidad) async {
    final json = await _api.put<Map<String, dynamic>>(
      '/commerce/cart/items/$variantId',
      body: {'quantity': cantidad},
    );
    return Carrito.desdeJson(json);
  }

  Future<Carrito> quitarItem(String variantId) async {
    final json = await _api.delete<Map<String, dynamic>>('/commerce/cart/items/$variantId');
    return Carrito.desdeJson(json);
  }

  /// Recalcula el carrito con el cupón (solo lo valida), web `POST /cart/validate-coupon`.
  Future<Map<String, dynamic>> validarCupon(String codigo, {String? branchId}) async {
    return _api.post<Map<String, dynamic>>(
      '/commerce/cart/validate-coupon',
      body: {'code': codigo, if (branchId != null) 'branch_id': branchId},
    );
  }

  Future<void> vaciarCarrito() => _api.delete<void>('/commerce/cart');

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
        if (cuponCode != null && cuponCode.isNotEmpty) 'coupon_code': cuponCode,
      },
    );
    return Pedido.desdeJson(json);
  }

  Future<List<Pedido>> pedidos({int limit = 20, int offset = 0}) async {
    final json = await _api.get<Map<String, dynamic>>(
      '/commerce/orders',
      query: {'limit': limit, 'offset': offset},
    );
    return _listaPedidos(json);
  }

  Future<Pedido> pedidoDetalle(String id) async {
    final json = await _api.get<Map<String, dynamic>>('/commerce/orders/$id');
    return Pedido.desdeJson(json);
  }

  /// Arranca la sesión Stripe y devuelve la URL a la que redirigir.
  Future<({String? url, String? status})> checkout(String pedidoId) async {
    final json = await _api.post<Map<String, dynamic>>(
      '/commerce/orders/$pedidoId/checkout',
      body: const <String, dynamic>{},
    );
    return (url: json['url'] as String?, status: json['status'] as String?);
  }

  Future<void> cancelarPedido(String id, {required String razon}) async {
    await _api.post<void>('/commerce/orders/$id/cancel', body: {'reason': razon});
  }

  Future<bool> confirmarPagoPedido(String id, {String? nota}) async {
    final json = await _api.post<Map<String, dynamic>>(
      '/commerce/orders/$id/payment-status',
      body: {
        'status': 'paid',
        if (nota != null) 'note': nota,
      },
    );
    return json['success'] as bool? ?? false;
  }

  // --- Devoluciones (cliente) ---

  Future<DisponibilidadDevolucion> disponibilidadDevolucion(String orderId) async {
    final json = await _api.get<Map<String, dynamic>>('/commerce/orders/$orderId/returns');
    return DisponibilidadDevolucion.desdeJson(json);
  }

  Future<Devolucion> solicitarDevolucion(
    String orderId, {
    required Map<String, int> units,
    required String razon,
  }) async {
    final json = await _api.post<Map<String, dynamic>>(
      '/commerce/orders/$orderId/returns',
      body: {'units': units, 'reason': razon},
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
      query: {'number': orderNumber, if (branchId != null) 'branch_id': branchId},
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
    return filas.map((e) => Favorito.desdeJson(e as Map<String, dynamic>)).toList();
  }

  Future<EstadoFavorito> estadoFavorito(String productId) async {
    final json = await _api.get<Map<String, dynamic>>('/commerce/favorites/$productId');
    return EstadoFavorito.desdeJson(json);
  }

  Future<EstadoFavorito> guardarFavorito(String productId,
      {bool stockAlert = true, bool priceAlert = true}) async {
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
    return filas.map((e) => Promocion.desdeJson(e as Map<String, dynamic>)).toList();
  }

  Future<Promocion> crearPromocion(Map<String, dynamic> datos) async {
    final json = await _api.post<Map<String, dynamic>>('/commerce/admin/promotions', body: datos);
    return Promocion.desdeJson(json);
  }

  Future<Promocion> actualizarPromocion(String id, Map<String, dynamic> datos) async {
    final json = await _api
        .patch<Map<String, dynamic>>('/commerce/admin/promotions/$id', body: datos);
    return Promocion.desdeJson(json);
  }

  Future<void> togglePromocion(String id) async {
    await _api.patch<void>('/commerce/admin/promotions/$id', body: {'toggle': true});
  }

  Future<void> eliminarPromocion(String id) =>
      _api.delete<void>('/commerce/admin/promotions/$id');
}

List<Pedido> _listaPedidos(Map<String, dynamic> json) {
  final crudo = json.containsKey('items') ? json['items'] : json['orders'];
  if (crudo is List<dynamic>) {
    return crudo.map((e) => Pedido.desdeJson(e as Map<String, dynamic>)).toList();
  }
  return const [];
}
