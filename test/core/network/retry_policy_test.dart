import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:mobile_marketplace_moda/core/network/api_client.dart';
import 'package:mobile_marketplace_moda/core/network/api_exception.dart';
import 'package:mobile_marketplace_moda/core/network/retry_policy.dart';
import 'package:mobile_marketplace_moda/core/offline/base_local.dart';
import 'package:mobile_marketplace_moda/features/operacion_offline/application/sincronizacion_controller.dart';
import 'package:mobile_marketplace_moda/features/operacion_offline/domain/reserva_local.dart';
import 'package:mobile_marketplace_moda/features/operacion_offline/domain/sincronizacion.dart';
import 'package:mobile_marketplace_moda/features/operacion_offline/infrastructure/operaciones_dao.dart';
import 'package:mobile_marketplace_moda/features/operacion_offline/infrastructure/sync_api.dart';

class FailingApi extends SyncApi {
  FailingApi(this.status) : super(ApiClient());
  final int status;
  final retried = Completer<void>();
  int calls = 0;
  @override
  Future<SyncBatchResponse> postBatch(List<SyncOperationWire> operaciones) async {
    calls++;
    if (calls > 1 && !retried.isCompleted) retried.complete();
    throw ApiException('Fallo temporal', statusCode: status, retryAfter: '1');
  }
}

void main() {
  sqfliteFfiInit();
  test('respeta segundos, fecha HTTP y backoff con máximo local', () {
    final policy = RetryPolicy(ahora: () => DateTime.utc(2026, 11, 5), aleatorio: () => 0);
    expect(policy.esperaPara(1, '120'), const Duration(seconds: 120));
    expect(policy.esperaPara(1, '3600'), const Duration(hours: 1));
    expect(policy.esperaPara(1, 'Thu, 05 Nov 2026 00:02:00 GMT'), const Duration(minutes: 2));
    expect(policy.esperaPara(2, null), const Duration(seconds: 4));
    expect(policy.esperaPara(50, 'incorrecto'), const Duration(minutes: 5));
  });

  test('ApiException conserva la cabecera para 429 y 503', () {
    for (final status in [429, 503]) {
      final options = RequestOptions(path: '/sync/batch');
      final e = ApiException.from(DioException(requestOptions: options, response: Response(
        requestOptions: options, statusCode: status, data: {}, headers: Headers.fromMap({'retry-after': ['123']}),
      )));
      expect(e.retryAfter, '123');
      expect(e.statusCode, status);
    }
  });

  test('la cola de envío filtra empresa y usuario de la sesión', () async {
    final base = BaseLocal(fabrica: databaseFactoryFfi, ruta: inMemoryDatabasePath);
    try {
      final db = await base.abrir();
      final now = DateTime.now();
      for (final item in [('a', 't1', 'u1'), ('b', 't2', 'u1'), ('c', 't1', 'u2')]) {
        await db.insert('operaciones_pendientes', OperacionPendiente(
          id: item.$1, tenantId: item.$2, sucursalId: 'b1', usuarioId: item.$3, dispositivoId: 'd1',
          payload: {}, creadaEn: now, actualizadaEn: now,
        ).aFila());
      }
      final dao = OperacionesDao(base);
      expect((await dao.tomarParaEnvio(tenantId: 't1', usuarioId: 'u1')).map((o) => o.id), ['a']);
      expect((await dao.listarPendientes(tenantId: 't2', usuarioId: 'u1')).map((o) => o.id), ['b']);
    } finally {
      await base.cerrar();
    }
  });

  for (final status in [429, 503]) {
    test('HTTP $status conserva SQLite y reintenta automáticamente', () async {
      final base = BaseLocal(fabrica: databaseFactoryFfi, ruta: inMemoryDatabasePath);
      final dao = OperacionesDao(base);
      final now = DateTime.now();
      final db = await base.abrir();
      await db.insert('operaciones_pendientes', OperacionPendiente(
        id: 'op-retry', tenantId: 't1', sucursalId: 'b1', usuarioId: 'u1', dispositivoId: 'd1',
        payload: {}, creadaEn: now, actualizadaEn: now,
      ).aFila());
      final api = FailingApi(status);
      final controller = SincronizacionController(dao: dao, api: api);
      try {
        await controller.sincronizarAhora();
        final pending = await dao.listarPendientes();
        expect(pending, hasLength(1));
        expect(pending.single.estado, EstadoOperacion.pendiente);
        expect(pending.single.intentos, 0);
        expect(controller.state.ultimoError, contains('En espera'));
        await controller.sincronizarAhora();
        expect(api.calls, 1); // El botón no elude Retry-After.
        await api.retried.future.timeout(const Duration(seconds: 5));
        while (controller.state.sincronizando) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
        expect((await dao.listarPendientes()).single.id, 'op-retry');
      } finally {
        controller.dispose();
        await base.cerrar();
      }
    });
  }
}
