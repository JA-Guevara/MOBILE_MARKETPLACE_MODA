import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_marketplace_moda/features/reservas_vestidor/presentation/mis_reservas_screen.dart';
import 'package:mobile_marketplace_moda/features/reservas_vestidor/presentation/nueva_reserva_screen.dart';
import 'package:mobile_marketplace_moda/features/usuarios_catalogo/presentation/account_screen.dart';
import 'package:mobile_marketplace_moda/features/usuarios_catalogo/presentation/catalog_screen.dart';
import 'package:mobile_marketplace_moda/features/usuarios_catalogo/presentation/direcciones_screen.dart';
import 'package:mobile_marketplace_moda/features/usuarios_catalogo/presentation/prenda_screen.dart';
import 'package:mobile_marketplace_moda/features/ventas_pagos/presentation/carrito_screen.dart';
import 'package:mobile_marketplace_moda/features/ventas_pagos/presentation/favoritos_screen.dart';
import 'package:mobile_marketplace_moda/features/ventas_pagos/presentation/pedido_detalle_screen.dart';
import 'package:mobile_marketplace_moda/features/ventas_pagos/presentation/pedidos_screen.dart';
import 'package:mobile_marketplace_moda/features/ventas_pagos/presentation/sucursales_screen.dart';

import 'package:mobile_marketplace_moda/shared/widgets/estado_vista.dart';

import 'support/backend_falso.dart';

/// Cada pantalla del cliente, montada de verdad contra un backend falso.
///
/// `flutter analyze` no detecta que una pantalla no se dibuja: eso solo se ve
/// construyéndola. Estas pruebas recorren las once vistas con datos y sin
/// datos, que son los dos estados donde aparecen los errores de layout.
void main() {
  late BackendFalso backend;

  setUp(() => backend = BackendFalso());

  /// Falla la prueba con el error real si la pantalla reventó al construirse.
  void sinExcepciones(WidgetTester tester) {
    final error = tester.takeException();
    expect(error, isNull, reason: 'La pantalla lanzó: $error');
  }

  group('catálogo', () {
    testWidgets('se dibuja con prendas', (tester) async {
      await montarPantalla(tester, const CatalogScreen(), backend: backend);
      sinExcepciones(tester);
      expect(find.text('Vestido midi'), findsWidgets);
      // El precio va con separador de miles y coma decimal, como la web.
      expect(find.text('Bs 420,00'), findsWidgets);
    });

    testWidgets('se dibuja sin prendas', (tester) async {
      backend.vacio = true;
      await montarPantalla(tester, const CatalogScreen(), backend: backend);
      sinExcepciones(tester);
      expect(find.text('Todavía no hay prendas para mostrar'), findsOneWidget);
    });
  });

  group('detalle de prenda', () {
    testWidgets('muestra fotos, tallas, colores y precio', (tester) async {
      await montarPantalla(
        tester,
        const PrendaScreen(slug: 'vestido-midi-01'),
        backend: backend,
      );
      sinExcepciones(tester);

      expect(find.text('Pequeño'), findsOneWidget);
      expect(find.text('Mediano'), findsOneWidget);
      expect(find.text('Mostaza'), findsOneWidget);
      expect(find.text('Negro'), findsOneWidget);
      expect(find.text('Bs 420,00'), findsWidgets);
    });

    testWidgets('el botón de agregar al carrito está habilitado', (tester) async {
      await montarPantalla(
        tester,
        const PrendaScreen(slug: 'vestido-midi-01'),
        backend: backend,
      );

      final boton = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Agregar al carrito'),
      );
      expect(boton.onPressed, isNotNull,
          reason: 'Con una variante preseleccionada tiene que poder comprarse.');
    });

    testWidgets('tocar agregar al carrito llama al backend', (tester) async {
      await montarPantalla(
        tester,
        const PrendaScreen(slug: 'vestido-midi-01'),
        backend: backend,
      );

      await tester.tap(find.widgetWithText(FilledButton, 'Agregar al carrito'));
      await asentar(tester);

      sinExcepciones(tester);
      expect(backend.pedidos, contains('PUT /commerce/cart/items/v1'));
      // El botón vive en la barra fija de abajo: si el aviso se dibujara en el
      // cuerpo de la ficha caería fuera de la vista y parecería que no pasó
      // nada. Tiene que ser un `SnackBar`.
      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.text('Agregamos la prenda a tu carrito.'), findsOneWidget);
      expect(find.text('Ver carrito'), findsOneWidget);
    });

    testWidgets('el corazón de favorito también avisa', (tester) async {
      await montarPantalla(
        tester,
        const PrendaScreen(slug: 'vestido-midi-01'),
        backend: backend,
      );

      await tester.tap(find.byIcon(Icons.favorite_border));
      await asentar(tester);

      sinExcepciones(tester);
      expect(backend.pedidos, contains('PUT /commerce/favorites/p1'));
      expect(find.byType(SnackBar), findsOneWidget);
    });

    testWidgets('ofrece el probador y el botón de reservar', (tester) async {
      await montarPantalla(
        tester,
        const PrendaScreen(slug: 'vestido-midi-01'),
        backend: backend,
      );
      sinExcepciones(tester);
      expect(find.text('Probarme'), findsOneWidget);
      expect(find.text('Reservar para probarme en sucursal'), findsOneWidget);
    });

    testWidgets('una prenda que no existe muestra el error, no un blanco',
        (tester) async {
      backend.fallan['/catalog/products/no-existe'] = 404;
      await montarPantalla(
        tester,
        const PrendaScreen(slug: 'no-existe'),
        backend: backend,
      );
      sinExcepciones(tester);
      expect(find.text('Reintentar'), findsOneWidget);
    });
  });

  group('carrito', () {
    testWidgets('se dibuja con líneas, cupón, sucursal y total', (tester) async {
      await montarPantalla(tester, const CarritoScreen(), backend: backend);
      sinExcepciones(tester);

      expect(find.text('Vestido midi'), findsOneWidget);
      expect(find.text('Centro'), findsOneWidget);
      expect(find.text('Total'), findsOneWidget);
      expect(find.text('Bs 800,00'), findsOneWidget);
    });

    testWidgets('se dibuja vacío', (tester) async {
      backend.vacio = true;
      await montarPantalla(tester, const CarritoScreen(), backend: backend);
      sinExcepciones(tester);
      expect(find.text('Tu carrito está vacío'), findsOneWidget);
    });

    testWidgets('no desborda el control de cantidad en un teléfono angosto',
        (tester) async {
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await montarPantalla(tester, const CarritoScreen(), backend: backend);

      sinExcepciones(tester);
      expect(find.text('Quitar'), findsOneWidget);
    });
  });

  group('pedidos', () {
    testWidgets('la lista se dibuja', (tester) async {
      await montarPantalla(tester, const PedidosScreen(), backend: backend);
      sinExcepciones(tester);
      expect(find.text('Pedido P-000123'), findsOneWidget);
      expect(find.text('Entregado'), findsOneWidget);
    });

    testWidgets('la lista vacía se dibuja', (tester) async {
      backend.vacio = true;
      await montarPantalla(tester, const PedidosScreen(), backend: backend);
      sinExcepciones(tester);
      expect(find.text('Todavía no hiciste ningún pedido'), findsOneWidget);
    });

    testWidgets('el detalle dibuja seguimiento y devoluciones', (tester) async {
      await montarPantalla(
        tester,
        const PedidoDetalleScreen(id: 'o1'),
        backend: backend,
      );
      sinExcepciones(tester);
      expect(find.text('Seguimiento'), findsOneWidget);
      expect(find.text('Entregado'), findsWidgets);

      // «Cambios y devoluciones» está al final de la lista: en un `ListView` lo que no
      // se ve no se construye, así que hay que bajar para encontrarlo.
      await tester.scrollUntilVisible(find.text('Cambios y devoluciones'), 300);
      sinExcepciones(tester);
      expect(find.text('Cambios y devoluciones'), findsOneWidget);
    });
  });

  group('favoritos', () {
    testWidgets('se dibuja con avisos de stock y precio', (tester) async {
      await montarPantalla(tester, const FavoritosScreen(), backend: backend);
      sinExcepciones(tester);
      expect(find.text('Vestido midi'), findsOneWidget);
      expect(find.text('Avisarme si vuelve el stock'), findsOneWidget);
    });

    testWidgets('se dibuja vacío', (tester) async {
      backend.vacio = true;
      await montarPantalla(tester, const FavoritosScreen(), backend: backend);
      sinExcepciones(tester);
      expect(find.text('Todavía no guardaste ninguna prenda'), findsOneWidget);
    });
  });

  group('direcciones', () {
    testWidgets('se dibuja con la predeterminada marcada', (tester) async {
      await montarPantalla(tester, const DireccionesScreen(), backend: backend);
      sinExcepciones(tester);
      expect(find.text('Casa'), findsOneWidget);
      expect(find.text('Predeterminada'), findsOneWidget);
    });

    testWidgets('se dibuja vacía', (tester) async {
      backend.vacio = true;
      await montarPantalla(tester, const DireccionesScreen(), backend: backend);
      sinExcepciones(tester);
      expect(find.text('Todavía no guardaste direcciones'), findsOneWidget);
    });
  });

  group('sucursales', () {
    testWidgets('se dibuja', (tester) async {
      await montarPantalla(tester, const SucursalesScreen(), backend: backend);
      sinExcepciones(tester);
      expect(find.text('Centro'), findsOneWidget);
      expect(find.text('Norte'), findsOneWidget);
    });
  });

  group('reservas', () {
    testWidgets('mis reservas se dibuja', (tester) async {
      await montarPantalla(tester, const MisReservasScreen(), backend: backend);
      sinExcepciones(tester);
      expect(find.text('Pendiente de confirmar'), findsOneWidget);
    });

    testWidgets('mis reservas vacío se dibuja', (tester) async {
      backend.vacio = true;
      await montarPantalla(tester, const MisReservasScreen(), backend: backend);
      sinExcepciones(tester);
      expect(find.text('Todavía no agendaste ninguna visita'), findsOneWidget);
    });

    testWidgets('nueva reserva se dibuja con la selección vacía', (tester) async {
      await montarPantalla(tester, const NuevaReservaScreen(), backend: backend);
      sinExcepciones(tester);
      // El aviso lo pinta `BloqueAyuda`, que usa `Text.rich`: `find.text` no
      // mira dentro de los `TextSpan`, así que se busca el widget.
      expect(find.byType(BloqueAyuda), findsOneWidget);
      expect(find.text('Centro'), findsOneWidget);
      expect(find.text('Cuándo pasás'), findsOneWidget);
    });
  });

  group('mi cuenta', () {
    testWidgets('se dibuja con el perfil y los accesos', (tester) async {
      await montarPantalla(tester, const AccountScreen(), backend: backend);
      sinExcepciones(tester);
      expect(find.text('Ana Vargas'), findsOneWidget);
      expect(find.text('Mis pedidos'), findsOneWidget);
      expect(find.text('Mis favoritos'), findsOneWidget);
      expect(find.text('Mis direcciones'), findsOneWidget);
    });
  });
}
