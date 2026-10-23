import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:mobile_marketplace_moda/core/offline/base_local.dart';
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
}
