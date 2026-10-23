import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_marketplace_moda/core/network/api_client.dart';
import 'package:mobile_marketplace_moda/features/usuarios_catalogo/infrastructure/direcciones_api.dart';
import 'package:mobile_marketplace_moda/features/ventas_pagos/application/carrito_controller.dart';
import 'package:mobile_marketplace_moda/features/ventas_pagos/infrastructure/commerce_api.dart';

/// Backend falso con un carrito en memoria: cambiar una cantidad tiene que
/// verse reflejado en el siguiente `GET`, como pasa de verdad.
class _ServidorFalso implements HttpClientAdapter {
  final List<String> pedidos = [];
  final List<Map<String, dynamic>> cuerpos = [];
  final Map<String, int> fallan = {};

  int cantidad = 2;
  int disponible = 5;

  /// Stock por sucursal. El backend responde `available: 0` cuando la variante
  /// no tiene fila de stock en la sucursal consultada, así que una sucursal
  /// que «no trabaja» la prenda se ve igual que una sin unidades.
  Map<String, int> disponiblePorSucursal = const {};

  /// Sucursal que llegó en el último `GET /commerce/cart`.
  String? ultimaSucursalConsultada;
  bool conDescuento = false;
  bool respuestaStripeInvalida = false;
  List<Map<String, dynamic>> direcciones = [];

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
        'error': {'code': 'x', 'message': 'No hay stock para esa cantidad.'},
      }, falla);
    }

    if (options.method == 'PUT' &&
        options.path.startsWith('/commerce/cart/items/')) {
      cantidad = (options.data as Map)['quantity'] as int;
    }
    if (options.method == 'DELETE' &&
        options.path.startsWith('/commerce/cart/items/')) {
      cantidad = 0;
    }
    if (options.method == 'POST' && options.path == '/commerce/orders') {
      // Crear el pedido consume las líneas, igual que el backend real.
      cantidad = 0;
    }
    // El cupón se manda como parámetro del GET del carrito.
    if (options.path == '/commerce/cart') {
      conDescuento = options.queryParameters['coupon_code'] == 'VERANO';
      ultimaSucursalConsultada = options.queryParameters['branch_id'] as String?;
    }

    return _json({
      'success': true,
      'message': '',
      'data': _datoDe(options),
    }, 200);
  }

  Object _datoDe(RequestOptions options) {
    final path = options.path;
    if (path == '/commerce/branches') {
      return [
        {'id': 'b1', 'name': 'Centro', 'address': 'Av Bush'},
        {'id': 'b2', 'name': 'Norte', 'address': 'Av Banzer'},
      ];
    }
    if (path == '/users/me/addresses') {
      if (options.method == 'POST') return _direccion('nueva', false);
      return direcciones;
    }
    if (path.startsWith('/commerce/cart')) return _carrito();
    if (path == '/commerce/orders') {
      return {
        'id': 'o1',
        'number': 'P-001',
        'status': 'pending',
        'total': '150.00',
      };
    }
    if (path.endsWith('/checkout')) {
      if (respuestaStripeInvalida) return {'url': 123, 'status': 'open'};
      return {'url': 'https://stripe.test/sesion', 'status': 'open'};
    }
    return const <String, dynamic>{};
  }

  int _disponibleDe(String? sucursal) {
    if (disponiblePorSucursal.isEmpty) return disponible;
    return disponiblePorSucursal[sucursal] ?? 0;
  }

  Map<String, dynamic> _carrito() => {
    'items': cantidad == 0
        ? []
        : [
            {
              'variant_id': 'v1',
              'product_id': 'p1',
              'name': 'Polera POLO',
              'sku': 'SKU-1',
              'size': 'M',
              'color': 'Azul',
              'unit_price': '75.00',
              'quantity': cantidad,
              'available': _disponibleDe(ultimaSucursalConsultada),
              'line_total': '${75 * cantidad}.00',
            },
          ],
    'subtotal': '${75 * cantidad}.00',
    'discount_total': conDescuento ? '15.00' : '0',
    'discounts': conDescuento
        ? [
            {
              'promotion_id': 'pr1',
              'name': 'Verano 20%',
              'code': 'VERANO',
              'type': 'percent',
              'amount': '15.00',
            },
          ]
        : [],
    'total': '${75 * cantidad - (conDescuento ? 15 : 0)}.00',
    'currency': 'BOB',
  };

  static Map<String, dynamic> _direccion(String id, bool predeterminada) => {
    'id': id,
    'label': 'Casa',
    'recipient_name': 'Ana Vargas',
    'phone': '77712345',
    'address_line': 'Calle Falsa 123',
    'city': 'Santa Cruz',
    'postal_code': null,
    'country': 'BO',
    'is_default': predeterminada,
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
  late CommerceApi comercio;

  CarritoController construir() {
    servidor = _ServidorFalso();
    final dio = Dio(
      BaseOptions(
        baseUrl: 'http://test/api/v1',
        validateStatus: (s) => s != null && s < 400,
      ),
    );
    dio.httpClientAdapter = servidor;
    final cliente = ApiClient(dio: dio);
    comercio = CommerceApi(cliente);
    return CarritoController(comercio, DireccionesApi(cliente));
  }

  /// Entrega mínima válida, para no repetirla en cada prueba de compra.
  void completarEntrega(CarritoController control) => control.escribirEntrega(
    const FormularioEntrega(
      destinatario: 'Ana Vargas',
      telefono: '77712345',
      linea: 'Calle Falsa 123',
      ciudad: 'Santa Cruz',
    ),
  );

  group('carga', () {
    test('trae sucursales y carrito, y elige la primera sucursal', () async {
      final control = construir();

      await control.cargar();

      expect(control.state.cargando, isFalse);
      expect(control.state.sucursales, hasLength(2));
      expect(control.state.sucursalId, 'b1');
      expect(control.state.items, hasLength(1));
    });

    test('preselecciona la dirección predeterminada del perfil', () async {
      final control = construir();
      servidor.direcciones = [
        _ServidorFalso._direccion('d1', false),
        _ServidorFalso._direccion('d2', true),
      ];

      await control.cargar();

      // La predeterminada, no la primera de la lista.
      expect(control.state.direccionGuardadaId, 'd2');
      expect(control.state.entrega.destinatario, 'Ana Vargas');
      expect(control.state.entrega.completo, isTrue);
    });

    test('sin direcciones guardadas el formulario queda vacío', () async {
      final control = construir();

      await control.cargar();

      expect(control.state.direccionGuardadaId, '');
      expect(control.state.entrega.completo, isFalse);
    });
  });

  group('líneas', () {
    test(
      'cambiar la cantidad la manda al backend y relee el carrito',
      () async {
        final control = construir();
        await control.cargar();

        await control.cambiarCantidad(control.state.items.first, 4);

        expect(servidor.pedidos, contains('PUT /commerce/cart/items/v1'));
        expect(control.state.items.first.quantity, 4);
        expect(control.state.carrito?.total, 300);
      },
    );

    test('bajar a cero es quitar la línea, no mandar quantity 0', () async {
      final control = construir();
      await control.cargar();

      await control.cambiarCantidad(control.state.items.first, 0);

      expect(servidor.pedidos, contains('DELETE /commerce/cart/items/v1'));
      expect(control.state.vacio, isTrue);
    });

    test('pedir más de lo disponible deja el aviso de sobregiro', () async {
      final control = construir();
      servidor.disponible = 1;
      await control.cargar();

      expect(control.state.haySobregiro, isTrue);
      // Y eso alcanza para bloquear la compra, aunque el resto esté completo.
      completarEntrega(control);
      expect(control.state.sePuedeComprar, isFalse);
    });

    test('un rechazo del backend no borra el carrito de la pantalla', () async {
      final control = construir();
      await control.cargar();
      servidor.fallan['/commerce/cart/items/v1'] = 409;

      await control.cambiarCantidad(control.state.items.first, 9);

      expect(control.state.error, 'No hay stock para esa cantidad.');
      expect(control.state.items, hasLength(1));
      expect(control.state.ocupado, isFalse);
    });
  });

  group('sucursal que cubre el carrito', () {
    test('si la primera no tiene stock, se cambia sola a la que sí', () async {
      final control = construir();
      // «Centro» (b1, la que la app elige sola) no trabaja esta prenda;
      // «Norte» (b2) sí. Antes quedaba en b1 con `available: 0`, el botón de
      // comprar gris y ninguna explicación.
      servidor.disponiblePorSucursal = const {'b1': 0, 'b2': 5};

      await control.cargar();

      expect(control.state.sucursalId, 'b2');
      expect(control.state.haySobregiro, isFalse);
      expect(control.state.ningunaSucursalCubre, isFalse);
      completarEntrega(control);
      expect(control.state.sePuedeComprar, isTrue);
    });

    test('si ninguna cubre, lo dice en vez de dejar todo gris', () async {
      final control = construir();
      servidor.disponiblePorSucursal = const {'b1': 0, 'b2': 0};

      await control.cargar();

      expect(control.state.haySobregiro, isTrue);
      expect(control.state.ningunaSucursalCubre, isTrue);
    });

    test('no le pisa la sucursal a quien la eligió a mano', () async {
      final control = construir();
      servidor.disponiblePorSucursal = const {'b1': 5, 'b2': 0};
      await control.cargar();

      await control.elegirSucursal('b2');
      await control.cargar();

      // Elegida a mano: aunque no tenga stock, se respeta y se muestra el
      // faltante. Moverla sin avisar sería peor que el problema.
      expect(control.state.sucursalId, 'b2');
      expect(control.state.sucursalManual, isTrue);
      expect(control.state.haySobregiro, isTrue);
    });

    test('con stock en la primera no prueba las demás', () async {
      final control = construir();
      servidor.disponiblePorSucursal = const {'b1': 5, 'b2': 5};

      await control.cargar();

      expect(control.state.sucursalId, 'b1');
      // Una sola lectura del carrito: no hay motivo para consultar más.
      expect(
        servidor.pedidos.where((p) => p == 'GET /commerce/cart'),
        hasLength(1),
      );
    });
  });

  group('sucursal', () {
    test('cambiarla relee el carrito contra la nueva', () async {
      final control = construir();
      await control.cargar();
      servidor.pedidos.clear();

      await control.elegirSucursal('b2');

      expect(control.state.sucursalId, 'b2');
      expect(servidor.pedidos, contains('GET /commerce/cart'));
    });
  });

  group('cupón', () {
    test('un cupón que aplica deja el nombre de la promoción', () async {
      final control = construir();
      await control.cargar();

      control.escribirCupon('VERANO');
      await control.aplicarCupon();

      expect(control.state.mensajeCupon, 'Verano 20%');
      expect(control.state.errorCupon, isNull);
      expect(control.state.carrito?.discountTotal, 15);
    });

    test(
      'un cupón que no aplica se avisa en vez de quedar en silencio',
      () async {
        final control = construir();
        await control.cargar();

        control.escribirCupon('NOEXISTE');
        await control.aplicarCupon();

        expect(control.state.errorCupon, isNotNull);
        expect(control.state.mensajeCupon, isNull);
      },
    );
  });

  group('comprar', () {
    test('no deja confirmar sin datos de entrega', () async {
      final control = construir();
      await control.cargar();

      expect(control.state.sePuedeComprar, isFalse);
      expect(await control.comprar(), isNull);
      expect(servidor.pedidos.contains('POST /commerce/orders'), isFalse);
    });

    test('crea el pedido con sucursal, dirección y método', () async {
      final control = construir();
      await control.cargar();
      completarEntrega(control);

      final resultado = await control.comprar();

      expect(resultado?.pedido.number, 'P-001');
      expect(servidor.pedidos, contains('POST /commerce/orders'));
      final cuerpo = servidor.cuerpos.last;
      expect(cuerpo['branch_id'], 'b1');
      expect(cuerpo['payment_method'], 'manual');
      expect(cuerpo['channel'], 'mobile');
      // El pedido usa `recipient`/`line1`, no los nombres del perfil.
      expect((cuerpo['address'] as Map)['recipient'], 'Ana Vargas');
      expect((cuerpo['address'] as Map)['line1'], 'Calle Falsa 123');
    });

    test('con método manual no pide la sesión de Stripe', () async {
      final control = construir();
      await control.cargar();
      completarEntrega(control);

      final resultado = await control.comprar();

      expect(resultado?.urlPago, isNull);
      expect(servidor.pedidos.any((p) => p.endsWith('/checkout')), isFalse);
    });

    test('con Stripe devuelve la URL para abrir el navegador', () async {
      final control = construir();
      await control.cargar();
      completarEntrega(control);
      control.elegirMetodoPago('stripe');

      final resultado = await control.comprar();

      expect(servidor.pedidos, contains('POST /commerce/orders/o1/checkout'));
      expect(resultado?.urlPago, 'https://stripe.test/sesion');
    });

    test(
      'si Stripe falla conserva el pedido pendiente para reintentar',
      () async {
        final control = construir();
        await control.cargar();
        completarEntrega(control);
        control.elegirMetodoPago('stripe');
        servidor.fallan['/commerce/orders/o1/checkout'] = 502;

        final resultado = await control.comprar();

        expect(resultado?.pedido.number, 'P-001');
        expect(resultado?.urlPago, isNull);
        expect(resultado?.errorPago, isNotNull);
        expect(control.state.vacio, isTrue);
        expect(control.state.ocupado, isFalse);
      },
    );

    test(
      'una respuesta Stripe inesperada no deja la compra bloqueada',
      () async {
        final control = construir();
        servidor.respuestaStripeInvalida = true;
        await control.cargar();
        completarEntrega(control);
        control.elegirMetodoPago('stripe');

        final resultado = await control.comprar();

        expect(resultado?.pedido.id, 'o1');
        expect(resultado?.errorPago, isNotNull);
        expect(control.state.ultimoPedido?.id, 'o1');
        expect(control.state.ocupado, isFalse);
      },
    );

    test(
      'guarda la dirección en el perfil solo si se pidió y es nueva',
      () async {
        final control = construir();
        await control.cargar();
        completarEntrega(control);
        control.alternarGuardarEnPerfil(true);

        await control.comprar();

        expect(servidor.pedidos, contains('POST /users/me/addresses'));
      },
    );

    test('con una dirección guardada elegida no la vuelve a guardar', () async {
      final control = construir();
      servidor.direcciones = [_ServidorFalso._direccion('d1', true)];
      await control.cargar();
      control.alternarGuardarEnPerfil(true);

      await control.comprar();

      expect(
        servidor.pedidos.where((p) => p == 'POST /users/me/addresses'),
        isEmpty,
      );
    });

    test(
      'si el pedido falla, el mensaje queda y no se vacía el carrito',
      () async {
        final control = construir();
        await control.cargar();
        completarEntrega(control);
        servidor.fallan['/commerce/orders'] = 409;

        final resultado = await control.comprar();

        expect(resultado, isNull);
        expect(control.state.error, isNotNull);
        expect(control.state.vacio, isFalse);
        expect(control.state.ocupado, isFalse);
      },
    );

    test('un pedido exitoso deja el carrito vacío', () async {
      final control = construir();
      await control.cargar();
      completarEntrega(control);

      await control.comprar();

      // El backend ya lo vació; la pantalla no puede seguir mostrando líneas.
      expect(control.state.vacio, isTrue);
      expect(control.state.ultimoPedido?.number, 'P-001');
    });

    test('permite un segundo pedido después de agregar otra prenda', () async {
      final control = construir();
      await control.cargar();
      completarEntrega(control);
      control.elegirMetodoPago('stripe');

      expect(await control.comprar(), isNotNull);
      expect(control.state.vacio, isTrue);
      expect(servidor.cantidad, 0);

      await comercio.agregarUno('v1');
      await control.cargar();

      expect(control.state.items.single.quantity, 1);
      expect(control.state.ultimoPedido, isNull);
      expect(control.state.sePuedeComprar, isTrue);
      expect(await control.comprar(), isNotNull);
      expect(
        servidor.pedidos.where((p) => p == 'POST /commerce/orders'),
        hasLength(2),
      );
      expect(control.state.ocupado, isFalse);
    });
  });
}
