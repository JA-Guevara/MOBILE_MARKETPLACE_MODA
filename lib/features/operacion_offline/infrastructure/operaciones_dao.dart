import '../../../core/offline/base_local.dart';
import '../domain/reserva_local.dart';
import '../domain/sincronizacion.dart';

class OperacionesDao {
  const OperacionesDao(this.base);
  final BaseLocal base;

  Future<List<OperacionPendiente>> listarPendientes({String? tenantId, String? usuarioId}) async {
    final db = await base.abrir();
    final where = "estado = 'PENDIENTE'${tenantId != null ? ' AND tenant_id = ?' : ''}${usuarioId != null ? ' AND usuario_id = ?' : ''}";
    final args = [if (tenantId != null) tenantId, if (usuarioId != null) usuarioId];

    final rows = await db.query(
      'operaciones_pendientes',
      where: where,
      whereArgs: args,
      orderBy: 'creada_en ASC',
    );
    return rows.map(OperacionPendiente.desdeFila).toList();
  }

  Future<List<OperacionPendiente>> tomarParaEnvio({int limite = 50, String? tenantId, String? usuarioId}) async {
    final db = await base.abrir();
    final rows = await db.query(
      'operaciones_pendientes',
      where: "estado = 'PENDIENTE' AND intentos < 5${tenantId != null ? ' AND tenant_id = ?' : ''}${usuarioId != null ? ' AND usuario_id = ?' : ''}",
      whereArgs: [if (tenantId != null) tenantId, if (usuarioId != null) usuarioId],
      orderBy: 'creada_en ASC',
      limit: limite,
    );
    return rows.map(OperacionPendiente.desdeFila).toList();
  }

  Future<void> aplicarResultados(List<SyncResult> resultados) async {
    final db = await base.abrir();
    final ahora = DateTime.now().toIso8601String();

    await db.transaction((txn) async {
      for (final res in resultados) {
        if (res.isConfirmed) {
          await txn.update(
            'operaciones_pendientes',
            {
              'estado': 'CONFIRMADA',
              'actualizada_en': ahora,
            },
            where: 'id = ?',
            whereArgs: [res.clientRequestId],
          );
        } else if (res.isConflict) {
          await txn.update(
            'operaciones_pendientes',
            {
              'estado': 'CONFLICTO',
              'ultimo_error': res.message,
              'actualizada_en': ahora,
            },
            where: 'id = ?',
            whereArgs: [res.clientRequestId],
          );
        } else {
          await txn.rawUpdate('''
            UPDATE operaciones_pendientes
            SET intentos = intentos + 1,
                ultimo_error = ?,
                actualizada_en = ?
            WHERE id = ?
          ''', [res.message, ahora, res.clientRequestId]);
        }
      }
    });
  }

  Future<void> registrarHistorialSync({
    required DateTime iniciadoEn,
    required DateTime terminadoEn,
    required int enviadas,
    required int confirmadas,
    required int conflictos,
    required int rechazadas,
    String? loteId,
    int? httpStatus,
    String? codigoError,
  }) async {
    final db = await base.abrir();
    await db.insert('historial_sync', {
      'iniciado_en': iniciadoEn.toIso8601String(),
      'terminado_en': terminadoEn.toIso8601String(),
      'enviadas': enviadas,
      'confirmadas': confirmadas,
      'conflictos': conflictos,
      'rechazadas': rechazadas,
      'lote_id': loteId,
      'http_status': httpStatus,
      'codigo_error': codigoError,
    });
  }

  Future<List<Map<String, dynamic>>> listarHistorial({int limite = 50}) async {
    final db = await base.abrir();
    final rows = await db.query(
      'historial_sync',
      orderBy: 'iniciado_en DESC',
      limit: limite,
    );
    return rows.map((r) => Map<String, dynamic>.from(r)).toList();
  }
}
