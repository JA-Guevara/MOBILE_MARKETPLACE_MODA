import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/api_exception.dart';
import '../domain/cambio.dart';
import '../infrastructure/exchanges_api.dart';

class EstadoCambio {
  const EstadoCambio({
    this.buscando = false,
    this.calculando = false,
    this.ejecutando = false,
    this.orden,
    this.prendaDevuelta,
    this.calculo,
    this.cambioRealizado,
    this.error,
  });

  final bool buscando;
  final bool calculando;
  final bool ejecutando;
  final ExchangeOrderLookup? orden;
  final ExchangeOrderItem? prendaDevuelta;
  final ExchangeCalculationResult? calculo;
  final ExchangeDetail? cambioRealizado;
  final String? error;

  EstadoCambio copyWith({
    bool? buscando,
    bool? calculando,
    bool? ejecutando,
    ExchangeOrderLookup? orden,
    ExchangeOrderItem? prendaDevuelta,
    ExchangeCalculationResult? calculo,
    ExchangeDetail? cambioRealizado,
    String? error,
    bool limpiarError = false,
    bool limpiarSeleccion = false,
  }) =>
      EstadoCambio(
        buscando: buscando ?? this.buscando,
        calculando: calculando ?? this.calculando,
        ejecutando: ejecutando ?? this.ejecutando,
        orden: orden ?? this.orden,
        prendaDevuelta: limpiarSeleccion ? null : (prendaDevuelta ?? this.prendaDevuelta),
        calculo: limpiarSeleccion ? null : (calculo ?? this.calculo),
        cambioRealizado: cambioRealizado ?? this.cambioRealizado,
        error: limpiarError ? null : (error ?? this.error),
      );
}

class CambioController extends StateNotifier<EstadoCambio> {
  CambioController(this._api) : super(const EstadoCambio());

  final ExchangesApi _api;

  Future<void> buscarOrden(String query) async {
    if (query.trim().isEmpty) return;
    state = state.copyWith(buscando: true, limpiarError: true, limpiarSeleccion: true);
    try {
      final ord = await _api.lookupOrder(query);
      state = state.copyWith(buscando: false, orden: ord);
    } on ApiException catch (e) {
      state = state.copyWith(buscando: false, error: e.message);
    } catch (e) {
      state = state.copyWith(buscando: false, error: e.toString());
    }
  }

  void seleccionarPrendaDevolucion(ExchangeOrderItem item) {
    state = state.copyWith(prendaDevuelta: item, limpiarSeleccion: false);
  }

  Future<void> calcular({
    required String branchId,
    required String originalVariantId,
    required int returnedQuantity,
    required double originalUnitPrice,
    required String newVariantId,
    required int deliveredQuantity,
    required double newUnitPrice,
  }) async {
    state = state.copyWith(calculando: true, limpiarError: true);
    try {
      final res = await _api.calculate(
        branchId: branchId,
        lines: [
          {
            'original_variant_id': originalVariantId,
            'returned_quantity': returnedQuantity,
            'original_unit_price': originalUnitPrice.toStringAsFixed(2),
            'new_variant_id': newVariantId,
            'delivered_quantity': deliveredQuantity,
            'new_unit_price': newUnitPrice.toStringAsFixed(2),
          }
        ],
      );
      state = state.copyWith(calculando: false, calculo: res);
    } on ApiException catch (e) {
      state = state.copyWith(calculando: false, error: e.message);
    } catch (e) {
      state = state.copyWith(calculando: false, error: e.toString());
    }
  }

  Future<bool> confirmarCambio({
    required String originalOrderId,
    required String branchId,
    required String paymentMethod,
    required String originalVariantId,
    required int returnedQuantity,
    required double originalUnitPrice,
    required String newVariantId,
    required int deliveredQuantity,
    required double newUnitPrice,
    double? cashReceived,
    String? notes,
  }) async {
    state = state.copyWith(ejecutando: true, limpiarError: true);
    try {
      final detail = await _api.executeExchange({
        'original_order_id': originalOrderId,
        'branch_id': branchId,
        'payment_method': paymentMethod,
        if (cashReceived != null) 'cash_received': cashReceived.toStringAsFixed(2),
        if (notes != null) 'notes': notes,
        'lines': [
          {
            'original_variant_id': originalVariantId,
            'returned_quantity': returnedQuantity,
            'original_unit_price': originalUnitPrice.toStringAsFixed(2),
            'new_variant_id': newVariantId,
            'delivered_quantity': deliveredQuantity,
            'new_unit_price': newUnitPrice.toStringAsFixed(2),
          }
        ],
      });
      state = state.copyWith(ejecutando: false, cambioRealizado: detail);
      return true;
    } on ApiException catch (e) {
      state = state.copyWith(ejecutando: false, error: e.message);
      return false;
    } catch (e) {
      state = state.copyWith(ejecutando: false, error: e.toString());
      return false;
    }
  }
}
