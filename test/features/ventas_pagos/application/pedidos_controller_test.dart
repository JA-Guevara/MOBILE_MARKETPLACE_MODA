import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_marketplace_moda/core/network/api_client.dart';
import 'package:mobile_marketplace_moda/features/ventas_pagos/application/pedidos_controller.dart';
import 'package:mobile_marketplace_moda/features/ventas_pagos/infrastructure/commerce_api.dart';

class _ServidorFalso implements HttpClientAdapter {
  final List<String> pedidos = [];
  final List<Map<String, dynamic>> cuerpos = [];
  final Map<String, int> fallan = {};

  String estado = 'delivered';
  String estadoPago = 'paid';
  String metodoPago = 'manual';
  String? urlCheckout = 'https://stripe.test/reintento';
  String estadoCheckout = 'open';
  bool puedeDevolver = true;
  Map<String, int> unidades = const {'v1': 2};
  List<Map<String, dynamic>> devoluciones = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    pedidos.add('${options.method} ${options.path}');
    if (options.data is Map<String, dynamic>) {
      cuerpos.add(options.data as Map<String, dynamic>);
    }

    final falla = fallan[options.path];
    if (falla != null) {
      return _json({
        'success': false,
        'error': {'code': 'x', 'message': 'El pedido ya fue despachado.'},
      }, falla);
    }
    return _json({
      'success': true,
      'message': '',
      'data': _datoDe(options),
    }, 200);
  }

  Object _datoDe(RequestOptions options) {
    final path = options.path;
    // El endpoint de cliente devuelve una lista directa, no el objeto
    // paginado que usa administración.
    if (path == '/commerce/orders') return [_pedido()];
    if (path.endsWith('/returns') && options.method == 'GET') {
      return {
        'can_request': puedeDevolver,
        'reason': puedeDevolver ? null : 'El pedido todavía no fue entregado.',
        'units': unidades,
        'returns': devoluciones,
      };
    }
    if (path.endsWith('/exchange-options')) {
      return [
        {
          'variant_id': 'v2',
          'product_name': 'Polera POLO',
          'size': 'L',
          'color': 'Azul',
          'available': 2,
          'price': '75.00',
        },
      ];
    }
    if (path.endsWith('/exchanges')) {
      return {
        'id': 'e1',
        'order_id': 'o1',
        'status': 'requested',
        'kind': 'exchange',
        'reason': 'Otra talla',
        'refund_amount': '0.00',
        'items': [],
        'created_at': '2026-09-21T10:00:00Z',
      };
    }
    if (path.endsWith('/returns')) {
      return {
        'id': 'r1',
        'order_id': 'o1',
        'status': 'requested',
        'reason': 'No me quedó bien',
        'refund_amount': '75.00',
        'items': [],
        'created_at': '2026-09-21T10:00:00Z',
      };
    }
    if (path.endsWith('/checkout')) {
      if (estadoCheckout == 'paid') {
        estado = 'paid';
        estadoPago = 'paid';
      }
      return {'url': urlCheckout, 'status': estadoCheckout};
    }
    if (path.endsWith('/cancel')) return const <String, dynamic>{};
    if (path.startsWith('/commerce/orders/')) return _pedido();
    return const <String, dynamic>{};
  }

  Map<String, dynamic> _pedido() => {
    'id': 'o1',
    'number': 'P-001',
    'customer_email': 'ana@test.com',
    'branch_id': 'b1',
    'status': estado,
    'payment_status': estadoPago,
    'payment_method': metodoPago,
    'subtotal': '150.00',
    'total': '150.00',
    'currency': 'BOB',
    'created_at': '2026-09-20T10:00:00Z',
    'address': {
      'recipient': 'Ana Vargas',
      'phone': '77712345',
      'line1': 'Calle Falsa 123',
      'city': 'Santa Cruz',
      'country': 'BO',
    },
    'items': [
      {
        'variant_id': 'v1',
        'product_id': 'p1',
        'name': 'Polera POLO',
        'sku': 'SKU-1',
        'size': 'M',
        'color': 'Azul',
        'unit_price': '75.00',
        'quantity': 2,
        'available': 2,
        'line_total': '150.00',
      },
    ],
    'tracking': [
      {'status': 'pending_payment', 'note': '', 'date': '2026-09-20T10:00:00Z'},
      {
        'status': 'paid',
        'note': 'Pago confirmado',
        'date': '2026-09-20T11:00:00Z',
      },
    ],
  };

  static ResponseBody _json(Object cuerpo, int estado) =>
      ResponseBody.fromString(
        jsonEncode(cuerpo),
        estado,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );

  @override
  void close({bool force = false}) {}
}

void main() {
  late _ServidorFalso servidor;

  CommerceApi api() {
    servidor = _ServidorFalso();
    final dio = Dio(
      BaseOptions(
        baseUrl: 'http://test/api/v1',
        validateStatus: (s) => s != null && s < 400,
      ),
    );
    dio.httpClientAdapter = servidor;
    return CommerceApi(ApiClient(dio: dio));
  }

  group('lista', () {
    test('trae los pedidos del cliente', () async {
      final control = PedidosController(api());

      await control.cargar();

      expect(control.state.cargando, isFalse);
      expect(control.state.pedidos, hasLength(1));
      expect(control.state.pedidos.first.number, 'P-001');
      // Las etiquetas salen del mismo diccionario que usa la web.
      expect(control.state.pedidos.first.etiquetaEstado, 'Entregado');
    });
  });

  group('detalle', () {
    test('carga el pedido y su disponibilidad de devolución', () async {
      final control = PedidoController(api());

      await control.cargar('o1');

      expect(control.state.pedido?.number, 'P-001');
      expect(servidor.pedidos, contains('GET /commerce/orders/o1/returns'));
      expect(control.state.sePuedeDevolver, isTrue);
      expect(control.state.disponiblesDe('v1'), 2);
    });

    test('un pedido entregado no se puede cancelar', () async {
      final control = PedidoController(api());

      await control.cargar('o1');

      expect(control.state.sePuedeCancelar, isFalse);
    });

    test(
      'reconcilia el pago con Stripe y conserva el pedido actualizado',
      () async {
        final comercio = api();
        servidor.estado = 'pending_payment';
        servidor.estadoPago = 'pending';
        servidor.metodoPago = 'stripe';
        final control = PedidoController(comercio);
        await control.cargar('o1');

        await control.reconciliarPago();

        expect(
          servidor.pedidos,
          contains('POST /commerce/orders/o1/payment-status'),
        );
        expect(control.state.pedido, isNotNull);
        expect(control.state.mensaje, isNotNull);
      },
    );

    test('un pedido en preparación sí se puede cancelar', () async {
      final comercio = api();
      servidor.estado = 'processing';
      final control = PedidoController(comercio);

      await control.cargar('o1');

      expect(control.state.sePuedeCancelar, isTrue);
    });

    test('cancelar manda el motivo que exige el backend', () async {
      final comercio = api();
      servidor.estado = 'processing';
      final control = PedidoController(comercio);
      await control.cargar('o1');

      await control.cancelar('Me equivoqué de talla');

      expect(servidor.pedidos, contains('POST /commerce/orders/o1/cancel'));
      expect(servidor.cuerpos.last['reason'], 'Me equivoqué de talla');
      expect(control.state.mensaje, isNotNull);
    });

    test('un rechazo al cancelar se muestra sin perder el pedido', () async {
      final comercio = api();
      servidor.estado = 'processing';
      final control = PedidoController(comercio);
      await control.cargar('o1');
      servidor.fallan['/commerce/orders/o1/cancel'] = 409;

      await control.cancelar('Ya no lo quiero');

      expect(control.state.errorAccion, 'El pedido ya fue despachado.');
      expect(control.state.pedido, isNotNull);
    });
  });

  group('reanudar el pago', () {
    test('un pedido Stripe sin pagar ofrece volver al checkout', () async {
      final comercio = api();
      servidor.metodoPago = 'stripe';
      servidor.estado = 'pending_payment';
      servidor.estadoPago = 'pending';
      final control = PedidoController(comercio);
      await control.cargar('o1');

      expect(control.state.sePuedeReanudarPago, isTrue);
      expect(await control.reanudarPago(), 'https://stripe.test/reintento');
    });

    test('un pedido ya pagado no lo ofrece', () async {
      final comercio = api();
      servidor.metodoPago = 'stripe';
      servidor.estadoPago = 'paid';
      final control = PedidoController(comercio);

      await control.cargar('o1');

      expect(control.state.sePuedeReanudarPago, isFalse);
    });

    test('un pedido de pago coordinado tampoco', () async {
      final control = PedidoController(api());

      await control.cargar('o1');

      expect(control.state.sePuedeReanudarPago, isFalse);
    });

    test(
      'si el pago terminó antes de abrir Stripe actualiza el pedido',
      () async {
        final comercio = api();
        servidor.metodoPago = 'stripe';
        servidor.estado = 'pending_payment';
        servidor.estadoPago = 'pending';
        servidor.urlCheckout = null;
        servidor.estadoCheckout = 'paid';
        final control = PedidoController(comercio);
        await control.cargar('o1');

        expect(await control.reanudarPago(), isNull);
        expect(control.state.pedido?.paymentStatus, 'paid');
        expect(control.state.sePuedeReanudarPago, isFalse);
        expect(control.state.ocupado, isFalse);
        expect(control.state.mensaje, contains('pagado'));
      },
    );

    test(
      'una respuesta sin enlace deja el botón habilitado para reintentar',
      () async {
        final comercio = api();
        servidor.metodoPago = 'stripe';
        servidor.estado = 'pending_payment';
        servidor.estadoPago = 'pending';
        servidor.urlCheckout = null;
        final control = PedidoController(comercio);
        await control.cargar('o1');

        expect(await control.reanudarPago(), isNull);
        expect(control.state.ocupado, isFalse);
        expect(control.state.sePuedeReanudarPago, isTrue);
        expect(control.state.errorAccion, contains('enlace'));
      },
    );

    test('una sesión expirada no ofrece volver a pagar el pedido', () async {
      final comercio = api();
      servidor.metodoPago = 'stripe';
      servidor.estado = 'expired';
      servidor.estadoPago = 'cancelled';
      final control = PedidoController(comercio);
      await control.cargar('o1');

      expect(control.state.sePuedeReanudarPago, isFalse);
    });
  });

  group('devoluciones', () {
    test(
      'consulta opciones y solicita un cambio con el mismo backend',
      () async {
        final control = PedidoController(api());
        await control.cargar('o1');
        final options = await control.opcionesCambio('v1');
        expect(options.single.variantId, 'v2');
        expect(
          await control.solicitarCambio(
            variantId: 'v1',
            replacementVariantId: 'v2',
            quantity: 1,
            reason: 'Necesito otra talla',
            clientRequestId: CommerceApi.nuevaClaveSolicitud(),
          ),
          isTrue,
        );
        expect(
          servidor.pedidos,
          contains('POST /commerce/orders/o1/exchanges'),
        );
        expect(servidor.cuerpos.last['replacement_variant_id'], 'v2');
        expect(servidor.cuerpos.last['client_request_id'], isNotEmpty);
      },
    );

    test('no se puede pedir sin unidades ni sin motivo', () async {
      final control = PedidoController(api());
      await control.cargar('o1');

      expect(control.state.sePuedeSolicitarDevolucion, isFalse);

      control.marcarUnidades('v1', 1);
      expect(control.state.sePuedeSolicitarDevolucion, isFalse);

      control.escribirRazon('no');
      // Un motivo de menos de 5 caracteres no le dice nada a quien lo revise.
      expect(control.state.sePuedeSolicitarDevolucion, isFalse);

      // Y los espacios no cuentan como motivo.
      control.escribirRazon('        ');
      expect(control.state.sePuedeSolicitarDevolucion, isFalse);

      control.escribirRazon('No me quedó bien');
      expect(control.state.sePuedeSolicitarDevolucion, isTrue);
    });

    test('no deja marcar más unidades de las devolvibles', () async {
      final control = PedidoController(api());
      await control.cargar('o1');

      control.marcarUnidades('v1', 9);

      expect(control.state.seleccion['v1'], 2);
    });

    test('marcar cero saca la línea de la selección', () async {
      final control = PedidoController(api());
      await control.cargar('o1');

      control.marcarUnidades('v1', 2);
      control.marcarUnidades('v1', 0);

      expect(control.state.seleccion, isEmpty);
      expect(control.state.unidadesElegidas, 0);
    });

    test(
      'solicitar manda items según el contrato y limpia el formulario',
      () async {
        final control = PedidoController(api());
        await control.cargar('o1');
        control.marcarUnidades('v1', 2);
        control.escribirRazon('  La prenda vino con una falla  ');

        await control.solicitarDevolucion();

        expect(servidor.pedidos, contains('POST /commerce/orders/o1/returns'));
        final cuerpo = servidor.cuerpos.last;
        expect(cuerpo['items'], [
          {'variant_id': 'v1', 'quantity': 2},
        ]);
        expect(cuerpo['reason'], 'La prenda vino con una falla');
        expect(control.state.seleccion, isEmpty);
        expect(control.state.razon, '');
        expect(control.state.mensaje, isNotNull);
      },
    );

    test(
      'un pedido no entregado explica por qué no se puede devolver',
      () async {
        final comercio = api();
        servidor.puedeDevolver = false;
        servidor.estado = 'processing';
        final control = PedidoController(comercio);

        await control.cargar('o1');

        expect(control.state.sePuedeDevolver, isFalse);
        expect(
          control.state.devoluciones?.motivo,
          'El pedido todavía no fue entregado.',
        );
      },
    );
  });
}
