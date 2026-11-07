import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_marketplace_moda/features/usuarios_catalogo/presentation/catalog_screen.dart';
import 'package:mobile_marketplace_moda/features/usuarios_catalogo/presentation/login_screen.dart';
import 'package:mobile_marketplace_moda/features/usuarios_catalogo/presentation/register_screen.dart';

import '../../support/backend_falso.dart';

void main() {
  testWidgets(
    'un fallo del directorio informa la causa y permite recuperar la carga',
    (tester) async {
      final backend = BackendFalso()..fallan['/public/stores'] = 503;
      await montarPantalla(
        tester,
        const CatalogScreen(),
        backend: backend,
        conSesion: false,
      );
      expect(find.text('No pudimos cargar las tiendas.'), findsOneWidget);
      expect(find.textContaining('mantenimiento'), findsOneWidget);
      expect(find.text('Abrir modo sin conexión'), findsNothing);
      expect(find.text('Consultar catálogo guardado'), findsNothing);
      backend.fallan.clear();
      await tester.tap(find.text('Reintentar'));
      await asentar(tester);
      expect(
        find.text('Elegí una tienda para ver su catálogo'),
        findsOneWidget,
      );
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Tienda A').last);
      await asentar(tester);
      expect(backend.pedidos, contains('GET /catalog/products'));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('ingreso explica cómo recuperarse si el directorio falla', (
    tester,
  ) async {
    final backend = BackendFalso()..fallan['/public/stores'] = 503;
    await montarPantalla(
      tester,
      const LoginScreen(),
      backend: backend,
      conSesion: false,
    );
    expect(find.text('Actualizar empresas'), findsOneWidget);
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    expect(find.text('Ingresar código de empresa'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('el registro permite elegir la tienda de la cuenta', (
    tester,
  ) async {
    await montarPantalla(
      tester,
      const RegisterScreen(),
      backend: BackendFalso(),
      conSesion: false,
    );
    expect(find.text('Empresa o tienda'), findsOneWidget);
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    expect(find.text('Tienda A'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
