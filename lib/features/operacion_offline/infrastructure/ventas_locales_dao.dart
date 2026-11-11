import 'package:sqflite/sqflite.dart';
import '../../ventas_pagos/infrastructure/commerce_api.dart';
import '../../../core/offline/base_local.dart';
import '../../usuarios_catalogo/domain/usuario.dart';

class VentasLocalesDao {
  const VentasLocalesDao(this.base);
  final BaseLocal base;

  Future<Map<String, Object?>> registrar({
    required Usuario usuario,
    required String cajaId,
    required Map<String, int> cantidades,
    required double recibido,
    String? clienteId,
  }) async {
    final subscription = usuario.suscripcion;
    final fin = DateTime.tryParse(subscription?.fin ?? '');
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final permiteVentas = subscription?.permite('sales') ?? true;
    final permiteOffline = subscription?.permite('offline') ?? true;
    if (usuario.empresa != null && usuario.empresa!.estado != 'ACTIVA' ||
        subscription != null && subscription.estado != 'ACTIVA' ||
        subscription?.soloLectura == true ||
        !permiteVentas ||
        !permiteOffline ||
        (fin != null &&
            DateTime(fin.year, fin.month, fin.day).isBefore(today))) {
      throw StateError('Tu cuenta o suscripción no permite registrar ventas.');
    }
    if (cantidades.isEmpty ||
        cantidades.values.any((n) => n <= 0) ||
        !recibido.isFinite) {
      throw StateError('Seleccioná prendas y registrá el efectivo recibido.');
    }
    final deviceId = await base.dispositivoId();
    final db = await base.abrir();
    return db.transaction((txn) async {
      final meta = {
        for (final row in await txn.query('meta'))
          row['clave'] as String: row['valor'] as String,
      };
      final branch = meta['sucursal_id'];
      final validity = DateTime.tryParse(meta['precio_vigente_hasta'] ?? '');
      if (meta['tenant_id'] != usuario.empresa?.id ||
          branch == null ||
          (validity != null && !validity.isAfter(DateTime.now()))) {
        throw StateError(
          'Actualizá el catálogo de tu empresa antes de vender.',
        );
      }
      var cajas = await txn.query(
        'cajas',
        where: 'id=? AND sucursal_id=? AND activa=1',
        whereArgs: [cajaId, branch],
      );
      if (cajas.isEmpty) {
        cajas = await txn.query(
          'cajas',
          where: 'sucursal_id=? AND activa=1',
          whereArgs: [branch],
        );
      }
      if (cajas.isEmpty) {
        throw StateError('No hay una caja autorizada activa en esta sucursal.');
      }
      final efectivaCajaId = cajas.first['id'] as String;
      final codigoCaja = cajas.first['codigo'] as String? ?? 'CAJA-01';
      // Cliente opcional (CU-18): solo uno descargado en el catálogo de esta
      // empresa; el nombre se toma de la base local, no de la pantalla.
      Map<String, Object?>? cliente;
      if (clienteId != null && clienteId.isNotEmpty) {
        final clientes = await txn.query(
          'clientes',
          columns: ['id', 'nombre'],
          where: 'id=?',
          whereArgs: [clienteId],
        );
        if (clientes.isEmpty) {
          throw StateError(
            'El cliente elegido no está en el catálogo local de tu empresa.',
          );
        }
        cliente = clientes.single;
      }
      final id = CommerceApi.nuevaClaveSolicitud();
      final timestamp = DateTime.now().toUtc().toIso8601String();
      final items = <Map<String, Object?>>[];
      var totalCentavos = 0;
      for (final entry in cantidades.entries) {
        final rows = await txn.rawQuery(
          '''
          SELECT v.id, v.sku, v.talla, v.color, COALESCE(v.precio,p.precio_base) AS precio,
                 p.nombre, e.cantidad
          FROM variantes v JOIN productos p ON p.id=v.producto_id
          JOIN existencias e ON e.variante_id=v.id AND e.sucursal_id=?
          WHERE v.id=? AND v.activa=1''',
          [branch, entry.key],
        );
        if (rows.isEmpty ||
            (rows.first['cantidad'] as num).toInt() < entry.value) {
          throw StateError('Sin existencia local suficiente.');
        }
        final row = rows.first;
        final precio = (row['precio'] as num).toDouble();
        final lineaCentavos = (precio * 100).round() * entry.value;
        totalCentavos += lineaCentavos;
        items.add({
          'venta_id': id,
          'variante_id': entry.key,
          'producto_nombre': row['nombre'],
          'variante_desc': '${row['talla']} · ${row['color']}',
          'cantidad': entry.value,
          'precio_unitario': precio,
          'precio_regular': precio,
          'total_linea': lineaCentavos / 100,
        });
      }
      if ((recibido * 100).round() < totalCentavos) {
        throw StateError('El efectivo recibido es insuficiente.');
      }
      final total = totalCentavos / 100;
      final folioKey = 'folio_$efectivaCajaId';
      final counter = (int.tryParse(meta[folioKey] ?? '0') ?? 0) + 1;
      final venta = <String, Object?>{
        'id': id,
        'folio':
            'OFF-$codigoCaja-${counter.toString().padLeft(4, '0')}',
        'tenant_id': usuario.empresa!.id,
        'sucursal_id': branch,
        'caja_id': efectivaCajaId,
        'usuario_id': usuario.id,
        'cliente_id': cliente?['id'],
        'cliente_nombre': cliente?['nombre'],
        'subtotal': total,
        'descuento': 0,
        'total': total,
        'recibido': recibido,
        'vuelto': ((recibido * 100).round() - totalCentavos) / 100,
        'forma_pago': 'EFECTIVO',
        'estado': 'PENDIENTE_SINCRONIZAR',
        'catalogo_descargado_en': meta['descargado_en'],
        'creada_en': timestamp,
      };
      await txn.insert('ventas_locales', venta);
      for (final item in items) {
        await txn.insert('venta_items_locales', item);
        await txn.rawUpdate(
          'UPDATE existencias SET cantidad=cantidad-? WHERE variante_id=? AND sucursal_id=?',
          [item['cantidad'], item['variante_id'], branch],
        );
      }
      await txn.insert('operaciones_pendientes', {
        'id': id,
        'venta_id': id,
        'tipo': 'VENTA',
        'estado': 'PENDIENTE',
        'tenant_id': usuario.empresa!.id,
        'sucursal_id': branch,
        'usuario_id': usuario.id,
        'dispositivo_id': deviceId,
        'intentos': 0,
        'creada_en': timestamp,
        'actualizada_en': timestamp,
      });
      await txn.insert('meta', {
        'clave': folioKey,
        'valor': '$counter',
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      return venta;
    });
  }

  /// CU-18: Anula una venta local pendiente y repone las existencias descontadas
  /// al inventario local de la sucursal.
  Future<void> anularYReponer({
    required String ventaId,
    required String tenantId,
  }) async {
    final db = await base.abrir();
    await db.transaction((txn) async {
      final sales = await txn.query(
        'ventas_locales',
        where: 'id=? AND tenant_id=?',
        whereArgs: [ventaId, tenantId],
      );
      if (sales.isEmpty) return;
      final sale = sales.first;
      final branch = sale['sucursal_id'] as String;
      final items = await txn.query(
        'venta_items_locales',
        where: 'venta_id=?',
        whereArgs: [ventaId],
      );
      for (final item in items) {
        await txn.rawUpdate(
          'UPDATE existencias SET cantidad=cantidad+? WHERE variante_id=? AND sucursal_id=?',
          [item['cantidad'], item['variante_id'], branch],
        );
      }
      await txn.update(
        'ventas_locales',
        {'estado': 'ANULADA_LOCAL'},
        where: 'id=?',
        whereArgs: [ventaId],
      );
      await txn.update(
        'operaciones_pendientes',
        {
          'estado': 'ANULADA',
          'actualizada_en': DateTime.now().toUtc().toIso8601String(),
          'ultimo_error': 'Operación anulada localmente; existencias repuestas.',
        },
        where: 'venta_id=?',
        whereArgs: [ventaId],
      );
    });
  }
}
