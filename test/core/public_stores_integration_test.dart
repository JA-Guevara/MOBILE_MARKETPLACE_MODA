import 'dart:io';
import 'dart:typed_data';
import 'package:dio/dio.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_marketplace_moda/features/usuarios_catalogo/application/session_controller.dart';
import 'package:mobile_marketplace_moda/features/usuarios_catalogo/infrastructure/catalog_api.dart';

import '../support/backend_falso.dart';

class _Recorder extends BackendFalso {
  final requests = <RequestOptions>[];
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    requests.add(options);
    return super.fetch(options, requestStream, cancelFuture);
  }
}

class _RealHttp extends HttpOverrides {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'la selección pública cambia el catálogo y no se filtra al directorio',
    () async {
      final container = ProviderContainer(
        overrides: [tokenStoreProvider.overrideWithValue(TokenStoreFalso())],
      );
      final client = container.read(apiClientProvider);
      final backend = _Recorder();
      client.dio.httpClientAdapter = backend;
      try {
        for (final slug in ['tienda-a', 'tienda-b']) {
          container.read(tiendaPublicaSeleccionadaProvider.notifier).state = (
            slug: slug,
            nombre: slug,
          );
          await client.get<Map<String, dynamic>>('/catalog/products');
          expect(backend.requests.last.headers['X-Tenant-Slug'], slug);
          expect(backend.requests.last.headers['Authorization'], isNull);
        }
        await client.get<Map<String, dynamic>>('/public/stores');
        expect(backend.requests.last.headers['X-Tenant-Slug'], isNull);
        await client.post<dynamic>('/auth/register', body: {});
        expect(backend.requests.last.headers['X-Tenant-Slug'], 'tienda-b');
      } finally {
        client.dio.close(force: true);
        container.dispose();
      }
    },
  );

  test(
    'iniciar sesión enlaza el token y la empresa sin volver a crear el cliente',
    () async {
      final container = ProviderContainer(
        overrides: [tokenStoreProvider.overrideWithValue(TokenStoreFalso())],
      );
      final client = container.read(apiClientProvider);
      final backend = _Recorder();
      client.dio.httpClientAdapter = backend;
      try {
        final session = container.read(sessionProvider.notifier);
        await session.iniciarSesion(
          'ana@test.com',
          'solo-fixture',
          empresaSlug: 'tienda-a',
        );
        container.read(tiendaPublicaSeleccionadaProvider.notifier).state = (
          slug: 'tienda-b',
          nombre: 'B',
        );
        await client.get<Map<String, dynamic>>('/catalog/products');
        final request = backend.requests.lastWhere(
          (r) => r.path == '/catalog/products',
        );
        expect(request.headers['Authorization'], 'Bearer token-de-prueba');
        expect(request.headers['X-Tenant-Slug'], 'tienda-a');
        expect(container.read(apiClientProvider), same(client));
        await session.limpiar();
        await client.get<Map<String, dynamic>>('/public/stores');
        expect(backend.requests.last.headers['Authorization'], isNull);
      } finally {
        client.dio.close(force: true);
        container.dispose();
      }
    },
  );

  test(
    'el directorio usa los interceptores reales sin una sesión iniciada',
    () async {
      final container = ProviderContainer(
        overrides: [tokenStoreProvider.overrideWithValue(TokenStoreFalso())],
      );
      final client = container.read(apiClientProvider);
      final backend = BackendFalso();
      client.dio.httpClientAdapter = backend;
      Object? transportError;
      client.dio.interceptors.add(
        InterceptorsWrapper(
          onError: (error, handler) {
            transportError = error.error;
            handler.next(error);
          },
        ),
      );
      try {
        final stores = await container.read(tiendasPublicasProvider.future);
        expect(stores.single.slug, 'tienda-a');
      } catch (error) {
        fail(
          'Error original del transporte: $transportError; peticiones recibidas: ${backend.pedidos}; $error',
        );
      } finally {
        client.dio.close(force: true);
        container.dispose();
      }
    },
  );

  test('humo de solo lectura del directorio real', () async {
    await HttpOverrides.runWithHttpOverrides(() async {
      final container = ProviderContainer(
        overrides: [tokenStoreProvider.overrideWithValue(TokenStoreFalso())],
      );
      try {
        final stores = await container
            .read(tiendasPublicasProvider.future)
            .timeout(const Duration(seconds: 45));
        expect(
          stores.every(
            (store) => store.slug.isNotEmpty && store.nombre.isNotEmpty,
          ),
          isTrue,
        );
        if (stores.isNotEmpty) {
          container.read(tiendaPublicaSeleccionadaProvider.notifier).state =
              stores.first;
          final catalog = CatalogApi(container.read(apiClientProvider));
          final products = await catalog.productos(pageSize: 1);
          await catalog.referencias('categories');
          await catalog.recomendaciones();
          // ignore: avoid_print
          print('PUBLIC_CATALOG_LIVE_OK parsed=${products.items.length}');
        }
        // No imprime cuentas, datos privados ni credenciales.
        // ignore: avoid_print
        print('PUBLIC_STORES_LIVE_OK count=${stores.length}');
      } finally {
        container.read(apiClientProvider).dio.close(force: true);
        container.dispose();
      }
    }, _RealHttp());
  }, skip: !const bool.fromEnvironment('RUN_PUBLIC_API_SMOKE'));
}
