import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:mobile_marketplace_moda/core/offline/base_local.dart';
import 'package:mobile_marketplace_moda/features/usuarios_catalogo/domain/usuario.dart';
import 'package:mobile_marketplace_moda/features/operacion_offline/domain/catalogo_local.dart';
import 'package:mobile_marketplace_moda/features/operacion_offline/domain/sincronizacion.dart';
import 'package:mobile_marketplace_moda/features/operacion_offline/infrastructure/catalogo_local_dao.dart';
import 'package:mobile_marketplace_moda/features/operacion_offline/infrastructure/operaciones_dao.dart';
import 'package:mobile_marketplace_moda/features/operacion_offline/infrastructure/ventas_locales_dao.dart';
import 'fixtures.dart';

void main() {
  sqfliteFfiInit();
  late BaseLocal base;
  late Usuario user;
  late Directory carpeta;
  late String ruta;
  setUp(() async {
    carpeta = await Directory.systemTemp.createTemp('fs-qa-venta-');
    ruta = '${carpeta.path}${Platform.pathSeparator}qa.db';
    base = BaseLocal(fabrica: databaseFactoryFfi, ruta: ruta);
    final snapshot = snapshotJson();
    snapshot['cash_points'] = [
      {'id': 'cash-1', 'branch_id': 'b1', 'code': 'C1', 'name': 'Caja Centro'},
    ];
    snapshot['price_valid_until'] = DateTime.now()
        .add(const Duration(hours: 1))
        .toUtc()
        .toIso8601String();
    await CatalogoLocalDao(
      base,
    ).guardar(InstantaneaCatalogo.desdeJson(snapshot), 'b1', usuarioId: 'u1');
    await base.guardarMeta('usuario_id', 'u1');
    user = Usuario.desdeJson({
      'id': 'u1',
      'email': 'qa@example.test',
      'first_name': 'Operador',
      'last_name': 'Prueba',
      'roles': [
        {
          'permissions': ['commerce.write', 'sync.write'],
        },
      ],
      'tenant': {
        'id': 'tenant-a',
        'slug': 'tenant-a',
        'trade_name': 'Moda',
        'status': 'ACTIVA',
      },
      'subscription': {
        'plan_code': 'BASICO',
        'plan_name': 'Básico',
        'status': 'ACTIVA',
        'end_date': '2030-12-31',
        'features': {'offline': true, 'sales': true},
      },
    });
  });
  tearDown(() async {
    await base.cerrar();
    if (await File(ruta).exists()) await File(ruta).delete();
    await carpeta.delete();
  });

  test(
    'venta persiste con su cola y sincroniza el mismo identificador',
    () async {
      final venta = await VentasLocalesDao(base).registrar(
        usuario: user,
        cajaId: 'cash-1',
        cantidades: {'v1': 2},
        recibido: 700,
      );
      await base.cerrar();
      final dao = OperacionesDao(base);
      final pending = await dao.tomarParaEnvio(
        tenantId: 'tenant-a',
        usuarioId: 'u1',
      );
      expect(pending.single.id, venta['id']);
      expect(pending.single.payload['total'], '640.00');
      final db = await base.abrir();
      expect(
        (await db.query(
          'existencias',
          where: 'variante_id=? AND sucursal_id=?',
          whereArgs: ['v1', 'b1'],
        )).single['cantidad'],
        2,
      );
      await dao.aplicarResultados([
        SyncResult(
          clientRequestId: venta['id'] as String,
          status: 'CONFIRMED',
          message: 'OK',
          serverRef: 'server-sale',
          serverNumber: 'FS-QA',
        ),
      ]);
      expect((await db.query('ventas_locales')).single['estado'], 'CONFIRMADA');
      expect(
        (await dao.listarTodas('tenant-a', 'u1')).single['server_numero'],
        'FS-QA',
      );
      expect(await dao.listarTodas('tenant-b', 'u1'), isEmpty);
    },
  );

  test('stock insuficiente revierte venta, cola y existencias', () async {
    await expectLater(
      VentasLocalesDao(base).registrar(
        usuario: user,
        cajaId: 'cash-1',
        cantidades: {'v1': 5},
        recibido: 2000,
      ),
      throwsStateError,
    );
    final db = await base.abrir();
    expect(await db.query('ventas_locales'), isEmpty);
    expect(await db.query('operaciones_pendientes'), isEmpty);
    expect(
      (await db.query(
        'existencias',
        where: 'variante_id=? AND sucursal_id=?',
        whereArgs: ['v1', 'b1'],
      )).single['cantidad'],
      4,
    );
  });

  group('CU-18 cliente opcional', () {
    test('guarda el cliente local y lo envía como customer_id', () async {
      final venta = await VentasLocalesDao(base).registrar(
        usuario: user,
        cajaId: 'cash-1',
        cantidades: {'v1': 1},
        recibido: 500,
        clienteId: 'c1',
      );
      expect(venta['cliente_id'], 'c1');
      expect(venta['cliente_nombre'], 'Ana Perez');
      final db = await base.abrir();
      final fila = (await db.query('ventas_locales')).single;
      expect(fila['cliente_id'], 'c1');
      expect(fila['cliente_nombre'], 'Ana Perez');
      final pending = await OperacionesDao(
        base,
      ).tomarParaEnvio(tenantId: 'tenant-a', usuarioId: 'u1');
      expect(pending.single.payload['customer_id'], 'c1');
    });

    test('sin cliente la venta sigue igual y customer_id va nulo', () async {
      await VentasLocalesDao(base).registrar(
        usuario: user,
        cajaId: 'cash-1',
        cantidades: {'v1': 1},
        recibido: 500,
      );
      final db = await base.abrir();
      final fila = (await db.query('ventas_locales')).single;
      expect(fila['cliente_id'], isNull);
      expect(fila['cliente_nombre'], isNull);
      final pending = await OperacionesDao(
        base,
      ).tomarParaEnvio(tenantId: 'tenant-a', usuarioId: 'u1');
      expect(pending.single.payload.containsKey('customer_id'), isTrue);
      expect(pending.single.payload['customer_id'], isNull);
    });

    test('cliente ajeno al catálogo local revierte toda la venta', () async {
      await expectLater(
        VentasLocalesDao(base).registrar(
          usuario: user,
          cajaId: 'cash-1',
          cantidades: {'v1': 1},
          recibido: 500,
          clienteId: 'cliente-de-otra-empresa',
        ),
        throwsStateError,
      );
      final db = await base.abrir();
      expect(await db.query('ventas_locales'), isEmpty);
      expect(await db.query('operaciones_pendientes'), isEmpty);
      expect(
        (await db.query(
          'existencias',
          where: 'variante_id=? AND sucursal_id=?',
          whereArgs: ['v1', 'b1'],
        )).single['cantidad'],
        4,
      );
    });
  });

  group('Validaciones de seguridad y estado de venta (MJ-02)', () {
    test('usuario sin commerce.write lanza error y nada queda guardado', () async {
      final userSinPermiso = Usuario.desdeJson({
        'id': 'u-sin-permiso',
        'email': 'sin@example.test',
        'first_name': 'Sin',
        'last_name': 'Permiso',
        'roles': [
          {
            'permissions': ['sync.write'],
          },
        ],
        'tenant': {
          'id': 'tenant-a',
          'slug': 'tenant-a',
          'trade_name': 'Moda',
          'status': 'ACTIVA',
        },
        'subscription': {
          'plan_code': 'BASICO',
          'plan_name': 'Básico',
          'status': 'ACTIVA',
          'end_date': '2030-12-31',
          'features': {'offline': true, 'sales': true},
        },
      });

      await expectLater(
        VentasLocalesDao(base).registrar(
          usuario: userSinPermiso,
          cajaId: 'cash-1',
          cantidades: {'v1': 1},
          recibido: 500,
        ),
        throwsA(isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('Tu cuenta o suscripción no permite registrar ventas.'),
        )),
      );

      final db = await base.abrir();
      expect(await db.query('ventas_locales'), isEmpty);
      expect(await db.query('operaciones_pendientes'), isEmpty);
    });

    test('sucursal sin cajas activas lanza error', () async {
      final db = await base.abrir();
      await db.delete('cajas');

      await expectLater(
        VentasLocalesDao(base).registrar(
          usuario: user,
          cajaId: 'cash-1',
          cantidades: {'v1': 1},
          recibido: 500,
        ),
        throwsA(isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('No hay una caja autorizada activa en esta sucursal.'),
        )),
      );
    });

    test('catálogo descargado por otro usuario lanza error', () async {
      final db = await base.abrir();
      await db.update('meta', {'valor': 'otro-usuario'}, where: 'clave=?', whereArgs: ['usuario_id']);

      await expectLater(
        VentasLocalesDao(base).registrar(
          usuario: user,
          cajaId: 'cash-1',
          cantidades: {'v1': 1},
          recibido: 500,
        ),
        throwsA(isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('Actualizá el catálogo de tu empresa antes de vender.'),
        )),
      );
    });

    test('sin fecha de vigencia de precios o vencida lanza error', () async {
      final db = await base.abrir();
      await db.delete('meta', where: 'clave=?', whereArgs: ['precio_vigente_hasta']);

      await expectLater(
        VentasLocalesDao(base).registrar(
          usuario: user,
          cajaId: 'cash-1',
          cantidades: {'v1': 1},
          recibido: 500,
        ),
        throwsA(isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('Actualizá el catálogo de tu empresa antes de vender.'),
        )),
      );

      await db.insert('meta', {
        'clave': 'precio_vigente_hasta',
        'valor': DateTime.now().subtract(const Duration(minutes: 5)).toUtc().toIso8601String(),
      });

      await expectLater(
        VentasLocalesDao(base).registrar(
          usuario: user,
          cajaId: 'cash-1',
          cantidades: {'v1': 1},
          recibido: 500,
        ),
        throwsA(isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('Actualizá el catálogo de tu empresa antes de vender.'),
        )),
      );
    });

    test('venta válida registra venta, líneas y operación PENDIENTE descontando stock en transacción', () async {
      final venta = await VentasLocalesDao(base).registrar(
        usuario: user,
        cajaId: 'cash-1',
        cantidades: {'v1': 2},
        recibido: 700,
      );

      final db = await base.abrir();
      final ventas = await db.query('ventas_locales', where: 'id=?', whereArgs: [venta['id']]);
      expect(ventas, hasLength(1));
      expect(ventas.single['estado'], 'PENDIENTE');

      final lineas = await db.query('lineas_venta_local', where: 'venta_id=?', whereArgs: [venta['id']]);
      expect(lineas, hasLength(1));
      expect(lineas.single['cantidad'], 2);

      final ops = await db.query('operaciones_pendientes', where: 'id=?', whereArgs: [venta['id']]);
      expect(ops, hasLength(1));
      expect(ops.single['estado'], 'PENDIENTE');

      final stock = (await db.query(
        'existencias',
        where: 'variante_id=? AND sucursal_id=?',
        whereArgs: ['v1', 'b1'],
      )).single['cantidad'];
      expect(stock, 2);
    });
  });
}
