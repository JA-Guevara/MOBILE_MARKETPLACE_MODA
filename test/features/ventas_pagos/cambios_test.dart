import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_marketplace_moda/features/ventas_pagos/application/cambio_controller.dart';
import 'package:mobile_marketplace_moda/features/ventas_pagos/domain/cambio.dart';
import 'package:mobile_marketplace_moda/features/ventas_pagos/infrastructure/exchanges_api.dart';

class MockExchangesApi implements ExchangesApi {
  @override
  Future<ExchangePolicy> getPolicy() async {
    return const ExchangePolicy(tenantId: 't-1', exchangeDays: 15);
  }

  @override
  Future<ExchangeOrderLookup> lookupOrder(String query) async {
    return const ExchangeOrderLookup(
      orderId: 'ord-100',
      orderNumber: 'ORD-100',
      purchaseDate: '2026-11-01T10:00:00Z',
      deadlineDays: 15,
      remainingDays: 11,
      canExchange: true,
      customerEmail: 'cliente@test.com',
      branchId: 'b-1',
      items: [
        ExchangeOrderItem(
          variantId: 'v-orig-1',
          productName: 'Vestido Lino',
          size: 'M',
          color: 'Rojo',
          originalQuantity: 2,
          alreadyExchangedQuantity: 0,
          availableForExchange: 2,
          unitPrice: 150.0,
        ),
      ],
    );
  }

  @override
  Future<ExchangeCalculationResult> calculate({
    String? orderId,
    required String branchId,
    required List<Map<String, dynamic>> lines,
  }) async {
    return const ExchangeCalculationResult(
      totalReturnedValue: 150.0,
      totalDeliveredValue: 180.0,
      differenceAmount: 30.0,
      tipoDiferencia: 'PAGO_CLIENTE',
    );
  }

  @override
  Future<ExchangeDetail> executeExchange(Map<String, dynamic> payload) async {
    return const ExchangeDetail(
      id: 'ex-555',
      originalOrderId: 'ord-100',
      originalOrderNumber: 'ORD-100',
      differenceAmount: 30.0,
      paymentMethod: 'cash',
      status: 'COMPLETED',
      createdAt: '2026-11-04T12:00:00Z',
    );
  }
}

void main() {
  group('CU-08 Cambios de prenda (Mobile)', () {
    late MockExchangesApi api;
    late CambioController controller;

    setUp(() {
      api = MockExchangesApi();
      controller = CambioController(api);
    });

    test('busca pedido y carga líneas y días restantes', () async {
      await controller.buscarOrden('ORD-100');
      final state = controller.state;
      expect(state.orden, isNotNull);
      expect(state.orden!.orderNumber, 'ORD-100');
      expect(state.orden!.remainingDays, 11);
      expect(state.orden!.canExchange, isTrue);
      expect(state.orden!.items.length, 1);
    });

    test('selecciona prenda y calcula diferencia de precio', () async {
      await controller.buscarOrden('ORD-100');
      final item = controller.state.orden!.items.first;
      controller.seleccionarPrendaDevolucion(item);
      expect(controller.state.prendaDevuelta, isNotNull);
      expect(controller.state.prendaDevuelta!.variantId, 'v-orig-1');

      await controller.calcular(
        branchId: 'b-1',
        originalVariantId: item.variantId,
        returnedQuantity: 1,
        originalUnitPrice: item.unitPrice,
        newVariantId: 'v-new-2',
        deliveredQuantity: 1,
        newUnitPrice: 180.0,
      );

      final state = controller.state;
      expect(state.calculo, isNotNull);
      expect(state.calculo!.differenceAmount, 30.0);
      expect(state.calculo!.tipoDiferencia, 'PAGO_CLIENTE');
    });

    test('confirma cambio y recibe comprobante con status COMPLETED', () async {
      final success = await controller.confirmarCambio(
        originalOrderId: 'ord-100',
        branchId: 'b-1',
        paymentMethod: 'cash',
        originalVariantId: 'v-orig-1',
        returnedQuantity: 1,
        originalUnitPrice: 150.0,
        newVariantId: 'v-new-2',
        deliveredQuantity: 1,
        newUnitPrice: 180.0,
        cashReceived: 50.0,
      );

      expect(success, isTrue);
      expect(controller.state.cambioRealizado, isNotNull);
      expect(controller.state.cambioRealizado!.id, 'ex-555');
      expect(controller.state.cambioRealizado!.status, 'COMPLETED');
    });
  });
}
