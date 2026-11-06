import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:mobile_marketplace_moda/core/network/api_client.dart';
import 'package:mobile_marketplace_moda/core/network/api_exception.dart';
import 'package:mobile_marketplace_moda/core/offline/base_local.dart';
import 'package:mobile_marketplace_moda/core/offline/sincronizacion_fondo.dart';
import 'package:mobile_marketplace_moda/features/operacion_offline/domain/reserva_local.dart';
import 'package:mobile_marketplace_moda/features/operacion_offline/domain/sincronizacion.dart';
import 'package:mobile_marketplace_moda/features/operacion_offline/infrastructure/operaciones_dao.dart';
import 'package:mobile_marketplace_moda/features/operacion_offline/infrastructure/sync_api.dart';
import 'package:mobile_marketplace_moda/features/usuarios_catalogo/domain/usuario.dart';

class RegistradorFalso implements RegistradorSincronizacion {
  int inicios = 0;
  int registros = 0;
  @override
  Future<void> inicializar() async => inicios++;
  @override
  Future<void> programar(Duration frecuencia) async => registros++;
  @override
  Future<void> cancelar() async {}
}

class ApiFalsa extends SyncApi {
  ApiFalsa({this.fallo}) : super(ApiClient());
  final ApiException? fallo;
  final envios = <List<SyncOperationWire>>[];
  @override
  Future<SyncBatchResponse> postBatch(List<SyncOperationWire> operaciones) async {
    envios.add(operaciones);
    if (fallo != null) throw fallo!;
    return SyncBatchResponse(
      batchId: 'batch-test',
      received: operaciones.length,
      confirmed: operaciones.length,
      conflicts: 0,
      rejected: 0,
      results: operaciones.map((op) => SyncResult(
        clientRequestId: op.clientRequestId,
        status: 'CONFIRMED',
        message: 'Confirmada',
      )).toList(),
    );
  }
}

const usuario = Usuario(
  id: 'u1', email: 'operador@example.com', nombre: 'Operador', apellido: 'Prueba',
  empresa: EmpresaResumen(id: 't1', slug: 'tienda-uno', nombre: 'Tienda', estado: 'ACTIVA'),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  late BaseLocal base;
  late OperacionesDao dao;
  setUp(() async {
    base = BaseLocal(fabrica: databaseFactoryFfi, ruta: inMemoryDatabasePath);
    dao = OperacionesDao(base);
    await base.guardarMeta('usuario_offline', jsonEncode(usuario.aJson()));
    final db = await base.abrir();
    for (final item in [('propia', 't1', 'u1'), ('otra-empresa', 't2', 'u1'), ('otro-usuario', 't1', 'u2')]) {
      await db.insert('operaciones_pendientes', OperacionPendiente(
        id: item.$1, tenantId: item.$2, usuarioId: item.$3,
        sucursalId: 'b1', dispositivoId: 'device-prueba', payload: {},
        creadaEn: DateTime.utc(2026, 11, 6), actualizadaEn: DateTime.utc(2026, 11, 6),
      ).aFila());
    }
  });
  tearDown(() => base.cerrar());

  test('el arranque registra una tarea aunque se invoque concurrentemente', () async {
    final registrador = RegistradorFalso();
    await Future.wait(List.generate(3, (_) => SincronizacionFondo.inicializar(registrador: registrador)));
    await Future.wait(List.generate(3, (_) => SincronizacionFondo.programar(registrador: registrador)));
    expect(registrador.inicios, 1);
    expect(registrador.registros, 1);
  });

  test('sin red no envía ni cambia las operaciones pendientes', () async {
    final api = ApiFalsa();
    final resultado = await SincronizacionFondo.ejecutarSincronizacion(
      base: base, api: api, usuario: usuario, hayRed: () async => false,
    );
    expect(resultado, isFalse);
    expect(api.envios, isEmpty);
    expect(await dao.listarPendientes(), hasLength(3));
    expect((await dao.listarPendientes()).every((op) => op.intentos == 0), isTrue);
  });

  test('429 conserva SQLite y respeta Retry-After incluso entre ejecuciones', () async {
    final api = ApiFalsa(fallo: const ApiException('En espera', statusCode: 429, retryAfter: '120'));
    var ahora = DateTime.utc(2026, 11, 6);
    for (var i = 0; i < 2; i++) {
      expect(await SincronizacionFondo.ejecutarSincronizacion(
        base: base, api: api, usuario: usuario, hayRed: () async => true, ahora: () => ahora,
      ), isFalse);
    }
    expect(api.envios, hasLength(1));
    expect(await dao.listarPendientes(), hasLength(3));
    expect((await dao.listarPendientes()).every((op) => op.intentos == 0), isTrue);
    ahora = ahora.add(const Duration(seconds: 121));
    await SincronizacionFondo.ejecutarSincronizacion(
      base: base, api: api, usuario: usuario, hayRed: () async => true, ahora: () => ahora,
    );
    expect(api.envios, hasLength(2));
  });

  test('solo envía operaciones de la empresa y usuario autenticados', () async {
    final api = ApiFalsa();
    expect(await SincronizacionFondo.ejecutarSincronizacion(
      base: base, api: api, usuario: usuario, hayRed: () async => true,
    ), isTrue);
    expect(api.envios.single.map((op) => op.clientRequestId), ['propia']);
    expect((await dao.listarPendientes()).map((op) => op.id).toSet(), {'otra-empresa', 'otro-usuario'});
  });

  test('sin identidad no envía ni elimina ninguna operación', () async {
    final api = ApiFalsa();
    await base.borrarMeta('usuario_offline');
    expect(await SincronizacionFondo.ejecutarSincronizacion(
      base: base, api: api, hayRed: () async => true,
    ), isFalse);
    expect(api.envios, isEmpty);
    expect(await dao.listarPendientes(), hasLength(3));
  });
}
