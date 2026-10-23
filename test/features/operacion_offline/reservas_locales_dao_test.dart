import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:mobile_marketplace_moda/core/offline/base_local.dart';
import 'package:mobile_marketplace_moda/features/operacion_offline/domain/reserva_local.dart';
import 'package:mobile_marketplace_moda/features/operacion_offline/infrastructure/catalogo_local_dao.dart';
import 'package:mobile_marketplace_moda/features/operacion_offline/infrastructure/reservas_locales_dao.dart';
import 'fixtures.dart';

void main() {
  sqfliteFfiInit();
  late BaseLocal base;
  late ReservasLocalesDao dao;
  late CatalogoLocalDao catalogo;
  setUp(() async {
    base = BaseLocal(fabrica: databaseFactoryFfi, ruta: inMemoryDatabasePath);
    dao = ReservasLocalesDao(base, tenantId: 'tenant-a', usuarioId: 'u1');
    catalogo = CatalogoLocalDao(base);
    await catalogo.guardar(instantanea(), 'b1', usuarioId: 'u1');
  });
  tearDown(() => base.cerrar());
  test(
    'registra en tres tablas, descuenta stock y cancela exactamente una vez',
    () async {
      final r = reserva();
      final items = itemsPara(r);
      final op = operacion(r, items);
      await dao.registrar(r, items, op);
      expect((await catalogo.leer('b1')).stock('v1'), 2);
      expect(
        (await dao.obtener(r.id))!.operacion.estado,
        EstadoOperacion.pendiente,
      );
      await expectLater(dao.registrar(r, items, op), throwsA(anything));
      expect((await catalogo.leer('b1')).stock('v1'), 2);
      await dao.cancelar(r.id);
      expect((await catalogo.leer('b1')).stock('v1'), 4);
      expect(
        (await dao.obtener(r.id))!.reserva.estado,
        EstadoReservaLocal.anuladaLocal,
      );
      expect(
        (await dao.obtener(r.id))!.operacion.estado,
        EstadoOperacion.anulada,
      );
      await expectLater(dao.cancelar(r.id), throwsStateError);
      expect((await catalogo.leer('b1')).stock('v1'), 4);
    },
  );
  test(
    'falla de segundo ítem revierte reserva, operación y primer descuento',
    () async {
      final r = reserva();
      final items = [
        ...itemsPara(r),
        ItemReservaLocal(reservaId: r.id, varianteId: 'v2', cantidad: 2),
      ];
      await expectLater(
        dao.registrar(r, items, operacion(r, items)),
        throwsStateError,
      );
      expect(await dao.listar(), isEmpty);
      expect((await catalogo.leer('b1')).stock('v1'), 4);
      final db = await base.abrir();
      expect(await db.query('reserva_items_locales'), isEmpty);
      expect(await db.query('operaciones_pendientes'), isEmpty);
    },
  );
  test('DAO rechaza 11 unidades aunque hay 100 de stock', () async {
    await catalogo.guardar(instantanea(stock: 100), 'b1', usuarioId: 'u1');
    final r = reserva();
    final items = itemsPara(r, cantidad: 11);
    await expectLater(
      dao.registrar(r, items, operacion(r, items)),
      throwsStateError,
    );
    expect((await catalogo.leer('b1')).stock('v1'), 100);
  });
  test('no permite cancelar confirmada ni consultar reservas ajenas', () async {
    final r = reserva();
    final items = itemsPara(r);
    final op = operacion(r, items);
    await dao.registrar(r, items, op);
    final otro = ReservasLocalesDao(
      base,
      tenantId: 'tenant-a',
      usuarioId: 'u2',
    );
    expect(await otro.listar(), isEmpty);
    expect(await otro.obtener(r.id), isNull);
    await expectLater(otro.cancelar(r.id), throwsStateError);
    final otraEmpresa = ReservasLocalesDao(
      base,
      tenantId: 'tenant-b',
      usuarioId: 'u1',
    );
    expect(await otraEmpresa.obtener(r.id), isNull);
    await (await base.abrir()).update(
      'operaciones_pendientes',
      {'estado': 'CONFIRMADA'},
      where: 'id = ?',
      whereArgs: [op.id],
    );
    await expectLater(dao.cancelar(r.id), throwsStateError);
    expect((await catalogo.leer('b1')).stock('v1'), 2);
  });
  test('dos reservas simultáneas no pueden consumir el mismo stock', () async {
    final a = reserva(id: 'aaaaaaaa-1111-4444-8888-111111111111');
    final b = reserva(id: 'bbbbbbbb-1111-4444-8888-111111111111');
    final resultados = await Future.wait(
      [a, b].map((r) async {
        final items = itemsPara(r, cantidad: 3);
        try {
          await dao.registrar(r, items, operacion(r, items));
          return true;
        } catch (_) {
          return false;
        }
      }),
    );
    expect(resultados.where((e) => e), hasLength(1));
    expect((await catalogo.leer('b1')).stock('v1'), 1);
  });
  test('cerrar y reabrir archivo conserva reserva y cola', () async {
    final carpeta = await Directory.systemTemp.createTemp(
      'fashionstore-offline-test-',
    );
    final ruta = path.join(carpeta.path, 'offline.db');
    var archivo = BaseLocal(fabrica: databaseFactoryFfi, ruta: ruta);
    try {
      await CatalogoLocalDao(
        archivo,
      ).guardar(instantanea(), 'b1', usuarioId: 'u1');
      var persistente = ReservasLocalesDao(
        archivo,
        tenantId: 'tenant-a',
        usuarioId: 'u1',
      );
      final r = reserva();
      final items = itemsPara(r);
      await persistente.registrar(r, items, operacion(r, items));
      await archivo.cerrar();
      archivo = BaseLocal(fabrica: databaseFactoryFfi, ruta: ruta);
      persistente = ReservasLocalesDao(
        archivo,
        tenantId: 'tenant-a',
        usuarioId: 'u1',
      );
      expect((await persistente.obtener(r.id))!.unidades, 2);
      expect((await CatalogoLocalDao(archivo).leer('b1')).stock('v1'), 2);
      await persistente.cancelar(r.id);
      expect((await CatalogoLocalDao(archivo).leer('b1')).stock('v1'), 4);
    } finally {
      await archivo.cerrar();
      await carpeta.delete(recursive: true);
    }
  });
}
