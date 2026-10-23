import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_marketplace_moda/app/theme.dart';
import 'package:mobile_marketplace_moda/core/network/api_client.dart';
import 'package:mobile_marketplace_moda/core/storage/token_store.dart';
import 'package:mobile_marketplace_moda/features/usuarios_catalogo/application/session_controller.dart';

/// Backend falso con respuestas realistas para **todos** los endpoints que
/// consume el cliente.
///
/// Sirve para montar cada pantalla entera y ver si se dibuja. Los tests de
/// controlador prueban la lógica; estos prueban que la vista no reviente al
/// construirse, que es lo que un `flutter analyze` limpio no garantiza.
class BackendFalso implements HttpClientAdapter {
  final List<String> pedidos = [];

  /// Rutas que deben contestar con error, con el estado a devolver.
  final Map<String, int> fallan = {};

  /// Devolver listas vacías, para probar los estados «sin nada todavía».
  bool vacio = false;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    pedidos.add('${options.method} ${options.path}');
    final falla = fallan[options.path];
    if (falla != null) {
      return _json({
        'success': false,
        'error': {'code': 'x', 'message': 'No se pudo completar la operación.'},
      }, falla);
    }
    return _json(
      {'success': true, 'message': 'ok', 'data': _datoDe(options)},
      200,
    );
  }

  Object _datoDe(RequestOptions options) {
    final path = options.path;

    if (path == '/auth/login' || path == '/auth/refresh') {
      return {
        'access_token': 'token-de-prueba',
        'refresh_token': 'refresh-de-prueba',
        'token_type': 'bearer',
        'expires_in': 3600,
        'user': usuario,
      };
    }
    if (path == '/auth/me') return usuario;

    if (path == '/catalog/products') {
      return {
        'items': vacio ? [] : [prenda],
        'total': vacio ? 0 : 1,
        'page': 1,
        'page_size': 12,
        'pages': 1,
      };
    }
    if (path.startsWith('/catalog/products/')) return prenda;
    if (path.startsWith('/catalog/')) {
      return vacio ? [] : [
        {'id': 'c1', 'name': 'Vestidos'},
        {'id': 'c2', 'name': 'Poleras'},
      ];
    }

    if (path == '/commerce/recommendations') return vacio ? [] : [recomendado];
    if (path == '/commerce/branches') {
      return vacio ? [] : [
        {'id': 'b1', 'name': 'Centro', 'address': 'Av Bush'},
        {'id': 'b2', 'name': 'Norte', 'address': 'Av Banzer'},
      ];
    }
    if (path.startsWith('/commerce/favorites/')) {
      return {'is_favorite': false, 'stock_alert': true, 'price_alert': true};
    }
    if (path == '/commerce/favorites') return vacio ? [] : [favorito];
    if (path.startsWith('/commerce/cart')) return vacio ? carritoVacio : carrito;
    if (path == '/commerce/orders') {
      return options.method == 'POST'
          ? pedido
          : (vacio ? [] : [pedido]);
    }
    if (path.endsWith('/returns') && options.method == 'GET') {
      return {
        'can_request': true,
        'reason': null,
        'units': {'v1': 1},
        'returns': [],
      };
    }
    if (path.startsWith('/commerce/orders/')) return pedido;

    if (path == '/users/me/addresses') return vacio ? [] : [direccion];
    if (path.startsWith('/users/me/addresses/')) return direccion;

    if (path == '/reservations/availability') {
      return [
        {
          'variant_id': 'v1',
          'available': true,
          'quantity': 5,
          'requested': 1,
          'product': 'Vestido midi',
          'size': 'S',
          'color': 'Mostaza',
          'reason': null,
        },
      ];
    }
    if (path == '/reservations' && options.method == 'GET') {
      return {
        'items': vacio ? [] : [reserva],
        'total': vacio ? 0 : 1,
        'page': 1,
        'page_size': 20,
        'pages': 1,
      };
    }
    if (path.startsWith('/reservations')) return reserva;

    return const <String, dynamic>{};
  }

  static ResponseBody _json(Object cuerpo, int estado) => ResponseBody.fromString(
        jsonEncode(cuerpo),
        estado,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );

  @override
  void close({bool force = false}) {}

  // --- Datos, calcados de lo que responde el backend real ---

  static const usuario = {
    'id': 'u1',
    'email': 'ana@test.com',
    'first_name': 'Ana',
    'last_name': 'Vargas',
    'phone': '77712345',
    'is_active': true,
    'is_verified': true,
    'roles': [],
  };

  static const prenda = {
    'id': 'p1',
    'name': 'Vestido midi',
    'slug': 'vestido-midi-01',
    'description': 'Vestido midi de viscosa.',
    'brand': 'FashionStore',
    'gender': 'mujer',
    'base_price': '420.00',
    'is_featured': true,
    'category': {'id': 'c1', 'name': 'Vestidos'},
    'season': {'id': 's1', 'name': 'verano'},
    'collection': {'id': 'k1', 'name': 'Casual'},
    'images': [
      {'url': 'https://x/uno.jpg', 'is_primary': true},
      {'url': 'https://x/dos.jpg', 'is_primary': false},
    ],
    'variants': [
      {
        'id': 'v1',
        'sku': 'VM-S-MOS',
        'price_override': null,
        'is_active': true,
        'size': {'code': 'S', 'name': 'Pequeño'},
        'color': {'name': 'Mostaza', 'hex_code': '#C08A22'},
      },
      {
        'id': 'v2',
        'sku': 'VM-M-NEG',
        'price_override': '399.00',
        'is_active': true,
        'size': {'code': 'M', 'name': 'Mediano'},
        'color': {'name': 'Negro', 'hex_code': '#111111'},
      },
    ],
  };

  static const recomendado = {
    'id': 'p2',
    'name': 'Blusa de seda',
    'slug': 'blusa-de-seda-01',
    'base_price': '260.00',
    'category': 'Blusas',
    'image_url': 'https://x/blusa.jpg',
  };

  static const carrito = {
    'items': [
      {
        'variant_id': 'v1',
        'product_id': 'p1',
        'name': 'Vestido midi',
        'sku': 'VM-S-MOS',
        'size': 'S',
        'color': 'Mostaza',
        'image_url': 'https://x/uno.jpg',
        'unit_price': '420.00',
        'quantity': 2,
        'available': 5,
        'line_total': '840.00',
      },
    ],
    'subtotal': '840.00',
    'discount_total': '40.00',
    'discounts': [
      {
        'promotion_id': 'pr1',
        'name': 'Verano 10%',
        'code': 'VERANO',
        'type': 'percent',
        'amount': '40.00',
      },
    ],
    'coupon_code': 'VERANO',
    'total': '800.00',
    'currency': 'BOB',
  };

  static const carritoVacio = {
    'items': [],
    'subtotal': '0',
    'discount_total': '0',
    'discounts': [],
    'total': '0',
    'currency': 'BOB',
  };

  static const pedido = {
    'id': 'o1',
    'number': 'P-000123',
    'customer_email': 'ana@test.com',
    'branch_id': 'b1',
    'status': 'delivered',
    'payment_status': 'paid',
    'payment_method': 'manual',
    'subtotal': '840.00',
    'discount_total': '40.00',
    'discounts': [],
    'total': '800.00',
    'currency': 'BOB',
    'created_at': '2026-09-20T10:00:00Z',
    'carrier': 'Servicio propio',
    'tracking_number': 'TR-9',
    'has_open_return': false,
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
        'name': 'Vestido midi',
        'sku': 'VM-S-MOS',
        'size': 'S',
        'color': 'Mostaza',
        'unit_price': '420.00',
        'quantity': 2,
        'available': 5,
        'line_total': '840.00',
      },
    ],
    'tracking': [
      {'status': 'pending_payment', 'note': '', 'date': '2026-09-20T10:00:00Z'},
      {'status': 'paid', 'note': 'Pago confirmado', 'date': '2026-09-20T11:00:00Z'},
      {'status': 'delivered', 'note': 'Entregado', 'date': '2026-09-21T16:00:00Z'},
    ],
  };

  static const favorito = {
    'id': 'f1',
    'product_id': 'p1',
    'slug': 'vestido-midi-01',
    'name': 'Vestido midi',
    'base_price': '420.00',
    'stock_alert': true,
    'price_alert': false,
    'image_url': 'https://x/uno.jpg',
  };

  static const direccion = {
    'id': 'd1',
    'label': 'Casa',
    'recipient_name': 'Ana Vargas',
    'phone': '77712345',
    'address_line': 'Calle Falsa 123',
    'city': 'Santa Cruz',
    'postal_code': null,
    'country': 'BO',
    'is_default': true,
  };

  static const reserva = {
    'id': 'rs1',
    'user_id': 'u1',
    'branch_id': 'b1',
    'branch_name': 'Centro',
    'status': 'pending',
    'scheduled_at': '2026-10-01T15:00:00Z',
    'notes': 'Paso después del trabajo',
    'items': [
      {'variant_id': 'v1', 'quantity': 2, 'product': 'Vestido midi', 'size': 'S'},
    ],
    'tracking': [
      {'status': 'pending', 'note': '', 'date': '2026-09-21T10:00:00Z'},
    ],
    'created_at': '2026-09-21T10:00:00Z',
  };
}

/// `TokenStore` sin Keystore: en un test no hay canal de plataforma.
class TokenStoreFalso extends TokenStore {
  TokenStoreFalso({this.refresh});

  String? refresh;

  @override
  Future<String?> leerRefresh() async => refresh;

  @override
  Future<void> guardarRefresh(String token) async => refresh = token;

  @override
  Future<void> limpiar() async => refresh = null;
}

/// Monta una pantalla con el backend falso enchufado.
///
/// Devuelve el contenedor para poder leer o empujar estado desde el test.
Future<ProviderContainer> montarPantalla(
  WidgetTester tester,
  Widget pantalla, {
  required BackendFalso backend,
  bool conSesion = true,
}) async {
  // `cached_network_image` guarda en disco y pide el directorio al sistema;
  // sin este stub cada pantalla con fotos falla por el canal ausente.
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/path_provider'),
    (call) async => '.',
  );

  final dio = Dio(BaseOptions(
    baseUrl: 'http://test/api/v1',
    validateStatus: (s) => s != null && s < 400,
  ));
  dio.httpClientAdapter = backend;

  final contenedor = ProviderContainer(overrides: [
    apiClientProvider.overrideWithValue(ApiClient(dio: dio)),
    tokenStoreProvider.overrideWithValue(TokenStoreFalso()),
  ]);
  addTearDown(contenedor.dispose);

  // `testWidgets` corre en una zona de tiempo simulado: un `await` sobre una
  // petición de verdad —aunque el adaptador sea falso— nunca vuelve, porque
  // nadie avanza el reloj. `runAsync` la ejecuta en la zona real.
  if (conSesion) {
    await tester.runAsync(
      () => contenedor.read(sessionProvider.notifier).iniciarSesion('ana@test.com', 'x'),
    );
  }

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: contenedor,
      child: MaterialApp(theme: AppTheme.claro, home: pantalla),
    ),
  );

  // Las pantallas piden sus datos en `initState`; hay que dejarlas terminar
  // en la zona real antes de volver a dibujar.
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  return contenedor;
}

/// Deja correr las peticiones pendientes y vuelve a dibujar.
///
/// Se usa después de tocar un botón que llama al backend, por el mismo motivo
/// que [montarPantalla] usa `runAsync`.
Future<void> asentar(WidgetTester tester) async {
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}
