import 'dart:convert';

import '../../../core/offline/base_local.dart';
import '../../usuarios_catalogo/domain/usuario.dart';
import '../../ventas_pagos/infrastructure/commerce_api.dart';
import '../domain/compra_local.dart';
import '../domain/sincronizacion.dart';

class ComprasLocalesDao {
  const ComprasLocalesDao(this.base);
  final BaseLocal base;

  Future<CompraLocal> registrar({
    required Usuario usuario,
    required String sucursalId,
    required List<ItemCompraLocal> items,
    required String contactoNombre,
    required String contactoTelefono,
    required String formaPago,
    String? notas,
    Map<String, dynamic>? direccionEntrega,
  }) async {
    final tenantId = usuario.empresa?.id;
    if (tenantId == null || !usuario.puede('sync.write')) {
      throw StateError('Iniciá sesión con una cuenta de cliente válida.');
    }
    if (formaPago != 'TARJETA_AL_RECONECTAR' &&
        formaPago != 'EFECTIVO_AL_RETIRAR') {
      throw StateError('Elegí una forma de pago válida.');
    }
    if (contactoNombre.trim().length < 2 ||
        contactoTelefono.trim().length < 7) {
      throw StateError('Completá tu nombre y teléfono de contacto.');
    }
    final error = validarItemsCompra(items, validarStock: false);
    if (error != null) throw StateError(error);
    if (items.map((item) => item.varianteId).toSet().length != items.length) {
      throw StateError('La compra contiene prendas repetidas.');
    }

    final deviceId = await base.dispositivoId();
    final db = await base.abrir();
    return db.transaction((txn) async {
      final rows = await txn.query(
        'meta',
        where: 'clave IN (?, ?, ?, ?)',
        whereArgs: [
          'tenant_id',
          'sucursal_id',
          'catalogo_usuario_id',
          'descargado_en',
        ],
      );
      final meta = {
        for (final row in rows) row['clave'] as String: row['valor'] as String,
      };
      final descargadoEn = DateTime.tryParse(meta['descargado_en'] ?? '');
      if (meta['tenant_id'] != tenantId ||
          meta['catalogo_usuario_id'] != usuario.id ||
          meta['sucursal_id'] != sucursalId ||
          descargadoEn == null) {
        throw StateError(
          'Descargá primero el catálogo de esta empresa y sucursal.',
        );
      }
      final compraId = CommerceApi.nuevaClaveSolicitud();
      final ahora = DateTime.now().toUtc().toIso8601String();
      final lineas = <ItemCompraLocal>[];
      var totalCentavos = 0;
      for (final item in items) {
        final filas = await txn.rawQuery(
          '''SELECT p.nombre, v.talla, v.color, v.precio, p.precio_base, p.precio_oferta, e.cantidad
             FROM variantes v JOIN productos p ON p.id=v.producto_id
             JOIN existencias e ON e.variante_id=v.id AND e.sucursal_id=?
             WHERE v.id=? AND v.activa=1''',
          [sucursalId, item.varianteId],
        );
        if (filas.isEmpty) {
          throw StateError('Una prenda ya no está en el catálogo guardado.');
        }
        final row = filas.single;
        final stock = (row['cantidad'] as num).toInt();
        final precio =
            (row['precio_oferta'] as num?)?.toDouble() ??
            (row['precio'] as num?)?.toDouble() ??
            (row['precio_base'] as num).toDouble();
        final linea = ItemCompraLocal(
          varianteId: item.varianteId,
          productoNombre: row['nombre'] as String,
          varianteDesc: '${row['talla']} · ${row['color']}',
          cantidad: item.cantidad,
          precioUnitario: precio,
          stockDisponible: stock,
        );
        lineas.add(linea);
        totalCentavos += (precio * 100).round() * item.cantidad;
      }
      final total = totalCentavos / 100;
      final payload = payloadCompra(
        items: lineas,
        contactoNombre: contactoNombre,
        contactoTelefono: contactoTelefono,
        formaPago: formaPago,
        notas: notas,
        direccionEntrega: direccionEntrega,
        deviceId: deviceId,
      );
      await txn.insert('compras_locales', {
        'id': compraId,
        'tenant_id': tenantId,
        'sucursal_id': sucursalId,
        'usuario_id': usuario.id,
        'contacto_nombre': contactoNombre.trim(),
        'contacto_telefono': contactoTelefono.trim(),
        'forma_pago': formaPago,
        'notas': notas?.trim().isEmpty == true ? null : notas?.trim(),
        'subtotal': total,
        'total': total,
        'estado': 'POR_ENVIAR',
        'catalogo_descargado_en': descargadoEn.toIso8601String(),
        'creada_en': ahora,
      });
      for (final item in lineas) {
        await txn.insert('compra_items_locales', {
          'compra_id': compraId,
          'variante_id': item.varianteId,
          'producto_nombre': item.productoNombre,
          'variante_desc': item.varianteDesc,
          'cantidad': item.cantidad,
          'precio_unitario': item.precioUnitario,
        });
        await txn.rawUpdate(
          'UPDATE existencias SET cantidad=cantidad-? WHERE variante_id=? AND sucursal_id=? AND cantidad>=?',
          [item.cantidad, item.varianteId, sucursalId, item.cantidad],
        );
      }
      await txn.insert('operaciones_pendientes', {
        'id': compraId,
        'tipo': 'COMPRA',
        'estado': 'PENDIENTE',
        'tenant_id': tenantId,
        'sucursal_id': sucursalId,
        'usuario_id': usuario.id,
        'dispositivo_id': deviceId,
        'payload': jsonEncode(payload),
        'compra_id': compraId,
        'intentos': 0,
        'creada_en': ahora,
        'actualizada_en': ahora,
      });
      final saved = await txn.query(
        'compras_locales',
        where: 'id=?',
        whereArgs: [compraId],
      );
      return CompraLocal.desdeFila(saved.single);
    });
  }

  Future<List<ItemCompraLocal>> items(String compraId) async {
    final rows = await (await base.abrir()).query(
      'compra_items_locales',
      where: 'compra_id=?',
      whereArgs: [compraId],
      orderBy: 'producto_nombre',
    );
    return rows
        .map(
          (row) => ItemCompraLocal(
            varianteId: row['variante_id'] as String,
            productoNombre: row['producto_nombre'] as String,
            varianteDesc: row['variante_desc'] as String,
            cantidad: (row['cantidad'] as num).toInt(),
            precioUnitario: (row['precio_unitario'] as num).toDouble(),
          ),
        )
        .toList();
  }

  Future<List<CompraLocal>> listar(String tenantId, String usuarioId) async {
    final rows = await (await base.abrir()).query(
      'compras_locales',
      where: 'tenant_id=? AND usuario_id=?',
      whereArgs: [tenantId, usuarioId],
      orderBy: 'creada_en DESC',
    );
    return rows.map(CompraLocal.desdeFila).toList();
  }

  Future<void> anular(
    String compraId, {
    required String tenantId,
    required String usuarioId,
  }) async {
    final db = await base.abrir();
    await db.transaction((txn) async {
      final compras = await txn.query(
        'compras_locales',
        where: 'id=? AND tenant_id=? AND usuario_id=?',
        whereArgs: [compraId, tenantId, usuarioId],
      );
      if (compras.isEmpty) throw StateError('Compra local no encontrada.');
      final compra = CompraLocal.desdeFila(compras.single);
      final operaciones = await txn.query(
        'operaciones_pendientes',
        where: 'id=? AND tipo=?',
        whereArgs: [compraId, 'COMPRA'],
      );
      if (operaciones.isEmpty || operaciones.single['estado'] != 'PENDIENTE') {
        throw StateError(
          'Solo puedes cancelar una compra que todavía no fue confirmada.',
        );
      }
      final lineas = await txn.query(
        'compra_items_locales',
        where: 'compra_id=?',
        whereArgs: [compraId],
      );
      final meta = await txn.query(
        'meta',
        where: 'clave=?',
        whereArgs: ['tenant_id'],
      );
      if (meta.isNotEmpty && meta.single['valor'] == tenantId) {
        for (final item in lineas) {
          await txn.rawUpdate(
            'UPDATE existencias SET cantidad=cantidad+? WHERE variante_id=? AND sucursal_id=?',
            [item['cantidad'], item['variante_id'], compra.sucursalId],
          );
        }
      }
      await txn.update(
        'compras_locales',
        {'estado': 'CANCELADA_SIN_COBRO'},
        where: 'id=?',
        whereArgs: [compraId],
      );
      await txn.update(
        'operaciones_pendientes',
        {
          'estado': 'ANULADA',
          'ultimo_error':
              'Compra cancelada por el cliente; no se realizó ningún cobro.',
          'actualizada_en': DateTime.now().toUtc().toIso8601String(),
        },
        where: 'id=?',
        whereArgs: [compraId],
      );
    });
  }

  Future<void> aplicarResultado(
    Map<String, Object?> operacion,
    SyncResult resultado,
  ) async {
    final compraId = operacion['compra_id'] as String?;
    if (compraId == null) return;
    final db = await base.abrir();
    await db.transaction((txn) async {
      final state = resultado.isConfirmed
          ? (resultado.paymentRequired == true
                ? 'PENDIENTE_PAGO'
                : 'APARTADA_RETIRO')
          : resultado.isConflict
          ? 'EN_CONFLICTO'
          : resultado.isRejected
          ? 'CANCELADA_SIN_COBRO'
          : 'POR_ENVIAR';
      await txn.update(
        'compras_locales',
        {
          'estado': state,
          'pedido_id': resultado.serverRef,
          'pedido_numero': resultado.serverNumber,
          'pago_vence_en': resultado.paymentExpiresAt,
          if (resultado.total != null)
            'total': double.tryParse(resultado.total!),
        },
        where: 'id=?',
        whereArgs: [compraId],
      );
      if (resultado.isConflict || resultado.isRejected) {
        final rows = await txn.query(
          'compras_locales',
          where: 'id=?',
          whereArgs: [compraId],
        );
        if (rows.isNotEmpty) {
          final compra = CompraLocal.desdeFila(rows.single);
          final yaRepuso =
              operacion['estado'] == 'CONFLICTO' ||
              operacion['estado'] == 'RECHAZADA';
          if (!yaRepuso) {
            final lineas = await txn.query(
              'compra_items_locales',
              where: 'compra_id=?',
              whereArgs: [compraId],
            );
            for (final item in lineas) {
              await txn.rawUpdate(
                'UPDATE existencias SET cantidad=cantidad+? WHERE variante_id=? AND sucursal_id=?',
                [item['cantidad'], item['variante_id'], compra.sucursalId],
              );
            }
          }
        }
      }
    });
  }
}
