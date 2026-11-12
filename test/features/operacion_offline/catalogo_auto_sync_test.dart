import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:mobile_marketplace_moda/core/network/api_client.dart';
import 'package:mobile_marketplace_moda/core/offline/base_local.dart';
import 'package:mobile_marketplace_moda/features/operacion_offline/application/catalogo_offline_controller.dart';
import 'package:mobile_marketplace_moda/features/operacion_offline/application/catalogo_auto_sync.dart';
import 'package:mobile_marketplace_moda/features/operacion_offline/domain/catalogo_local.dart';
import 'package:mobile_marketplace_moda/features/operacion_offline/infrastructure/catalogo_local_dao.dart';
import 'package:mobile_marketplace_moda/features/operacion_offline/infrastructure/instantanea_api.dart';
import 'package:mobile_marketplace_moda/features/operacion_offline/infrastructure/imagenes_offline.dart';
import 'fixtures.dart';

class ApiInstantaneaFalsa extends InstantaneaApi {
  ApiInstantaneaFalsa() : super(ApiClient());
  int llamadas = 0;
  String? ultimoDesde;
  InstantaneaCatalogo? respuesta = instantanea(version: '2026-10-24T12:00:00Z');
  Object? error;

  @override
  Future<InstantaneaCatalogo> obtener({
    String? sucursalId,
    String? desde,
  }) async {
    llamadas++;
    ultimoDesde = desde;
    if (error != null) throw error!;
    return respuesta ?? instantanea(version: '2026-10-24T12:00:00Z');
  }
}

class ImagenesFalsas extends ImagenesOffline {
  int llamadas = 0;
  bool falla = false;

  @override
  Future<void> preparar(
    Iterable<String> urls, {
    void Function(int, int)? progreso,
  }) async {
    llamadas++;
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
  });

  tearDown(() => base.cerrar());

  test('Inicio de sesión con red (datos móviles) -> descarga completa sin abrir ninguna pantalla sin conexión', () async {
    final user = usuarioOffline();
    final controller = CatalogoOfflineController(dao, api, imagenes, user);
    addTearDown(controller.dispose);
    final autoSync = CatalogoAutoSync(
      controller: controller,
      dao: dao,
      online: true,
      usuario: user,
      esWifi: false,
    );
    await autoSync.notificar('login');
    expect(api.llamadas, 1);
    expect(api.ultimoDesde, isNull);
  });

  test('Reconexión con versión local de hace 6 min -> descarga incremental', () async {
    final user = usuarioOffline();
    await dao.guardar(instantanea(version: 'v-anterior'), 'b1', usuarioId: user.id);
    await dao.base.guardarMeta('descargado_en', DateTime.now().subtract(const Duration(minutes: 6)).toIso8601String());

    final controller = CatalogoOfflineController(dao, api, imagenes, user);
    addTearDown(controller.dispose);
    await controller.iniciar();

    final autoSync = CatalogoAutoSync(
      controller: controller,
      dao: dao,
      online: true,
      usuario: user,
      esWifi: false,
    );
    await autoSync.notificar('reconnect');
    expect(api.llamadas, 1);
    expect(api.ultimoDesde, 'v-anterior');
  });

  test('Vuelta a primer plano con versión de hace 30 s -> no descarga', () async {
    final user = usuarioOffline();
    await dao.guardar(instantanea(version: 'v-reciente'), 'b1', usuarioId: user.id);
    await dao.base.guardarMeta('descargado_en', DateTime.now().subtract(const Duration(seconds: 30)).toIso8601String());

    final controller = CatalogoOfflineController(dao, api, imagenes, user);
    addTearDown(controller.dispose);
    await controller.iniciar();

    final autoSync = CatalogoAutoSync(
      controller: controller,
      dao: dao,
      online: true,
      usuario: user,
      esWifi: false,
    );
    await autoSync.notificar('foreground');
    expect(api.llamadas, 0);
  });

  test('Sincronización con confirmadas > 0 -> descarga', () async {
    final user = usuarioOffline();
    await dao.guardar(instantanea(version: 'v-sync'), 'b1', usuarioId: user.id);
    await dao.base.guardarMeta('descargado_en', DateTime.now().toIso8601String());

    final controller = CatalogoOfflineController(dao, api, imagenes, user);
    addTearDown(controller.dispose);
    await controller.iniciar();

    final autoSync = CatalogoAutoSync(
      controller: controller,
      dao: dao,
      online: true,
      usuario: user,
      esWifi: false,
    );
    await autoSync.notificar('sync_confirmed');
    expect(api.llamadas, 1);
  });

  test('Sin Wi-Fi y sin preferencia -> no descarga imágenes; con imagenes_con_datos=\'true\' -> sí', () async {
    final user = usuarioOffline();
    final controller = CatalogoOfflineController(dao, api, imagenes, user);
    addTearDown(controller.dispose);

    final autoSync1 = CatalogoAutoSync(
      controller: controller,
      dao: dao,
      online: true,
      usuario: user,
      esWifi: false,
    );
    await autoSync1.notificar('manual');
    expect(imagenes.llamadas, 0);

    await dao.base.guardarMeta('imagenes_con_datos', 'true');
    final autoSync2 = CatalogoAutoSync(
      controller: controller,
      dao: dao,
      online: true,
      usuario: user,
      esWifi: false,
    );
    await autoSync2.notificar('manual');
    expect(imagenes.llamadas, greaterThanOrEqualTo(1));
  });

  test('Sesión sin conexión o suscripción sin módulo -> no descarga', () async {
    final userSinModulo = usuarioOffline(estado: 'SUSPENDIDA');
    final controller = CatalogoOfflineController(dao, api, imagenes, userSinModulo);
    addTearDown(controller.dispose);

    final autoSyncOffline = CatalogoAutoSync(
      controller: controller,
      dao: dao,
      online: false,
      usuario: usuarioOffline(),
    );
    await autoSyncOffline.notificar('login');
    expect(api.llamadas, 0);

    final autoSyncSinModulo = CatalogoAutoSync(
      controller: controller,
      dao: dao,
      online: true,
      usuario: userSinModulo,
    );
    await autoSyncSinModulo.notificar('login');
    expect(api.llamadas, 0);
  });

  test('instantanea_sin_sucursales -> conserva los datos previos y expone el mensaje', () async {
    final user = usuarioOffline();
    await dao.guardar(instantanea(version: 'v-previa'), 'b1', usuarioId: user.id);

    final controller = CatalogoOfflineController(dao, api, imagenes, user);
    addTearDown(controller.dispose);
    await controller.iniciar();

    api.error = StateError('Tu usuario no tiene sucursales asignadas. Pedile al administrador que te asigne una.');

    final autoSync = CatalogoAutoSync(
      controller: controller,
      dao: dao,
      online: true,
      usuario: user,
      esWifi: true,
    );
    await autoSync.notificar('manual');

    expect(controller.state.datos.productos, hasLength(2));
    expect(controller.state.error, contains('Tu usuario no tiene sucursales asignadas'));
  });

  test('Dos eventos seguidos -> una sola descarga', () async {
    final user = usuarioOffline();
    final controller = CatalogoOfflineController(dao, api, imagenes, user);
    addTearDown(controller.dispose);

    final autoSync = CatalogoAutoSync(
      controller: controller,
      dao: dao,
      online: true,
      usuario: user,
      esWifi: true,
    );

    final f1 = autoSync.notificar('event1');
    final f2 = autoSync.notificar('event2');
    await Future.wait([f1, f2]);

    expect(api.llamadas, 1);
  });
}
