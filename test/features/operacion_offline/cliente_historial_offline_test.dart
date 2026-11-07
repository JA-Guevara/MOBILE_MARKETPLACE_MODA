import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_marketplace_moda/app/theme.dart';
import 'package:mobile_marketplace_moda/core/network/api_client.dart';
import 'package:mobile_marketplace_moda/core/offline/base_local.dart';
import 'package:mobile_marketplace_moda/core/storage/token_store.dart';
import 'package:mobile_marketplace_moda/features/operacion_offline/application/catalogo_offline_controller.dart';
import 'package:mobile_marketplace_moda/features/operacion_offline/application/historial_sincronizacion_provider.dart';
import 'package:mobile_marketplace_moda/features/operacion_offline/domain/catalogo_local.dart';
import 'package:mobile_marketplace_moda/features/operacion_offline/domain/sincronizacion.dart';
import 'package:mobile_marketplace_moda/features/operacion_offline/infrastructure/catalogo_local_dao.dart';
import 'package:mobile_marketplace_moda/features/operacion_offline/infrastructure/imagenes_offline.dart';
import 'package:mobile_marketplace_moda/features/operacion_offline/infrastructure/instantanea_api.dart';
import 'package:mobile_marketplace_moda/features/operacion_offline/presentation/historial_sincronizacion_screen.dart';
import 'package:mobile_marketplace_moda/features/operacion_offline/presentation/venta_offline_screen.dart';
import 'package:mobile_marketplace_moda/features/usuarios_catalogo/application/session_controller.dart';
import 'package:mobile_marketplace_moda/features/usuarios_catalogo/domain/usuario.dart';
import 'package:mobile_marketplace_moda/features/usuarios_catalogo/infrastructure/auth_api.dart';
import 'fixtures.dart';

class _Sesion extends SessionController {
  _Sesion(Usuario usuario) : super(AuthApi(ApiClient()), TokenStore()) {
    state = EstadoSesion(
      usuario: usuario,
      restaurando: false,
      sinConexion: true,
    );
  }
}

/// DAO sin base real: la pantalla solo necesita las cajas de la sucursal.
class _DaoCajas extends CatalogoLocalDao {
  _DaoCajas() : super(BaseLocal());
  @override
  Future<List<CajaLocal>> cajas(String sucursalId) async => const [
    CajaLocal(id: 'cash-1', sucursalId: 'b1', codigo: 'C1', nombre: 'Caja 1'),
  ];
}

class _Catalogo extends CatalogoOfflineController {
  _Catalogo(Usuario usuario)
    : super(
        _DaoCajas(),
        InstantaneaApi(ApiClient()),
        ImagenesOffline(),
        usuario,
      ) {
    final i = instantanea();
    state = EstadoCatalogoOffline(
      datos: DatosLocales(
        productos: i.productos,
        variantes: i.variantes,
        existencias: i.existencias.where((e) => e.sucursalId == 'b1').toList(),
        sucursales: i.sucursales,
        clientes: const [
          ClienteLocal(id: 'c1', nombre: 'Ana Perez', documentoFinal: '123'),
          ClienteLocal(id: 'c2', nombre: 'Bruno Rojas'),
        ],
      ),
      sucursalId: 'b1',
      version: i.version,
      descargadoEn: DateTime.now(),
      cargando: false,
    );
  }

  @override
  Future<void> iniciar() async {}
}

void main() {
  Future<void> montar(
    WidgetTester tester,
    Widget pantalla, {
    List<RegistroSincronizacion> historial = const [],
  }) async {
    tester.view.physicalSize = const Size(320, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final usuario = usuarioOffline();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sessionProvider.overrideWith((ref) => _Sesion(usuario)),
          catalogoOfflineProvider.overrideWith((ref) => _Catalogo(usuario)),
          historialSincronizacionProvider.overrideWith(
            (ref) async => historial,
          ),
        ],
        child: MaterialApp(theme: AppTheme.claro, home: pantalla),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  }

  testWidgets('CU-18 venta local permite buscar, elegir y quitar cliente', (
    tester,
  ) async {
    await montar(tester, const VentaOfflineScreen());
    final buscador = find.byKey(const Key('venta-buscar-cliente'));
    expect(buscador, findsOneWidget);
    expect(find.text('Bruno Rojas'), findsNothing);

    await tester.enterText(buscador, 'ana');
    await tester.pump();
    expect(find.text('Ana Perez'), findsOneWidget);
    expect(find.text('Bruno Rojas'), findsNothing);

    await tester.tap(find.text('Ana Perez'));
    await tester.pump();
    expect(find.byKey(const Key('venta-cliente-elegido')), findsOneWidget);
    expect(find.text('Cliente de la venta'), findsOneWidget);
    expect(buscador, findsNothing);

    await tester.tap(find.byTooltip('Quitar cliente'));
    await tester.pump();
    expect(find.byKey(const Key('venta-cliente-elegido')), findsNothing);
    expect(find.byKey(const Key('venta-buscar-cliente')), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('venta-buscar-cliente')),
      'zzz',
    );
    await tester.pump();
    expect(
      find.text('Sin coincidencias. La venta puede seguir sin cliente.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('CU-19 historial vacío muestra estado vacío', (tester) async {
    await montar(tester, const HistorialSincronizacionScreen());
    expect(find.text('Historial de sincronización'), findsOneWidget);
    expect(
      find.text(
        'Todavía no hay sincronizaciones registradas en este dispositivo.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('CU-19 historial muestra contadores y error', (tester) async {
    await montar(
      tester,
      const HistorialSincronizacionScreen(),
      historial: [
        RegistroSincronizacion(
          id: 2,
          iniciadoEn: DateTime(2026, 11, 7, 10, 30),
          enviadas: 5,
          confirmadas: 3,
          conflictos: 1,
          rechazadas: 1,
        ),
        RegistroSincronizacion(
          id: 1,
          iniciadoEn: DateTime(2026, 11, 6, 9, 0),
          enviadas: 2,
          confirmadas: 0,
          conflictos: 0,
          rechazadas: 0,
          codigoError: 'NETWORK',
        ),
      ],
    );
    expect(find.text('Enviadas: 5'), findsOneWidget);
    expect(find.text('Aceptadas: 3'), findsOneWidget);
    expect(find.text('Rechazadas: 1'), findsOneWidget);
    expect(find.text('En conflicto: 1'), findsOneWidget);
    expect(find.text('Enviadas: 2'), findsOneWidget);
    expect(find.textContaining('Error: Sin conexión'), findsOneWidget);
  });
}
