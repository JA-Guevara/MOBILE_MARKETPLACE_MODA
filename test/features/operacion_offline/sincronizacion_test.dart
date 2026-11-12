import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:mobile_marketplace_moda/core/offline/base_local.dart';
import 'package:mobile_marketplace_moda/features/operacion_offline/domain/reserva_local.dart';
import 'package:mobile_marketplace_moda/features/operacion_offline/domain/sincronizacion.dart';
import 'package:mobile_marketplace_moda/features/operacion_offline/infrastructure/operaciones_dao.dart';

void main() {
  sqfliteFfiInit();
  late BaseLocal base;
  late OperacionesDao dao;

  setUp(() async {
    base = BaseLocal(fabrica: databaseFactoryFfi, ruta: inMemoryDatabasePath);
    dao = OperacionesDao(base);
  });

  tearDown(() => base.cerrar());

  test('modelo de sincronizacion y backoff calculan correctamente', () {
    expect(backoffMs(0), 5000);
    expect(backoffMs(1), 10000);
    expect(backoffMs(2), 20000);
    expect(backoffMs(10), 300000);

    final lista = [1, 2, 3, 4, 5];
    final lotes = enLotes(lista, 2);
    expect(lotes.length, 3);
    expect(lotes[0], [1, 2]);
    expect(lotes[2], [5]);
  });

  test('dao lista pendientes y aplica resultados confirmados', () async {
    final db = await base.abrir();
    final op = OperacionPendiente(
      id: 'op-sync-1',
      tipo: 'VENTA',
      tenantId: 't1',
      sucursalId: 's1',
      usuarioId: 'u1',
      dispositivoId: 'd1',
      payload: {'client_request_id': 'op-sync-1'},
      creadaEn: DateTime.now(),
      actualizadaEn: DateTime.now(),
      estado: EstadoOperacion.pendiente,
    );

    await db.insert('operaciones_pendientes', op.aFila());

    final pendientes = await dao.listarPendientes(tenantId: 't1');
    expect(pendientes, hasLength(1));
    expect(pendientes.first.id, 'op-sync-1');

    final resultado = SyncResult(
      clientRequestId: 'op-sync-1',
      status: 'CONFIRMED',
      serverRef: 'ord-123',
      serverNumber: 'ORD-001',
      message: 'OK',
    );

    await dao.aplicarResultados([resultado]);

    final pendientesDespues = await dao.listarPendientes(tenantId: 't1');
    expect(pendientesDespues, isEmpty);
  });

  test('registra y consulta historial de sincronizacion', () async {
    final ini = DateTime.now();
    final fin = ini.add(const Duration(seconds: 1));

    await dao.registrarHistorialSync(
      tenantId: 't1',
      usuarioId: 'u1',
      iniciadoEn: ini,
      terminadoEn: fin,
      enviadas: 3,
      confirmadas: 2,
      conflictos: 1,
      rechazadas: 0,
    );

    final hist = await dao.listarHistorial(tenantId: 't1', usuarioId: 'u1');
    expect(hist, hasLength(1));
    expect(hist.first.enviadas, 3);
    expect(hist.first.confirmadas, 2);
    expect(hist.first.conflictos, 1);
    expect(hist.first.rechazadas, 0);
    expect(hist.first.mensajeError, isNull);
  });

  test('historial aislado por empresa y usuario (A/B)', () async {
    final ahora = DateTime.now();
    await dao.registrarHistorialSync(
      tenantId: 'tenant-a',
      usuarioId: 'u1',
      iniciadoEn: ahora,
      terminadoEn: ahora,
      enviadas: 1,
      confirmadas: 1,
      conflictos: 0,
      rechazadas: 0,
    );
    await dao.registrarHistorialSync(
      tenantId: 'tenant-b',
      usuarioId: 'u2',
      iniciadoEn: ahora,
      terminadoEn: ahora,
      enviadas: 4,
      confirmadas: 0,
      conflictos: 0,
      rechazadas: 0,
      codigoError: 'NETWORK',
    );
    final a = await dao.listarHistorial(tenantId: 'tenant-a', usuarioId: 'u1');
    final b = await dao.listarHistorial(tenantId: 'tenant-b', usuarioId: 'u2');
    expect(a.single.enviadas, 1);
    expect(b.single.enviadas, 4);
    expect(b.single.mensajeError, contains('Sin conexión'));
    expect(
      await dao.listarHistorial(tenantId: 'tenant-a', usuarioId: 'u2'),
      isEmpty,
    );
    expect(
      await dao.listarHistorial(tenantId: 'tenant-b', usuarioId: 'u1'),
      isEmpty,
    );
  });

  test('registro con error HTTP explica que las operaciones siguen', () {
    final r = RegistroSincronizacion.desdeFila({
      'id': 7,
      'iniciado_en': '2026-11-07T10:00:00.000',
      'enviadas': 2,
      'confirmadas': 0,
      'conflictos': 0,
      'rechazadas': 0,
      'codigo_error': 'HTTP_500',
      'http_status': 500,
    });
    expect(r.fallido, isTrue);
    expect(r.mensajeError, contains('HTTP 500'));
    expect(r.mensajeError, contains('pendientes'));
  });

  group('Funciones puras de sincronización e indicador (MJ-02)', () {
    test('estadoIndicador respeta la prioridad del contrato en las 7 combinaciones', () {
      // Prioridad: SINCRONIZANDO > SESION_VENCIDA > SIN_CONEXION > SERVIDOR_NO_RESPONDE > CONFLICTO > PENDIENTES > AL_DIA
      expect(
        estadoIndicador(
          sincronizando: true,
          sesionVencida: true,
          online: false,
          conflictosCount: 1,
        ),
        'SINCRONIZANDO',
      );

      expect(
        estadoIndicador(
          sincronizando: false,
          sesionVencida: true,
          online: false,
          pendientesCount: 3,
        ),
        'SESION_VENCIDA',
      );

      expect(
        estadoIndicador(
          sincronizando: false,
          sesionVencida: false,
          online: false,
          servidorAlcanzable: false,
          pendientesCount: 2,
        ),
        'SIN_CONEXION',
      );

      expect(
        estadoIndicador(
          sincronizando: false,
          online: true,
          servidorAlcanzable: false,
          conflictosCount: 1,
        ),
        'SERVIDOR_NO_RESPONDE',
      );

      expect(
        estadoIndicador(
          sincronizando: false,
          online: true,
          servidorAlcanzable: true,
          conflictosCount: 2,
          pendientesCount: 5,
        ),
        'CONFLICTO',
      );

      expect(
        estadoIndicador(
          sincronizando: false,
          online: true,
          servidorAlcanzable: true,
          conflictosCount: 0,
          pendientesCount: 3,
        ),
        'PENDIENTES',
      );

      expect(
        estadoIndicador(
          sincronizando: false,
          online: true,
          servidorAlcanzable: true,
          conflictosCount: 0,
          pendientesCount: 0,
        ),
        'AL_DIA',
      );
    });

    test('textoIndicador devuelve los textos exactos del enmaquetado, con plurales', () {
      expect(
        textoIndicador('AL_DIA', minutosDesdeDescarga: 2),
        'Todo sincronizado · datos de hace 2 min',
      );
      expect(textoIndicador('AL_DIA'), 'Todo sincronizado');

      expect(
        textoIndicador('SINCRONIZANDO', pendientesCount: 1),
        'Sincronizando 1 operación…',
      );
      expect(
        textoIndicador('SINCRONIZANDO', pendientesCount: 3),
        'Sincronizando 3 operaciones…',
      );

      expect(
        textoIndicador('PENDIENTES', pendientesCount: 3, reintentoEnSegundos: 20),
        '3 por subir · reintento en 20 s',
      );
      expect(
        textoIndicador('PENDIENTES', pendientesCount: 1),
        '1 por subir',
      );

      expect(
        textoIndicador('SIN_CONEXION', pendientesCount: 3),
        'Sin conexión · 3 por subir · se enviarán solas',
      );
      expect(
        textoIndicador(
          'SIN_CONEXION',
          pendientesCount: 0,
          fechaDatos: DateTime(2026, 11, 11, 10, 40),
        ),
        contains('Sin conexión · datos del 11/11 10:40'),
      );

      expect(
        textoIndicador('SESION_VENCIDA', pendientesCount: 3),
        '3 ventas por subir · Iniciá sesión para enviarlas',
      );

      expect(
        textoIndicador('CONFLICTO', conflictosCount: 1),
        '1 operación necesita revisión',
      );
      expect(
        textoIndicador('CONFLICTO', conflictosCount: 2),
        '2 operaciones necesitan revisión',
      );

      expect(
        textoIndicador('SERVIDOR_NO_RESPONDE'),
        'El servidor no responde · reintentando',
      );

      expect(
        textoIndicador(
          'AL_DIA',
          minutosDesdeDescarga: 1500,
          fechaDatos: DateTime(2026, 11, 10, 9, 12),
        ),
        contains('datos del 10/11 09:12, pueden estar desactualizados'),
      );
    });

    test('etiquetas de estado y tipo', () {
      expect(etiquetaEstado('PENDIENTE'), 'Por subir');
      expect(etiquetaEstado('ENVIADA'), 'Enviando');
      expect(etiquetaEstado('CONFIRMADA'), 'Confirmada');
      expect(etiquetaEstado('CONFLICTO'), 'Necesita revisión');
      expect(etiquetaEstado('RECHAZADA'), 'Rechazada');
      expect(etiquetaEstado('ANULADA'), 'Anulada');

      expect(etiquetaTipo('VENTA'), 'Venta de contado');
      expect(etiquetaTipo('RESERVA'), 'Reserva');
    });

    test('debeActualizarCatalogo evalúa red, sesión, módulo, tiempo y eventos', () {
      final base = DateTime(2026, 11, 11, 14, 0);

      // Sin red / sesión / módulo -> false
      expect(
        debeActualizarCatalogo(
          online: false,
          sesionReal: true,
          tieneModuloOffline: true,
          versionLocal: 'v1',
        ),
        isFalse,
      );

      // Sin versión local -> true
      expect(
        debeActualizarCatalogo(
          online: true,
          sesionReal: true,
          tieneModuloOffline: true,
          versionLocal: null,
        ),
        isTrue,
      );

      // Con 2 min sin evento -> false
      expect(
        debeActualizarCatalogo(
          online: true,
          sesionReal: true,
          tieneModuloOffline: true,
          versionLocal: 'v1',
          ultimaDescarga: base,
          ahora: base.add(const Duration(minutes: 2)),
        ),
        isFalse,
      );

      // Con 6 min sin evento -> true
      expect(
        debeActualizarCatalogo(
          online: true,
          sesionReal: true,
          tieneModuloOffline: true,
          versionLocal: 'v1',
          ultimaDescarga: base,
          ahora: base.add(const Duration(minutes: 6)),
        ),
        isTrue,
      );

      // Evento sync_confirmed -> true
      expect(
        debeActualizarCatalogo(
          online: true,
          sesionReal: true,
          tieneModuloOffline: true,
          versionLocal: 'v1',
          ultimaDescarga: base,
          ahora: base.add(const Duration(minutes: 2)),
          evento: 'sync_confirmed',
        ),
        isTrue,
      );
    });
  });
}
