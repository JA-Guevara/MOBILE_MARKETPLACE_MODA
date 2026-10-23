import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_marketplace_moda/core/network/api_client.dart';
import 'package:mobile_marketplace_moda/features/usuarios_catalogo/application/prenda_controller.dart';
import 'package:mobile_marketplace_moda/features/usuarios_catalogo/infrastructure/catalog_api.dart';
import 'package:mobile_marketplace_moda/features/ventas_pagos/infrastructure/commerce_api.dart';

/// Backend falso: responde por ruta y anota qué se le pidió.
class _ServidorFalso implements HttpClientAdapter {
  final List<String> pedidos = [];

  /// Rutas que deben contestar con error, con el estado a devolver.
  final Map<String, int> fallan = {};
  final Set<String> malformadas = {};

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    pedidos.add('${options.method} ${options.path}');

    final falla = fallan[options.path];
    if (falla != null) {
      return ResponseBody.fromString(
        jsonEncode({
          'success': false,
          'error': {'code': 'x', 'message': 'No hay stock de esa talla.'},
        }),
        falla,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
    }

    if (malformadas.contains(options.path)) {
      return ResponseBody.fromString(
        jsonEncode({'success': true, 'data': []}),
        200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
    }

    return ResponseBody.fromString(
      jsonEncode({
        'success': true,
        'message': '',
        'data': _datoDe(options.path),
      }),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  static Object _datoDe(String path) {
    if (path.startsWith('/catalog/products/')) return _prenda;
    if (path.startsWith('/commerce/favorites/')) {
      return {'is_favorite': false, 'stock_alert': true, 'price_alert': true};
    }
    if (path.startsWith('/commerce/cart')) {
      return {'items': [], 'subtotal': '0', 'total': '0'};
    }
    return const <String, dynamic>{};
  }

  @override
  void close({bool force = false}) {}
}

const _prenda = {
  'id': 'p1',
  'name': 'Polera POLO',
  'slug': 'polera-polo',
  'base_price': '200.00',
  'category': {'name': 'Poleras'},
  'images': [
    {'url': 'https://x/a.jpg', 'is_primary': true},
    {'url': 'https://x/b.jpg'},
  ],
  'variants': [
    {
      'id': 'v1',
      'sku': 'SKU-1',
      'is_active': true,
      'size': {'code': 'XS', 'name': 'Extra pequeño'},
      'color': {'name': 'Azul', 'hex_code': '#1E2A44'},
    },
    {
      'id': 'v2',
      'sku': 'SKU-2',
      'price_override': '150.00',
      'is_active': true,
      'size': {'code': 'M', 'name': 'Mediano'},
      'color': {'name': 'Rojo', 'hex_code': '#AA0000'},
    },
  ],
};

void main() {
  late _ServidorFalso servidor;

  PrendaController construir({
    bool conSesion = true,
    Future<void> Function()? alActualizarCarrito,
  }) {
    servidor = _ServidorFalso();
    final dio = Dio(
      BaseOptions(
        baseUrl: 'http://test/api/v1',
        validateStatus: (s) => s != null && s < 400,
      ),
    );
    dio.httpClientAdapter = servidor;
    final cliente = ApiClient(dio: dio);
    return PrendaController(
      catalogo: CatalogApi(cliente),
      comercio: CommerceApi(cliente),
      haySesion: () => conSesion,
      alActualizarCarrito: alActualizarCarrito,
    );
  }

  group('carga', () {
    test(
      'trae la prenda y preselecciona la primera variante disponible',
      () async {
        final control = construir();

        await control.cargar('polera-polo');

        expect(control.state.cargando, isFalse);
        expect(control.state.producto?.nombre, 'Polera POLO');
        // Sin preselección la persona vería la prenda sin precio hasta tocar dos
        // chips; el precio es justamente a lo que vino.
        expect(control.state.talla, 'Extra pequeño');
        expect(control.state.color, 'Azul');
        expect(control.state.variante?.id, 'v1');
        expect(control.state.sePuedeComprar, isTrue);
      },
    );

    test('sin sesión no pregunta por el favorito', () async {
      final control = construir(conSesion: false);

      await control.cargar('polera-polo');

      // Preguntar sin token es un 401 asegurado en cada prenda que se abra.
      expect(servidor.pedidos.any((p) => p.contains('/favorites/')), isFalse);
      expect(control.state.favorito, isFalse);
    });

    test('con sesión lee el estado del favorito', () async {
      final control = construir();

      await control.cargar('polera-polo');

      expect(servidor.pedidos, contains('GET /commerce/favorites/p1'));
    });

    test('si la prenda no existe deja el mensaje y no un blanco', () async {
      final control = construir();
      servidor.fallan['/catalog/products/no-existe'] = 404;

      await control.cargar('no-existe');

      expect(control.state.cargando, isFalse);
      expect(control.state.producto, isNull);
      expect(control.state.error, isNotNull);
    });
  });

  group('selección', () {
    test('el precio sigue a la variante elegida', () async {
      final control = construir();
      await control.cargar('polera-polo');

      expect(control.state.precio, 200);

      control.elegirTalla('Mediano');
      control.elegirColor('Rojo');

      expect(control.state.variante?.id, 'v2');
      expect(control.state.precio, 150);
    });

    test('una combinación inexistente no se puede comprar', () async {
      final control = construir();
      await control.cargar('polera-polo');

      control.elegirTalla('Mediano'); // Mediano existe, pero en Rojo.

      expect(control.state.variante, isNull);
      expect(control.state.sePuedeComprar, isFalse);
      // Y el precio vuelve al base, que es lo único cierto en ese momento.
      expect(control.state.precio, 200);
    });

    test('el carrusel da la vuelta en los extremos', () async {
      final control = construir();
      await control.cargar('polera-polo');

      control.verImagen(-1);
      expect(control.state.imagen, 1);

      control.verImagen(2);
      expect(control.state.imagen, 0);
    });
  });

  group('agregar al carrito', () {
    test('avisa a la pestaña de carrito tras confirmar el servidor', () async {
      var actualizaciones = 0;
      final control = construir(
        alActualizarCarrito: () async {
          expect(servidor.pedidos, contains('PUT /commerce/cart/items/v1'));
          actualizaciones++;
        },
      );
      await control.cargar('polera-polo');

      await control.agregarAlCarrito();

      expect(actualizaciones, 1);
      expect(control.state.errorAccion, isNull);
      expect(control.state.ocupado, isFalse);
    });

    test('manda la variante elegida, no la prenda', () async {
      final control = construir();
      await control.cargar('polera-polo');
      control.elegirTalla('Mediano');
      control.elegirColor('Rojo');

      final pudo = await control.agregarAlCarrito();

      expect(pudo, isTrue);
      expect(servidor.pedidos, contains('PUT /commerce/cart/items/v2'));
      expect(control.state.mensaje, isNotNull);
      expect(control.state.ocupado, isFalse);
    });

    test('sin sesión devuelve false y no llama al backend', () async {
      final control = construir(conSesion: false);
      await control.cargar('polera-polo');

      final pudo = await control.agregarAlCarrito();

      expect(pudo, isFalse);
      expect(servidor.pedidos.any((p) => p.contains('/cart/')), isFalse);
    });

    test('un rechazo del backend se muestra sin borrar la prenda', () async {
      final control = construir();
      await control.cargar('polera-polo');
      servidor.fallan['/commerce/cart/items/v1'] = 409;

      await control.agregarAlCarrito();

      expect(control.state.errorAccion, 'No hay stock de esa talla.');
      // La prenda sigue en pantalla: el error es de la acción, no de la carga.
      expect(control.state.producto, isNotNull);
      expect(control.state.error, isNull);
      expect(control.state.ocupado, isFalse);
    });

    test('una respuesta inesperada libera el botón para reintentar', () async {
      final control = construir();
      await control.cargar('polera-polo');
      servidor.malformadas.add('/commerce/cart');

      await control.agregarAlCarrito();

      expect(control.state.ocupado, isFalse);
      expect(control.state.sePuedeComprar, isTrue);
      expect(control.state.errorAccion, contains('Intentá nuevamente'));
    });
  });

  group('favoritos', () {
    test('marcar y desmarcar usan PUT y DELETE', () async {
      final control = construir();
      await control.cargar('polera-polo');

      await control.alternarFavorito();
      expect(control.state.favorito, isTrue);
      expect(servidor.pedidos, contains('PUT /commerce/favorites/p1'));

      await control.alternarFavorito();
      expect(control.state.favorito, isFalse);
      expect(servidor.pedidos, contains('DELETE /commerce/favorites/p1'));
    });

    test(
      'sin sesión devuelve false para que la pantalla mande al login',
      () async {
        final control = construir(conSesion: false);
        await control.cargar('polera-polo');

        expect(await control.alternarFavorito(), isFalse);
      },
    );
  });
}
