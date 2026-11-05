import 'dart:convert';
import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:mobile_marketplace_moda/core/offline/base_local.dart';
import 'package:mobile_marketplace_moda/core/offline/conectividad.dart';
import 'package:mobile_marketplace_moda/core/offline/esquema_local.dart';
import 'package:mobile_marketplace_moda/features/usuarios_catalogo/domain/usuario.dart';
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

  test('v2 activa claves foráneas y rechaza documentos huérfanos', () async {
    final db = await base.abrir();
    expect((await db.rawQuery('PRAGMA foreign_keys')).first.values.single, 1);
    final fk = await db.rawQuery('PRAGMA foreign_key_list(ventas_locales)');
    expect(fk.single['table'], 'cajas');
    expect(fk.single['on_delete'], 'RESTRICT');
    expect(
      (await db.rawQuery(
        'PRAGMA foreign_key_list(operaciones_pendientes)',
      )).length,
      2,
    );
    await expectLater(
      db.insert('venta_items_locales', {
        'venta_id': 'ausente',
        'variante_id': 'v1',
        'producto_nombre': 'Prenda',
        'variante_desc': 'M',
        'cantidad': 1,
        'precio_unitario': 10,
        'precio_regular': 10,
        'total_linea': 10,
      }),
      throwsA(isA<DatabaseException>()),
    );
    final indexes = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='index'",
    );
    expect(
      indexes.map((r) => r['name']),
      containsAll(['ix_variantes_sku', 'ix_operaciones_estado']),
    );
  });

  test(
    'v1 a v2 conserva reserva y cola con backfill sin JSON SQL y tras reabrir',
    () async {
      final directorio = await Directory.systemTemp.createTemp(
        'fashionstore-v03-',
      );
      final ruta = '${directorio.path}/migracion.db';
      final reservaId = reserva().id;
      try {
        final anterior = await databaseFactoryFfi.openDatabase(
          ruta,
          options: OpenDatabaseOptions(
            version: 1,
            onCreate: EsquemaLocal.crear,
          ),
        );
        await anterior.insert('reservas_locales', reserva().aFila());
        await anterior.insert('operaciones_pendientes', {
          'id': 'op-v1',
          'tipo': 'RESERVA',
          'estado': 'PENDIENTE',
          'tenant_id': 'tenant-a',
          'sucursal_id': 'b1',
          'usuario_id': 'u1',
          'dispositivo_id': 'd1',
          'payload': jsonEncode({'client_key': reservaId}),
          'creada_en': '2026-11-04',
          'actualizada_en': '2026-11-04',
        });
        await anterior.close();
        final migrada = BaseLocal(fabrica: databaseFactoryFfi, ruta: ruta);
        final db = await migrada.abrir();
        expect(await db.getVersion(), 2);
        expect(
          (await db.query('operaciones_pendientes')).single['reserva_id'],
          reservaId,
        );
        expect(await db.query('reservas_locales'), hasLength(1));
        await migrada.cerrar();
        final reabierta = await migrada.abrir();
        expect(
          (await reabierta.query(
            'operaciones_pendientes',
          )).single['reserva_id'],
          reservaId,
        );
        await migrada.cerrar();
      } finally {
        await directorio.delete(recursive: true);
      }
    },
  );

  test('repara v2 preliminar vacía sin perder meta o cola legacy', () async {
    final directorio = await Directory.systemTemp.createTemp(
      'fashionstore-v03-',
    );
    final ruta = '${directorio.path}/preliminar.db';
    try {
      final anterior = await databaseFactoryFfi.openDatabase(
        ruta,
        options: OpenDatabaseOptions(
          version: 2,
          onCreate: (db, _) => EsquemaLocal.crear(db, 1),
        ),
      );
      await anterior.insert('meta', {
        'clave': 'dispositivo_id',
        'valor': 'conservado',
      });
      await anterior.close();
      final reparada = BaseLocal(fabrica: databaseFactoryFfi, ruta: ruta);
      final db = await reparada.abrir();
      expect(await reparada.leerMeta('dispositivo_id'), 'conservado');
      expect(await db.query('ventas_locales'), isEmpty);
      expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
      await reparada.cerrar();
    } finally {
      await directorio.delete(recursive: true);
    }
  });

  test(
    'venta v2 incompatible aborta y revierte reparación sin inventar caja o fecha',
    () async {
      final directorio = await Directory.systemTemp.createTemp(
        'fashionstore-v03-',
      );
      final ruta = '${directorio.path}/incompatible.db';
      try {
        final anterior = await databaseFactoryFfi.openDatabase(
          ruta,
          options: OpenDatabaseOptions(
            version: 2,
            onCreate: (db, _) async {
              await EsquemaLocal.crear(db, 1);
              await db.execute(
                'CREATE TABLE ventas_locales (id TEXT PRIMARY KEY, caja_id TEXT)',
              );
              await db.insert('ventas_locales', {
                'id': 'documento-original',
                'caja_id': null,
              });
            },
          ),
        );
        await anterior.close();
        final reparada = BaseLocal(fabrica: databaseFactoryFfi, ruta: ruta);
        await expectLater(reparada.abrir(), throwsStateError);
        final intacta = await databaseFactoryFfi.openDatabase(ruta);
        expect(
          (await intacta.query('ventas_locales')).single['id'],
          'documento-original',
        );
        expect(
          await intacta.rawQuery(
            "SELECT name FROM sqlite_master WHERE type='table' AND name='cajas'",
          ),
          isEmpty,
        );
        expect(
          (await intacta.rawQuery(
            'PRAGMA table_info(operaciones_pendientes)',
          )).map((r) => r['name']),
          isNot(contains('venta_id')),
        );
        await intacta.close();
      } finally {
        await directorio.delete(recursive: true);
      }
    },
  );

  test(
    'sucursales autorizadas sobreviven perfil offline y ausencia no concede alcance',
    () {
      final perfil = usuarioOffline().aJson();
      perfil['authorized_branches'] = [
        {'id': 'b1', 'code': 'CENTRO', 'name': 'Centro', 'is_default': true},
      ];
      final usuario = Usuario.desdeJson(perfil);
      expect(usuario.sucursalesAutorizadas.single.predeterminada, true);
      expect(
        Usuario.desdeJson(usuario.aJson()).sucursalesAutorizadas.single.id,
        'b1',
      );
      perfil.remove('authorized_branches');
      expect(Usuario.desdeJson(perfil).sucursalesAutorizadas, isEmpty);
    },
  );
}
