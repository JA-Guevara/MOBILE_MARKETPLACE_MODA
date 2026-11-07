import 'dart:convert';
import '../../../core/offline/base_local.dart';
import '../domain/reserva_local.dart';
import '../domain/sincronizacion.dart';

class OperacionesDao {
  const OperacionesDao(this.base);
  final BaseLocal base;

  Future<List<OperacionPendiente>> listarPendientes({
    String? tenantId,
    String? usuarioId,
  }) async {
    final db = await base.abrir();
    final where =
        "estado = 'PENDIENTE'${tenantId != null ? ' AND tenant_id = ?' : ''}${usuarioId != null ? ' AND usuario_id = ?' : ''}";
    final args = [
      if (tenantId != null) tenantId,
      if (usuarioId != null) usuarioId,
    ];

    final rows = await db.query(
      'operaciones_pendientes',
      where: where,
      whereArgs: args,
      orderBy: 'creada_en ASC',
    );
    return rows.map(OperacionPendiente.desdeFila).toList();
  }

  Future<List<OperacionPendiente>> tomarParaEnvio({
    int limite = 50,
    String? tenantId,
    String? usuarioId,
  }) async {
    final db = await base.abrir();
    return db.transaction((txn) async {
      final now = DateTime.now().toUtc();
      final rows = await txn.query(
        'operaciones_pendientes',
        where:
            "((estado = 'PENDIENTE' AND (proximo_intento_en IS NULL OR proximo_intento_en <= ?)) OR (estado = 'ENVIADA' AND actualizada_en < ?))${tenantId != null ? ' AND tenant_id = ?' : ''}${usuarioId != null ? ' AND usuario_id = ?' : ''}",
        whereArgs: [
          now.toIso8601String(),
          now.subtract(const Duration(minutes: 2)).toIso8601String(),
          if (tenantId != null) tenantId,
          if (usuarioId != null) usuarioId,
        ],
        orderBy: 'creada_en ASC',
        limit: limite,
      );
      final result = <OperacionPendiente>[];
      for (final row in rows) {
        await txn.update(
          'operaciones_pendientes',
          {'estado': 'ENVIADA', 'actualizada_en': now.toIso8601String()},
          where: 'id=?',
          whereArgs: [row['id']],
        );
        final copy = Map<String, Object?>.from(row);
        if (row['venta_id'] != null) {
          final sales = await txn.query(
            'ventas_locales',
            where: 'id=?',
            whereArgs: [row['venta_id']],
          );
          if (sales.isEmpty) {
            throw StateError('Falta una venta pendiente del dispositivo.');
          }
          final sale = sales.single;
          final items = await txn.query(
            'venta_items_locales',
            where: 'venta_id=?',
            whereArgs: [sale['id']],
          );
          String importe(Object? value) => (value as num).toStringAsFixed(2);
          copy['payload'] = jsonEncode({
            'user_id': sale['usuario_id'],
            'cash_point_id': sale['caja_id'],
            'customer_id': sale['cliente_id'],
            'payment_method': 'cash',
            'subtotal': importe(sale['subtotal']),
            'total': importe(sale['total']),
            'discount_total': '0.00',
            'cash_received': importe(sale['recibido']),
            'local_folio': sale['folio'],
            'catalog_downloaded_at': sale['catalogo_descargado_en'],
            'items': items
                .map(
                  (item) => {
                    'variant_id': item['variante_id'],
                    'quantity': item['cantidad'],
                    'unit_price': importe(item['precio_unitario']),
                    'regular_price': importe(item['precio_regular']),
                  },
                )
                .toList(),
          });
        }
        result.add(OperacionPendiente.desdeFila(copy));
      }
      return result;
    });
  }

  Future<void> aplicarResultados(List<SyncResult> resultados) async {
    final db = await base.abrir();
    final ahora = DateTime.now().toIso8601String();

    await db.transaction((txn) async {
      for (final res in resultados) {
        final rows = await txn.query(
          'operaciones_pendientes',
          where: 'id=?',
          whereArgs: [res.clientRequestId],
        );
        if (rows.isEmpty || res.status == 'UNKNOWN') continue;
        final operation = rows.single;
        final estado = res.isConfirmed
            ? 'CONFIRMADA'
            : res.isConflict
            ? 'CONFLICTO'
            : res.isRejected
            ? 'RECHAZADA'
            : 'PENDIENTE';
        await txn.update(
          'operaciones_pendientes',
          {
            'estado': estado,
            'refund_amount': res.refundAmount,
            'refund_status': res.refundStatus,
            'server_ref': res.serverRef,
            'server_numero': res.serverNumber,
            'conflicto_id': res.conflictId,
            'motivo_codigo': res.reasonCode,
            'ultimo_error': res.isConfirmed ? null : res.message,
            'actualizada_en': ahora,
            'intentos': (operation['intentos'] as num).toInt() + 1,
          },
          where: 'id=?',
          whereArgs: [res.clientRequestId],
        );
        if (operation['venta_id'] != null) {
          await txn.update(
            'ventas_locales',
            {
              'estado': res.isConfirmed
                  ? 'CONFIRMADA'
                  : res.isConflict
                  ? 'EN_CONFLICTO'
                  : res.isRejected
                  ? 'RECHAZADA'
                  : 'PENDIENTE_SINCRONIZAR',
              'server_ref': res.serverRef,
              'server_numero': res.serverNumber,
            },
            where: 'id=?',
            whereArgs: [operation['venta_id']],
          );
        }
        final reservaId =
            operation['reserva_id'] ??
            (operation['tipo'] == 'RESERVA' ? res.clientRequestId : null);
        if (reservaId != null) {
          await txn.update(
            'reservas_locales',
            {
              'estado': res.isConfirmed
                  ? 'CONFIRMADA'
                  : res.isRejected
                  ? 'RECHAZADA'
                  : 'PENDIENTE_CONFIRMACION',
            },
            where: 'id=?',
            whereArgs: [reservaId],
          );
        }
      }
    });
  }

  Future<void> liberarEnvio(List<String> ids) async {
    final db = await base.abrir();
    await db.transaction((txn) async {
      for (final id in ids) {
        await txn.update(
          'operaciones_pendientes',
          {
            'estado': 'PENDIENTE',
            'ultimo_error': 'Se reintentará al recuperar conexión.',
          },
          where: "id=? AND estado='ENVIADA'",
          whereArgs: [id],
        );
      }
    });
  }

  Future<List<Map<String, Object?>>> listarTodas(
    String tenantId,
    String usuarioId,
  ) async {
    return (await base.abrir()).query(
      'operaciones_pendientes',
      where: 'tenant_id=? AND usuario_id=?',
      whereArgs: [tenantId, usuarioId],
      orderBy: 'creada_en DESC',
    );
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
    String? tenantId,
    String? usuarioId,
  }) async {
    final db = await base.abrir();
    await db.insert('historial_sync', {
      'tenant_id': tenantId,
      'usuario_id': usuarioId,
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

  /// Historial de la cuenta actual (RN03): solo filas de esa empresa y usuario.
  Future<List<RegistroSincronizacion>> listarHistorial({
    required String tenantId,
    required String usuarioId,
    int limite = 50,
  }) async {
    final db = await base.abrir();
    final rows = await db.query(
      'historial_sync',
      where: 'tenant_id = ? AND usuario_id = ?',
      whereArgs: [tenantId, usuarioId],
      orderBy: 'iniciado_en DESC, id DESC',
      limit: limite,
    );
    return rows.map(RegistroSincronizacion.desdeFila).toList();
  }
}
