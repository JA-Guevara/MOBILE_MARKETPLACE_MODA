import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:mobile_marketplace_moda/app/theme.dart';
import 'package:mobile_marketplace_moda/core/network/api_exception.dart';
import 'package:mobile_marketplace_moda/core/offline/base_local.dart';
import 'package:mobile_marketplace_moda/core/storage/token_store.dart';
import 'package:mobile_marketplace_moda/features/operacion_offline/domain/reserva_local.dart';
import 'package:mobile_marketplace_moda/features/operacion_offline/domain/sincronizacion.dart';
import 'package:mobile_marketplace_moda/features/operacion_offline/infrastructure/operaciones_dao.dart';
import 'package:mobile_marketplace_moda/features/usuarios_catalogo/application/session_controller.dart';
import 'package:mobile_marketplace_moda/features/usuarios_catalogo/domain/usuario.dart';
import 'package:mobile_marketplace_moda/features/usuarios_catalogo/infrastructure/auth_api.dart';
import 'package:mobile_marketplace_moda/shared/widgets/aviso_suscripcion.dart';

class _FakeAuthApi implements AuthApi {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeTokenStore implements TokenStore {
  @override
  Future<void> guardarRefresh(String token) async {}
  @override
  Future<String?> leerRefresh() async => null;
  @override
  Future<void> limpiar() async {}
}

void main() {
  sqfliteFfiInit();

  Widget wrapWithTheme(Widget child, [List<Override> overrides = const []]) {
    return ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        theme: AppTheme.claro,
        home: Scaffold(body: child),
      ),
    );
  }

  Usuario crearUsuarioMock({
    String estadoSuscripcion = 'ACTIVA',
    int diasRestantes = 20,
  }) {
    return Usuario(
      id: 'usr-1',
      email: 'admin@laslomas.test',
      nombre: 'Admin',
      apellido: 'Lomas',
      empresa: const EmpresaResumen(
        id: 't-1',
        slug: 'las-lomas',
        nombre: 'Las Lomas Moda',
        estado: 'ACTIVA',
      ),
      suscripcion: SuscripcionResumen(
        codigoPlan: 'plan-pro',
        nombrePlan: 'Plan Profesional',
        estado: estadoSuscripcion,
        diasRestantes: diasRestantes,
        funciones: const {'sales': true, 'offline': true},
      ),
      permisos: const {'orders.write', 'catalog.write'},
    );
  }

  group('AvisoSuscripcion y estados de ciclo', () {
    testWidgets('activa normal no muestra banner', (tester) async {
      final controller = SessionController(
        _FakeAuthApi(),
        _FakeTokenStore(),
      );
      controller.state = EstadoSesion(
        usuario: crearUsuarioMock(),
        restaurando: false,
        lifecycleState: 'active',
      );

      await tester.pumpWidget(
        wrapWithTheme(
          const AvisoSuscripcion(),
          [sessionProvider.overrideWith((ref) => controller)],
        ),
      );

      expect(find.byType(AvisoSuscripcion), findsOneWidget);
      expect(find.text('Modo solo lectura activado'), findsNothing);
      expect(find.text('Suscripción en gracia'), findsNothing);
      expect(find.text('Suscripción por vencer'), findsNothing);
    });

    testWidgets('en gracia muestra alerta según maqueta px-movil', (tester) async {
      final controller = SessionController(
        _FakeAuthApi(),
        _FakeTokenStore(),
      );
      controller.state = EstadoSesion(
        usuario: crearUsuarioMock(estadoSuscripcion: 'ACTIVA', diasRestantes: 2),
        restaurando: false,
        lifecycleState: 'grace',
        graceUntil: '2026-11-08',
      );

      await tester.pumpWidget(
        wrapWithTheme(
          const AvisoSuscripcion(),
          [sessionProvider.overrideWith((ref) => controller)],
        ),
      );

      expect(find.text('Suscripción en gracia'), findsOneWidget);
      expect(find.textContaining('Hasta el 2026-11-08. Luego solo lectura.'), findsOneWidget);
    });

    testWidgets('solo lectura muestra alerta y desactiva operaciones', (tester) async {
      final controller = SessionController(
        _FakeAuthApi(),
        _FakeTokenStore(),
      );
      controller.state = EstadoSesion(
        usuario: crearUsuarioMock(estadoSuscripcion: 'VENCIDA', diasRestantes: 0),
        restaurando: false,
        lifecycleState: 'read_only',
        soloLecturaPorSuscripcion: true,
      );

      await tester.pumpWidget(
        wrapWithTheme(
          const AvisoSuscripcion(),
          [sessionProvider.overrideWith((ref) => controller)],
        ),
      );

      expect(find.text('Modo solo lectura activado'), findsOneWidget);
      expect(
        find.textContaining('No se pueden registrar ventas ni reservas'),
        findsOneWidget,
      );
    });
  });

  group('Caso obligatorio 1: Solo lectura deshabilita vender', () {
    testWidgets('en cuenta activa vender está habilitado', (tester) async {
      bool vendio = false;
      final controller = SessionController(_FakeAuthApi(), _FakeTokenStore());
      controller.state = EstadoSesion(
        usuario: crearUsuarioMock(),
        restaurando: false,
        lifecycleState: 'active',
      );

      await tester.pumpWidget(
        wrapWithTheme(
          AccionSoloLectura(
            accion: 'vender',
            onPressed: () => vendio = true,
            child: (context, callback, bloqueado) => ElevatedButton(
              onPressed: callback,
              child: const Text('Confirmar venta'),
            ),
          ),
          [sessionProvider.overrideWith((ref) => controller)],
        ),
      );

      expect(find.text('Confirmar venta'), findsOneWidget);
      expect(find.textContaining('Acción deshabilitada'), findsNothing);

      await tester.tap(find.text('Confirmar venta'));
      await tester.pump();
      expect(vendio, isTrue);
    });

    testWidgets('en solo lectura vender queda deshabilitado con explicación', (
      tester,
    ) async {
      bool vendio = false;
      final controller = SessionController(_FakeAuthApi(), _FakeTokenStore());
      controller.state = EstadoSesion(
        usuario: crearUsuarioMock(estadoSuscripcion: 'VENCIDA', diasRestantes: 0),
        restaurando: false,
        lifecycleState: 'read_only',
        soloLecturaPorSuscripcion: true,
      );

      await tester.pumpWidget(
        wrapWithTheme(
          AccionSoloLectura(
            accion: 'vender',
            onPressed: () => vendio = true,
            child: (context, callback, bloqueado) => ElevatedButton(
              onPressed: callback,
              child: const Text('Confirmar venta'),
            ),
          ),
          [sessionProvider.overrideWith((ref) => controller)],
        ),
      );

      expect(find.text('Confirmar venta'), findsOneWidget);
      // Explanatory message displayed below the button
      expect(
        find.text('Acción deshabilitada (vender): suscripción en modo solo lectura.'),
        findsOneWidget,
      );

      // Tap should not trigger the callback because callback is null
      await tester.tap(find.text('Confirmar venta'));
      await tester.pump();
      expect(vendio, isFalse);
    });
  });

  group('Caso obligatorio 2: La operación offline sigue pendiente', () {
    late BaseLocal base;
    late OperacionesDao dao;

    setUp(() async {
      base = BaseLocal(fabrica: databaseFactoryFfi, ruta: inMemoryDatabasePath);
      dao = OperacionesDao(base);
    });

    tearDown(() => base.cerrar());

    test('operación offline permanece PENDIENTE ante 403 solo lectura o reintento', () async {
      final db = await base.abrir();
      final opVenta = OperacionPendiente(
        id: 'op-venta-local-101',
        tipo: 'VENTA',
        tenantId: 't-1',
        sucursalId: 'suc-centro',
        usuarioId: 'usr-1',
        dispositivoId: 'disp-caja-1',
        payload: {
          'client_request_id': 'op-venta-local-101',
          'total': 420.0,
          'items': {'prod-denim': 1},
        },
        creadaEn: DateTime.now(),
        actualizadaEn: DateTime.now(),
        estado: EstadoOperacion.pendiente,
      );

      // Guardar venta offline
      await db.insert('operaciones_pendientes', opVenta.aFila());

      // Verificar que está en PENDIENTE
      final pendientesIniciales = await dao.listarPendientes(tenantId: 't-1');
      expect(pendientesIniciales, hasLength(1));
      expect(pendientesIniciales.first.id, 'op-venta-local-101');
      expect(pendientesIniciales.first.estado, EstadoOperacion.pendiente);

      // Simular respuesta del backend al intentar sync durante período de solo lectura:
      // Status RETRY con reason_code subscription_read_only (RNF06)
      final resultadoRetry = SyncResult(
        clientRequestId: 'op-venta-local-101',
        status: 'RETRY',
        reasonCode: 'subscription_read_only',
        message: 'Rechazada temporalmente: empresa en modo solo lectura',
      );

      await dao.aplicarResultados([resultadoRetry]);

      // Verificar que la operación NO fue descartada ni borrada: sigue PENDIENTE
      final pendientesDespues = await dao.listarPendientes(tenantId: 't-1');
      expect(pendientesDespues, hasLength(1));
      expect(pendientesDespues.first.id, 'op-venta-local-101');
      expect(pendientesDespues.first.estado, EstadoOperacion.pendiente);
      expect(pendientesDespues.first.intentos, 1);
      expect(
        pendientesDespues.first.ultimoError,
        'Rechazada temporalmente: empresa en modo solo lectura',
      );

      // Actualizar SessionController con el error 403 subscription_read_only
      final sessionController = SessionController(_FakeAuthApi(), _FakeTokenStore());
      sessionController.state = EstadoSesion(
        usuario: crearUsuarioMock(),
        restaurando: false,
        lifecycleState: 'active',
      );

      sessionController.manejarError403(
        const ApiException(
          'subscription_read_only: suscripcion vencida',
          statusCode: 403,
        ),
      );

      expect(sessionController.state.soloLectura, isTrue);
      expect(sessionController.state.lifecycleState, 'read_only');
      expect(sessionController.state.soloLecturaPorSuscripcion, isTrue);

      // Re-verificar que las operaciones locales siguen intactas en la base local
      final pendientesFinal = await dao.listarPendientes(tenantId: 't-1');
      expect(pendientesFinal, hasLength(1));
    });
  });
}
