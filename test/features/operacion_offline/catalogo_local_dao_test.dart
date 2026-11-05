import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:mobile_marketplace_moda/core/offline/base_local.dart';
import 'package:mobile_marketplace_moda/features/operacion_offline/domain/catalogo_local.dart';
import 'package:mobile_marketplace_moda/features/operacion_offline/infrastructure/catalogo_local_dao.dart';
import 'package:mobile_marketplace_moda/features/operacion_offline/infrastructure/reservas_locales_dao.dart';
import 'fixtures.dart';

void main() {
  sqfliteFfiInit();
  late BaseLocal base;
  late CatalogoLocalDao dao;
  setUp(() async {
    base = BaseLocal(fabrica: databaseFactoryFfi, ruta: inMemoryDatabasePath);
    dao = CatalogoLocalDao(base);
    await dao.guardar(instantanea(), 'b1', usuarioId: 'u1');
  });
  tearDown(() => base.cerrar());
  test('guarda y lee datos con stock por sucursal y conteos', () async {
    final datos = await dao.leer('b1');
    expect(datos.productos, hasLength(2));
    expect(datos.stock('v1'), 4);
    expect((await dao.leer('b2')).stock('v1'), 8);
    expect(await dao.conteos(), {
      'productos': 2,
      'variantes': 5,
      'clientes': 1,
    });
    expect((await dao.meta()).usuarioId, 'u1');
  });
  test('fallo en descarga revierte las eliminaciones y la versión', () async {
    await expectLater(
      dao.guardar(
        instantanea(version: '2026-10-24T12:00:00Z', stock: -1),
        'b1',
        usuarioId: 'u1',
      ),
      throwsA(anything),
    );
    expect((await dao.meta()).version, '2026-10-23T12:00:00Z');
    expect((await dao.leer('b1')).stock('v1'), 4);
  });
  test(
    'instantánea nueva conserva cola y descuenta una vez la reserva pendiente',
    () async {
      final reservas = ReservasLocalesDao(
        base,
        tenantId: 'tenant-a',
        usuarioId: 'u1',
      );
      final r = reserva();
      final items = itemsPara(r);
      await reservas.registrar(r, items, operacion(r, items));
      expect((await dao.leer('b1')).stock('v1'), 2);
      await dao.guardar(instantanea(stock: 5), 'b1', usuarioId: 'u1');
      expect((await dao.leer('b1')).stock('v1'), 3);
      await dao.guardar(instantanea(stock: 5), 'b1', usuarioId: 'u1');
      expect((await dao.leer('b1')).stock('v1'), 3);
      expect(await reservas.listar(), hasLength(1));
      await reservas.cancelar(r.id);
      expect((await dao.leer('b1')).stock('v1'), 5);
    },
  );
  test('cambio de empresa exige full y no altera su cola previa', () async {
    final reservas = ReservasLocalesDao(
      base,
      tenantId: 'tenant-a',
      usuarioId: 'u1',
    );
    final r = reserva();
    final items = itemsPara(r);
    await reservas.registrar(r, items, operacion(r, items));
    await expectLater(
      dao.guardar(
        instantanea(tenant: 'tenant-b', full: false),
        'b1',
        usuarioId: 'u2',
      ),
      throwsStateError,
    );
    await dao.guardar(
      instantanea(tenant: 'tenant-b', stock: 9),
      'b1',
      usuarioId: 'u2',
    );
    expect((await dao.leer('b1')).stock('v1'), 9);
    expect((await dao.meta()).tenantId, 'tenant-b');
    await reservas.cancelar(r.id);
    expect((await dao.leer('b1')).stock('v1'), 9);
  });

  InstantaneaCatalogo conCajas({
    bool incluir = true,
    int stock = 4,
    String version = '2026-11-04T12:00:00Z',
  }) {
    final json = snapshotJson(stock: stock, version: version);
    json['cash_points'] = incluir
        ? [
            {
              'id': 'cj1',
              'branch_id': 'b1',
              'code': 'CENTRO-1',
              'name': 'Caja centro',
            },
            {
              'id': 'cj2',
              'branch_id': 'b2',
              'code': 'NORTE-1',
              'name': 'Caja norte',
            },
          ]
        : [];
    json['price_valid_until'] = '2026-11-05T12:00:00Z';
    return InstantaneaCatalogo.desdeJson(json);
  }

  Future<void> ventaHistorica() async {
    await (await base.abrir()).insert('ventas_locales', {
      'id': 'venta1',
      'folio': 'OFF-CJ1-0001',
      'tenant_id': 'tenant-a',
      'sucursal_id': 'b1',
      'caja_id': 'cj1',
      'usuario_id': 'u1',
      'subtotal': 10,
      'descuento': 0,
      'total': 10,
      'recibido': 10,
      'vuelto': 0,
      'forma_pago': 'EFECTIVO',
      'estado': 'PENDIENTE_SINCRONIZAR',
      'catalogo_descargado_en': '2026-11-04T12:00:00Z',
      'creada_en': '2026-11-04T12:30:00Z',
    });
  }

  test(
    'cajas por sucursal y vigencia se confirman con la instantánea',
    () async {
      await dao.guardar(conCajas(), 'b1', usuarioId: 'u1');
      expect((await dao.cajas('b1')).single.id, 'cj1');
      expect((await dao.cajas('b2')).single.id, 'cj2');
      expect(
        (await dao.meta()).precioVigenteHasta,
        DateTime.utc(2026, 11, 5, 12),
      );
      await dao.guardar(instantanea(), 'b1', usuarioId: 'u1');
      expect((await dao.meta()).precioVigenteHasta, isNull);
      expect(await dao.cajas('b1'), isEmpty);
    },
  );

  test(
    'una caja con venta se conserva inactiva y actualizarla no rompe su FK',
    () async {
      await dao.guardar(conCajas(), 'b1', usuarioId: 'u1');
      await ventaHistorica();
      await dao.guardar(conCajas(incluir: false), 'b1', usuarioId: 'u1');
      expect(await dao.cajas('b1'), isEmpty);
      final db = await base.abrir();
      expect((await db.query('cajas')).single['activa'], 0);
      expect(await db.query('ventas_locales'), hasLength(1));
      await expectLater(
        db.delete('cajas', where: 'id = ?', whereArgs: ['cj1']),
        throwsA(isA<DatabaseException>()),
      );
      await dao.guardar(conCajas(), 'b1', usuarioId: 'u1');
      expect((await dao.cajas('b1')).single.activa, true);
      expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
      await expectLater(
        db.insert('venta_items_locales', {
          'venta_id': 'venta1',
          'variante_id': 'v1',
          'producto_nombre': 'Prenda',
          'variante_desc': 'M',
          'cantidad': 0,
          'precio_unitario': 10,
          'precio_regular': 10,
          'total_linea': 0,
        }),
        throwsA(isA<DatabaseException>()),
      );
    },
  );

  test(
    'fallo de stock revierte cajas y metadatos junto con el catálogo',
    () async {
      await dao.guardar(conCajas(), 'b1', usuarioId: 'u1');
      await expectLater(
        dao.guardar(
          conCajas(incluir: false, stock: -1, version: '2026-11-05T12:00:00Z'),
          'b1',
          usuarioId: 'u1',
        ),
        throwsA(anything),
      );
      expect((await dao.cajas('b1')).single.id, 'cj1');
      expect((await dao.meta()).version, '2026-11-04T12:00:00Z');
    },
  );

  test('no admite una caja de una sucursal fuera de la instantánea', () async {
    final json = snapshotJson();
    json['cash_points'] = [
      {'id': 'c-ajena', 'branch_id': 'b-ajena', 'code': 'X', 'name': 'Ajena'},
    ];
    await expectLater(
      dao.guardar(InstantaneaCatalogo.desdeJson(json), 'b1', usuarioId: 'u1'),
      throwsStateError,
    );
    expect(await dao.cajas('b-ajena'), isEmpty);
  });
}
