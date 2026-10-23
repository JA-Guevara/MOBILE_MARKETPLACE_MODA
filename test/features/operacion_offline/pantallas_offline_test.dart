import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:mobile_marketplace_moda/app/theme.dart';
import 'package:mobile_marketplace_moda/core/network/api_client.dart';
import 'package:mobile_marketplace_moda/core/offline/base_local.dart';
import 'package:mobile_marketplace_moda/core/offline/conectividad.dart';
import 'package:mobile_marketplace_moda/core/storage/token_store.dart';
import 'package:mobile_marketplace_moda/features/usuarios_catalogo/application/session_controller.dart';
import 'package:mobile_marketplace_moda/features/usuarios_catalogo/infrastructure/auth_api.dart';
import 'package:mobile_marketplace_moda/features/usuarios_catalogo/domain/usuario.dart';
import 'package:mobile_marketplace_moda/features/operacion_offline/application/catalogo_offline_controller.dart';
import 'package:mobile_marketplace_moda/features/operacion_offline/application/reserva_offline_controller.dart';
import 'package:mobile_marketplace_moda/features/operacion_offline/domain/catalogo_local.dart';
import 'package:mobile_marketplace_moda/features/operacion_offline/domain/reserva_local.dart';
import 'package:mobile_marketplace_moda/features/operacion_offline/infrastructure/catalogo_local_dao.dart';
import 'package:mobile_marketplace_moda/features/operacion_offline/infrastructure/instantanea_api.dart';
import 'package:mobile_marketplace_moda/features/operacion_offline/infrastructure/imagenes_offline.dart';
import 'package:mobile_marketplace_moda/features/operacion_offline/infrastructure/reservas_locales_dao.dart';
import 'package:mobile_marketplace_moda/features/operacion_offline/presentation/catalogo_offline_screen.dart';
import 'package:mobile_marketplace_moda/features/operacion_offline/presentation/preparar_offline_screen.dart';
import 'package:mobile_marketplace_moda/features/operacion_offline/presentation/reserva_offline_screen.dart';
import 'package:mobile_marketplace_moda/features/operacion_offline/presentation/reservas_locales_screen.dart';
import 'package:mobile_marketplace_moda/features/operacion_offline/presentation/comprobante_reserva_screen.dart';
import 'fixtures.dart';

class SesionVisible extends SessionController {
  SesionVisible(Usuario usuario) : super(AuthApi(ApiClient()), TokenStore()) {
    state = EstadoSesion(
      usuario: usuario,
      restaurando: false,
      sinConexion: true,
    );
  }
}

class CatalogoVisible extends CatalogoOfflineController {
  CatalogoVisible(Usuario usuario, {bool vacio = false})
    : super(
        CatalogoLocalDao(BaseLocal()),
        InstantaneaApi(ApiClient()),
        ImagenesOffline(),
        usuario,
      ) {
    final i = instantanea();
    state = vacio
        ? const EstadoCatalogoOffline(cargando: false)
        : EstadoCatalogoOffline(
            datos: DatosLocales(
              productos: i.productos,
              variantes: i.variantes,
              existencias: i.existencias
                  .where((e) => e.sucursalId == 'b1')
                  .toList(),
              sucursales: i.sucursales,
              clientes: i.clientes,
            ),
            sucursalId: 'b1',
            version: i.version,
            descargadoEn: DateTime.now().subtract(const Duration(hours: 26)),
            cargando: false,
          );
  }
}

class ReservaVisible extends ReservaOfflineController {
  ReservaVisible(Usuario usuario)
    : super(
        BaseLocal(),
        ReservasLocalesDao(BaseLocal(), tenantId: 'tenant-a', usuarioId: 'u1'),
        usuario,
        () => const EstadoCatalogoOffline(),
        () async {},
      ) {
    state = EstadoReservaOffline(
      items: itemsPara(reserva()),
      sucursalId: 'b1',
      agendadaPara: DateTime(2030, 10, 25, 10, 30),
    );
  }
}

void main() {
  setUpAll(() async {
    // Flutter test usa Ahem por defecto. Para capturas legibles se carga una
    // fuente local cuando existe; las pruebas siguen portables sin Windows.
    final font = File('C:/Windows/Fonts/segoeui.ttf');
    if (await font.exists()) {
      final loader = FontLoader('Roboto')
        ..addFont(font.readAsBytes().then((b) => ByteData.sublistView(b)));
      await loader.load();
    }
    final icons = File(
      'C:/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
    );
    if (await icons.exists()) {
      final loader = FontLoader('MaterialIcons')
        ..addFont(icons.readAsBytes().then((b) => ByteData.sublistView(b)));
      await loader.load();
    }
  });
  final captura = GlobalKey();
  Future<void> montar(
    WidgetTester tester,
    Widget pantalla, {
    bool suspendida = false,
    bool vacio = false,
  }) async {
    tester.view.physicalSize = const Size(320, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final usuario = usuarioOffline(
      estado: suspendida ? 'SUSPENDIDA' : 'ACTIVA',
    );
    final r = reserva();
    final items = itemsPara(r);
    final vista = ReservaLocalVista(
      r,
      items,
      operacion(r, items),
      sucursalNombre: 'Centro',
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sessionProvider.overrideWith((ref) => SesionVisible(usuario)),
          conectividadProvider.overrideWith((ref) => Stream.value(false)),
          catalogoOfflineProvider.overrideWith(
            (ref) => CatalogoVisible(usuario, vacio: vacio),
          ),
          reservaOfflineProvider.overrideWith((ref) => ReservaVisible(usuario)),
          reservasLocalesProvider.overrideWith((ref) async => [vista]),
          reservaLocalProvider(r.id).overrideWith((ref) async => vista),
          descargaAutomaticaProvider.overrideWith((ref) async => true),
        ],
        child: MaterialApp(
          theme: AppTheme.claro,
          home: RepaintBoundary(key: captura, child: pantalla),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  }

  Future<void> guardarCaptura(WidgetTester tester, String nombre) async {
    final boundary =
        captura.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    await tester.runAsync(() async {
      final image = await boundary.toImage();
      final datos = await image.toByteData(format: ui.ImageByteFormat.png);
      final carpeta = Directory('build/qa-offline');
      await carpeta.create(recursive: true);
      await File(
        '${carpeta.path}/$nombre.png',
      ).writeAsBytes(datos!.buffer.asUint8List());
      image.dispose();
    });
  }

  testWidgets('catálogo 320px, aviso 26h, filtros y selección de variante', (
    tester,
  ) async {
    await montar(tester, const CatalogoOfflineScreen());
    expect(
      find.textContaining('La información puede estar desactualizada'),
      findsOneWidget,
    );
    expect(find.text('Vestido lino Aurora'), findsOneWidget);
    await guardarCaptura(tester, 'catalogo-320');
    await tester.ensureVisible(find.text('Filtros'));
    await tester.tap(find.text('Filtros'));
    await tester.pumpAndSettle();
    expect(find.text('Solo con stock local'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('preparar 320px con descarga y datos guardados', (tester) async {
    await montar(tester, const PrepararOfflineScreen());
    expect(find.text('Descarga automática'), findsOneWidget);
    await guardarCaptura(tester, 'preparar-320');
  });
  testWidgets('reserva 320px no desborda y muestra prendas y fecha', (
    tester,
  ) async {
    await montar(tester, const ReservaOfflineScreen());
    expect(find.text('Vestido lino Aurora'), findsOneWidget);
    await guardarCaptura(tester, 'reserva-320');
    await tester.drag(find.byType(ListView), const Offset(0, -500));
    await tester.pumpAndSettle();
    expect(find.text('Confirmar reserva sin conexión'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('suscripción suspendida deshabilita confirmar', (tester) async {
    await montar(tester, const ReservaOfflineScreen(), suspendida: true);
    await tester.drag(find.byType(ListView), const Offset(0, -700));
    await tester.pumpAndSettle();
    final boton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Confirmar reserva sin conexión'),
    );
    expect(boton.onPressed, isNull);
    expect(tester.takeException(), isNull);
  });
  testWidgets('comprobante local 320px incluye QR provisional y UUID', (
    tester,
  ) async {
    await montar(tester, ComprobanteReservaScreen(id: reserva().id));
    expect(find.text('Comprobante provisional de reserva'), findsOneWidget);
    await guardarCaptura(tester, 'comprobante-320');
  });
  testWidgets('lista local 320px muestra pendiente y permite cancelar', (
    tester,
  ) async {
    await montar(tester, const ReservasLocalesScreen());
    expect(find.text('Pendiente de sincronizar'), findsOneWidget);
    expect(find.text('Cancelar'), findsOneWidget);
    await guardarCaptura(tester, 'reservas-320');
  });
  testWidgets('catálogo nunca descargado presenta estado vacío', (
    tester,
  ) async {
    await montar(tester, const CatalogoOfflineScreen(), vacio: true);
    expect(find.text('Aún no hay datos sin conexión'), findsOneWidget);
  });
}
