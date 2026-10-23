import 'package:sqflite/sqflite.dart';
import '../../../core/offline/base_local.dart';
import '../domain/reserva_local.dart';

class ReservasLocalesDao {
  const ReservasLocalesDao(
    this.base, {
    required this.tenantId,
    required this.usuarioId,
  });
  final BaseLocal base;
  final String tenantId, usuarioId;

  Future<void> registrar(
    ReservaLocal r,
    List<ItemReservaLocal> items,
    OperacionPendiente op,
  ) async {
    if (r.tenantId != tenantId ||
        r.usuarioId != usuarioId ||
        op.tenantId != tenantId ||
        op.usuarioId != usuarioId ||
        op.sucursalId != r.sucursalId ||
        op.payload['client_key'] != r.id ||
        r.estado != EstadoReservaLocal.pendienteConfirmacion ||
        op.estado != EstadoOperacion.pendiente ||
        items.isEmpty ||
        items.length > 20 ||
        items.map((i) => i.varianteId).toSet().length != items.length) {
      throw StateError('La reserva local no es válida para este perfil.');
    }
    if (validarVisita(r.agendadaPara, DateTime.now()) != null) {
      throw StateError('Elegí una fecha y hora futuras.');
    }
    final db = await base.abrir();
    await db.transaction((txn) async {
      final meta = await txn.query(
        'meta',
        where: 'clave = ?',
        whereArgs: ['tenant_id'],
      );
      if (meta.isEmpty || meta.first['valor'] != tenantId) {
        throw StateError('Descargá primero el catálogo de tu empresa.');
      }
      await txn.insert('reservas_locales', r.aFila());
      for (final item in items) {
        if (item.reservaId != r.id || item.cantidad < 1 || item.cantidad > 10) {
          throw StateError(
            'La cantidad de la reserva no es válida (1 a 10 por variante).',
          );
        }
        final variante = await txn.query(
          'variantes',
          where: 'id = ? AND activa = 1',
          whereArgs: [item.varianteId],
        );
        if (variante.isEmpty) {
          throw StateError(
            'La variante ya no está disponible en el catálogo local.',
          );
        }
        final cambiadas = await txn.rawUpdate(
          'UPDATE existencias SET cantidad = cantidad - ? WHERE variante_id = ? AND sucursal_id = ? AND cantidad >= ?',
          [item.cantidad, item.varianteId, r.sucursalId, item.cantidad],
        );
        if (cambiadas != 1) throw StateError('Sin existencia local suficiente');
        await txn.insert('reserva_items_locales', item.aFila());
      }
      await txn.insert('operaciones_pendientes', op.aFila());
    });
  }

  Future<List<ReservaLocalVista>> listar() async {
    final db = await base.abrir();
    return db.transaction((txn) async {
      final filas = await txn.query(
        'reservas_locales',
        where: 'tenant_id = ? AND usuario_id = ?',
        whereArgs: [tenantId, usuarioId],
        orderBy: 'creada_en DESC',
      );
      final salida = <ReservaLocalVista>[];
      for (final fila in filas) {
        final vista = await _vista(txn, fila);
        if (vista != null) salida.add(vista);
      }
      return salida;
    });
  }

  Future<ReservaLocalVista?> obtener(String id) async {
    final db = await base.abrir();
    return db.transaction((txn) async {
      final filas = await txn.query(
        'reservas_locales',
        where: 'id = ? AND tenant_id = ? AND usuario_id = ?',
        whereArgs: [id, tenantId, usuarioId],
      );
      return filas.isEmpty ? null : await _vista(txn, filas.first);
    });
  }

  Future<ReservaLocalVista?> _vista(
    DatabaseExecutor txn,
    Map<String, Object?> fila,
  ) async {
    final r = ReservaLocal.desdeFila(fila);
    final ops = await txn.rawQuery(
      "SELECT * FROM operaciones_pendientes WHERE tenant_id=? AND usuario_id=? AND json_extract(payload, '\$.client_key')=?",
      [tenantId, usuarioId, r.id],
    );
    if (ops.isEmpty) return null;
    final sucursales = await txn.query(
      'sucursales',
      where: 'id = ?',
      whereArgs: [r.sucursalId],
    );
    return ReservaLocalVista(
      r,
      (await txn.query(
        'reserva_items_locales',
        where: 'reserva_id = ?',
        whereArgs: [r.id],
      )).map(ItemReservaLocal.desdeFila).toList(),
      OperacionPendiente.desdeFila(ops.first),
      sucursalNombre: sucursales.isEmpty
          ? null
          : sucursales.first['nombre'] as String,
    );
  }

  Future<void> cancelar(String id) async {
    final db = await base.abrir();
    await db.transaction((txn) async {
      final filas = await txn.query(
        'reservas_locales',
        where: 'id = ? AND tenant_id = ? AND usuario_id = ?',
        whereArgs: [id, tenantId, usuarioId],
      );
      if (filas.isEmpty) throw StateError('Reserva local no encontrada.');
      final vista = await _vista(txn, filas.first);
      if (vista == null ||
          !puedeCancelarLocal(vista.operacion) ||
          vista.reserva.estado != EstadoReservaLocal.pendienteConfirmacion) {
        throw StateError(
          'Solo puedes cancelar reservas pendientes de sincronizar.',
        );
      }
      // Otro catálogo puede estar descargado. La cola queda preservada, pero
      // su cancelación nunca puede cambiar las existencias de otra empresa.
      final meta = await txn.query(
        'meta',
        where: 'clave = ?',
        whereArgs: ['tenant_id'],
      );
      if (meta.isNotEmpty && meta.first['valor'] == tenantId) {
        for (final item in vista.items) {
          await txn.rawUpdate(
            'UPDATE existencias SET cantidad = cantidad + ? WHERE variante_id = ? AND sucursal_id = ?',
            [item.cantidad, item.varianteId, vista.reserva.sucursalId],
          );
        }
      }
      await txn.update(
        'reservas_locales',
        {'estado': EstadoReservaLocal.anuladaLocal.codigo},
        where: 'id = ?',
        whereArgs: [id],
      );
      await txn.update(
        'operaciones_pendientes',
        {
          'estado': EstadoOperacion.anulada.codigo,
          'actualizada_en': DateTime.now().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [vista.operacion.id],
      );
    });
  }
}
