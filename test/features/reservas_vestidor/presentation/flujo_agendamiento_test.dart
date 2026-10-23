import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_marketplace_moda/app/theme.dart';
import 'package:mobile_marketplace_moda/core/network/api_client.dart';
import 'package:mobile_marketplace_moda/features/reservas_vestidor/application/reservas_controller.dart';
import 'package:mobile_marketplace_moda/features/reservas_vestidor/domain/reserva.dart';
import 'package:mobile_marketplace_moda/features/reservas_vestidor/presentation/nueva_reserva_screen.dart';
import 'package:mobile_marketplace_moda/features/usuarios_catalogo/application/prenda_controller.dart';
import 'package:mobile_marketplace_moda/features/usuarios_catalogo/application/session_controller.dart';
import 'package:mobile_marketplace_moda/features/usuarios_catalogo/presentation/catalog_screen.dart';
import 'package:mobile_marketplace_moda/features/usuarios_catalogo/presentation/prenda_screen.dart';

import '../../../support/backend_falso.dart';

void main() {
  testWidgets('suma otra talla desde el catálogo y conserva el agendamiento', (
    tester,
  ) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => '.',
        );
    final backend = BackendFalso();
    final dio = Dio(
      BaseOptions(
        baseUrl: 'http://test/api/v1',
        validateStatus: (status) => status != null && status < 400,
      ),
    );
    dio.httpClientAdapter = backend;
    final contenedor = ProviderContainer(
      overrides: [
        apiClientProvider.overrideWithValue(ApiClient(dio: dio)),
        tokenStoreProvider.overrideWithValue(TokenStoreFalso()),
      ],
    );
    addTearDown(contenedor.dispose);

    await tester.runAsync(
      () => contenedor
          .read(sessionProvider.notifier)
          .iniciarSesion('ana@test.com', 'x'),
    );

    final seleccion = contenedor.read(nuevaReservaProvider.notifier);
    seleccion.agregar(
      const ItemReserva(
        variantId: 'v1',
        cantidad: 1,
        producto: 'Vestido midi',
        talla: 'S',
        color: 'Mostaza',
      ),
    );
    seleccion.elegirFecha(DateTime.now().add(const Duration(days: 1)));
    seleccion.escribirNotas('Voy con mi hermana');

    final router = GoRouter(
      initialLocation: '/reservar',
      routes: [
        GoRoute(
          path: '/reservar',
          builder: (context, state) => const NuevaReservaScreen(),
        ),
        GoRoute(
          path: '/elegir-prendas',
          builder: (context, state) => const CatalogScreen(paraReserva: true),
        ),
        GoRoute(
          path: '/prendas/:slug',
          builder: (context, state) => PrendaScreen(
            slug: state.pathParameters['slug']!,
            paraReserva: state.uri.queryParameters['paraReserva'] == '1',
          ),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: contenedor,
        child: MaterialApp.router(theme: AppTheme.claro, routerConfig: router),
      ),
    );
    await asentar(tester);

    expect(find.text('Agregar más prendas'), findsOneWidget);
    await tester.tap(find.text('Agregar más prendas'));
    await asentar(tester);
    await tester.pumpAndSettle();
    expect(find.text('Elegir prendas'), findsOneWidget);
    expect(find.text('Volver al agendamiento (1)'), findsOneWidget);

    final tarjeta = find
        .descendant(
          of: find.byType(CatalogScreen),
          matching: find.text('Vestido midi'),
        )
        .first;
    await tester.ensureVisible(tarjeta);
    await tester.pumpAndSettle();
    await tester.tap(tarjeta);
    await asentar(tester);
    await tester.pumpAndSettle();
    await tester.drag(
      find
          .descendant(
            of: find.byType(PrendaScreen),
            matching: find.byType(ListView),
          )
          .first,
      const Offset(0, -450),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mediano'));
    await tester.pump();
    expect(contenedor.read(prendaProvider('vestido-midi-01')).talla, 'Mediano');
    await tester.tap(find.text('Negro'));
    await tester.pump();
    expect(
      contenedor.read(prendaProvider('vestido-midi-01')).variante?.id,
      'v2',
    );
    await tester.tap(find.text('Reservar para probarme en sucursal'));
    await asentar(tester);

    expect(find.text('Elegir prendas'), findsOneWidget);
    expect(find.text('Volver al agendamiento (2)'), findsOneWidget);
    expect(
      contenedor.read(nuevaReservaProvider).items.map((e) => e.variantId),
      containsAll(['v1', 'v2']),
    );

    await tester.tap(find.text('Volver al agendamiento (2)'));
    await asentar(tester);
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.path, '/reservar');
    expect(find.text('Agregar más prendas'), findsOneWidget);
    expect(contenedor.read(nuevaReservaProvider).fecha, isNotNull);
    expect(contenedor.read(nuevaReservaProvider).notas, 'Voy con mi hermana');
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'Voy con mi hermana',
    );
    expect(tester.takeException(), isNull);
    // El caché de las fotos agenda una limpieza única; dejarla terminar.
    await tester.pump(const Duration(seconds: 11));
  });
}
