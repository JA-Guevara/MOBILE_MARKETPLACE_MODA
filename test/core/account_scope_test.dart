import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_marketplace_moda/features/reservas_vestidor/application/reservas_controller.dart';
import 'package:mobile_marketplace_moda/features/usuarios_catalogo/application/direcciones_controller.dart';
import 'package:mobile_marketplace_moda/features/usuarios_catalogo/application/session_controller.dart';
import 'package:mobile_marketplace_moda/features/ventas_pagos/application/carrito_controller.dart';
import 'package:mobile_marketplace_moda/features/ventas_pagos/application/favoritos_controller.dart';
import 'package:mobile_marketplace_moda/features/ventas_pagos/application/pedidos_controller.dart';
import '../support/backend_falso.dart';

class _AccountsBackend extends BackendFalso {
  bool pauseFavorites = false;
  bool pauseCheckout = false;
  bool pauseRefresh = false;
  String activeTenant = 'tienda-a';
  final started = Completer<void>();
  final release = Completer<void>();

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? stream,
    Future<void>? cancel,
  ) async {
    if (options.path == '/auth/login' || options.path == '/auth/refresh') {
      if (pauseRefresh && options.path == '/auth/refresh') {
        if (!started.isCompleted) started.complete();
        await release.future;
      }
      final slug = (options.data as Map)['tenant_slug'] ?? activeTenant;
      activeTenant = slug as String;
      return ResponseBody.fromString(
        jsonEncode({
          'data': {
            'access_token': 'fixture-access',
            'refresh_token': 'fixture-refresh',
            'user': {
              ...BackendFalso.usuario,
              'tenant': {
                'id': slug,
                'slug': slug,
                'trade_name': slug,
                'status': 'ACTIVA',
              },
            },
          },
        }),
        200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
    }
    if (pauseFavorites && options.path == '/commerce/favorites') {
      if (!started.isCompleted) started.complete();
      await release.future;
    }
    if (pauseCheckout && options.path.endsWith('/checkout')) {
      if (!started.isCompleted) started.complete();
      await release.future;
      return ResponseBody.fromString(
        jsonEncode({
          'data': {
            'url': 'https://checkout.stripe.com/c/pay_fixture',
            'status': 'open',
          },
        }),
        200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
    }
    return super.fetch(options, stream, cancel);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'un refresh tardío no restaura una sesión cerrada ni sus credenciales',
    () async {
      final tokens = TokenStoreFalso();
      final container = ProviderContainer(
        overrides: [tokenStoreProvider.overrideWithValue(tokens)],
      );
      final client = container.read(apiClientProvider);
      final backend = _AccountsBackend()..pauseRefresh = true;
      client.dio.httpClientAdapter = backend;
      try {
        final session = container.read(sessionProvider.notifier);
        await session.iniciarSesion(
          'fixture@example.test',
          'fixture',
          empresaSlug: 'tienda-a',
        );
        final pending = session.renovar();
        await backend.started.future;
        await session.limpiar();
        backend.release.complete();
        expect(await pending, isFalse);
        expect(container.read(sessionProvider).usuario, isNull);
        expect(session.accessToken, isNull);
        expect(await tokens.leerRefresh(), isNull);
      } finally {
        client.dio.close(force: true);
        container.dispose();
      }
    },
  );

  test(
    'la misma cuenta cambia de empresa sin conservar carrito, favoritos, pedidos o selección',
    () async {
      final container = ProviderContainer(
        overrides: [tokenStoreProvider.overrideWithValue(TokenStoreFalso())],
      );
      final client = container.read(apiClientProvider);
      client.dio.httpClientAdapter = _AccountsBackend();
      try {
        final session = container.read(sessionProvider.notifier);
        await session.iniciarSesion(
          'fixture@example.test',
          'fixture',
          empresaSlug: 'tienda-a',
        );
        await Future.wait([
          container.read(carritoProvider.notifier).cargar(),
          container.read(favoritosProvider.notifier).cargar(),
          container.read(pedidosProvider.notifier).cargar(),
          container.read(reservasProvider.notifier).cargar(),
          container.read(direccionesProvider.notifier).cargar(),
        ]);
        container
            .read(nuevaReservaProvider.notifier)
            .escribirNotas('Nota privada de A');
        expect(container.read(carritoProvider).carrito, isNotNull);
        expect(container.read(favoritosProvider).favoritos, isNotEmpty);
        expect(container.read(pedidosProvider).pedidos, isNotEmpty);
        expect(container.read(reservasProvider).reservas, isNotEmpty);
        expect(container.read(direccionesProvider).direcciones, isNotEmpty);
        final currentCart = container.read(carritoProvider.notifier);
        expect(await session.renovar(), isTrue);
        await container.pump();
        expect(
          container.read(carritoProvider.notifier),
          same(currentCart),
          reason: 'Renovar la misma sesión no borra la compra en preparación.',
        );
        expect(container.read(nuevaReservaProvider).notas, 'Nota privada de A');
        await session.iniciarSesion(
          'fixture@example.test',
          'fixture',
          empresaSlug: 'tienda-b',
        );
        await container.pump();
        expect(container.read(carritoProvider).carrito, isNull);
        expect(container.read(favoritosProvider).favoritos, isEmpty);
        expect(container.read(pedidosProvider).pedidos, isEmpty);
        expect(container.read(reservasProvider).reservas, isEmpty);
        expect(container.read(direccionesProvider).direcciones, isEmpty);
        expect(container.read(nuevaReservaProvider).notas, isEmpty);
      } finally {
        client.dio.close(force: true);
        container.dispose();
      }
    },
  );

  test(
    'una respuesta privada tardía se descarta después de cerrar sesión',
    () async {
      final container = ProviderContainer(
        overrides: [tokenStoreProvider.overrideWithValue(TokenStoreFalso())],
      );
      final client = container.read(apiClientProvider);
      final backend = _AccountsBackend()..pauseFavorites = true;
      client.dio.httpClientAdapter = backend;
      try {
        final session = container.read(sessionProvider.notifier);
        await session.iniciarSesion(
          'fixture@example.test',
          'fixture',
          empresaSlug: 'tienda-a',
        );
        final pending = container.read(favoritosProvider.notifier).cargar();
        await backend.started.future;
        await session.limpiar();
        await container.pump();
        expect(container.read(favoritosProvider).favoritos, isEmpty);
        backend.release.complete();
        await pending;
        expect(container.read(favoritosProvider).favoritos, isEmpty);
      } finally {
        client.dio.close(force: true);
        container.dispose();
      }
    },
  );

  test(
    'un enlace de pago tardío no se entrega a la siguiente sesión',
    () async {
      final container = ProviderContainer(
        overrides: [tokenStoreProvider.overrideWithValue(TokenStoreFalso())],
      );
      final client = container.read(apiClientProvider);
      final backend = _AccountsBackend()..pauseCheckout = true;
      client.dio.httpClientAdapter = backend;
      final subscription = container.listen(pedidoProvider('o1'), (_, _) {});
      try {
        final session = container.read(sessionProvider.notifier);
        await session.iniciarSesion(
          'fixture@example.test',
          'fixture',
          empresaSlug: 'tienda-a',
        );
        final control = container.read(pedidoProvider('o1').notifier);
        await control.cargar('o1');
        final pending = control.reanudarPago();
        await backend.started.future;
        await session.limpiar();
        await container.pump();
        backend.release.complete();
        expect(await pending, isNull);
      } finally {
        subscription.close();
        client.dio.close(force: true);
        container.dispose();
      }
    },
  );
}
