import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:mobile_marketplace_moda/core/network/api_client.dart';
import 'package:mobile_marketplace_moda/core/offline/base_local.dart';
import 'package:mobile_marketplace_moda/features/operacion_offline/application/catalogo_offline_controller.dart';
import 'package:mobile_marketplace_moda/features/operacion_offline/domain/catalogo_local.dart';
import 'package:mobile_marketplace_moda/features/operacion_offline/infrastructure/catalogo_local_dao.dart';
import 'package:mobile_marketplace_moda/features/operacion_offline/infrastructure/instantanea_api.dart';
import 'package:mobile_marketplace_moda/features/operacion_offline/infrastructure/imagenes_offline.dart';
import 'fixtures.dart';

class ApiInstantaneaFalsa extends InstantaneaApi {
  ApiInstantaneaFalsa() : super(ApiClient());
  int llamadas = 0;
  InstantaneaCatalogo respuesta = instantanea(version: '2026-10-24T12:00:00Z');
  @override
  Future<InstantaneaCatalogo> obtener({
    String? sucursalId,
    String? desde,
  }) async {
    llamadas++;
    return respuesta;
  }
}

class ImagenesFalsas extends ImagenesOffline {
  bool falla = false;
  @override
  Future<void> preparar(
    Iterable<String> urls, {
    void Function(int, int)? progreso,
  }) async {
    if (falla) throw StateError('Corte de imagen');
  }
}

void main() {
  sqfliteFfiInit();
  late BaseLocal base;
  late CatalogoLocalDao dao;
  late ApiInstantaneaFalsa api;
  late ImagenesFalsas imagenes;
  setUp(() async {
    base = BaseLocal(fabrica: databaseFactoryFfi, ruta: inMemoryDatabasePath);
    dao = CatalogoLocalDao(base);
    api = ApiInstantaneaFalsa();
    imagenes = ImagenesFalsas();
    await dao.guardar(instantanea(), 'b1', usuarioId: 'u1');
  });
  tearDown(() => base.cerrar());
  test('otro usuario/empresa o visitante nunca ve catálogo previo', () async {
    for (final u in [
      usuarioOffline(id: 'u2'),
      usuarioOffline(tenant: 'tenant-b'),
      null,
    ]) {
      final c = CatalogoOfflineController(dao, api, imagenes, u);
      await c.iniciar();
      expect(c.state.datos.productos, isEmpty);
      expect(c.state.version, isNull);
      c.dispose();
    }
  });
  test('fallo al precargar imágenes conserva instantánea anterior', () async {
    final c = CatalogoOfflineController(dao, api, imagenes, usuarioOffline());
    addTearDown(c.dispose);
    await c.iniciar();
    imagenes.falla = true;
    await c.descargar();
    expect(c.state.version, '2026-10-23T12:00:00Z');
    expect(c.state.error, contains('La descarga se interrumpió'));
    expect((await dao.meta()).version, '2026-10-23T12:00:00Z');
  });
  test('bloquea descarga suspendida pero mantiene consulta', () async {
    final c = CatalogoOfflineController(
      dao,
      api,
      imagenes,
      usuarioOffline(estado: 'SUSPENDIDA'),
    );
    addTearDown(c.dispose);
    await c.iniciar();
    await c.descargar();
    expect(c.state.datos.productos, hasLength(2));
    expect(api.llamadas, 0);
    expect(c.state.error, contains('suscripción'));
  });
}
