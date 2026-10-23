import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:mobile_marketplace_moda/core/offline/base_local.dart';
import 'package:mobile_marketplace_moda/core/offline/conectividad.dart';
import '../../features/operacion_offline/fixtures.dart';

void main() {
  sqfliteFfiInit();
  late BaseLocal base;
  setUp(
    () => base = BaseLocal(
      fabrica: databaseFactoryFfi,
      ruta: inMemoryDatabasePath,
    ),
  );
  tearDown(() => base.cerrar());
  test('crea las nueve tablas del contrato y memoiza abrir', () async {
    final db = await base.abrir();
    expect(identical(db, await base.abrir()), true);
    final tablas = (await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table'",
    )).map((f) => f['name']).toSet();
    expect(
      tablas,
      containsAll([
        'productos',
        'variantes',
        'existencias',
        'sucursales',
        'clientes',
        'meta',
        'reservas_locales',
        'reserva_items_locales',
        'operaciones_pendientes',
      ]),
    );
  });
  test(
    'dispositivoId es UUID v4 estable incluso con llamadas concurrentes',
    () async {
      final ids = await Future.wait(
        List.generate(5, (_) => base.dispositivoId()),
      );
      expect(ids.toSet(), hasLength(1));
      expect(
        ids.first,
        matches(
          RegExp(
            r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
          ),
        ),
      );
    },
  );
  test('conectividad distingue ninguna, wifi y combinaciones', () {
    expect(hayConexion([ConnectivityResult.none]), false);
    expect(hayConexion([ConnectivityResult.wifi]), true);
    expect(
      hayConexion([ConnectivityResult.none, ConnectivityResult.mobile]),
      true,
    );
    expect(hayConexion([]), false);
  });
  test('Usuario recibe tenant y subscription de auth/me', () {
    final u = usuarioOffline();
    expect(u.empresa!.slug, 'tenant-a');
    expect(u.suscripcion!.codigoPlan, 'BASICO');
    expect(u.suscripcion!.limites['max_active_branches'], 2);
    expect(u.aJson().keys, isNot(contains('refresh_token')));
  });
}
