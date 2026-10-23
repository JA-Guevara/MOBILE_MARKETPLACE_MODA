import 'package:sqflite/sqflite.dart';
import '../../../core/offline/base_local.dart';
import '../domain/catalogo_local.dart';

class CatalogoLocalDao {
  const CatalogoLocalDao(this.base);
  final BaseLocal base;

  Future<void> guardar(
    InstantaneaCatalogo i,
    String sucursalId, {
    String? usuarioId,
  }) async {
    if (!i.sucursales.any((s) => s.id == sucursalId)) {
      throw StateError('La sucursal no pertenece a la instantánea.');
    }
    final db = await base.abrir();
    await db.transaction((txn) async {
      final filas = await txn.query(
        'meta',
        where: 'clave = ?',
        whereArgs: ['tenant_id'],
      );
      final tenantAnterior = filas.isEmpty ? null : filas.first['valor'];
      final cambiaEmpresa = tenantAnterior != i.empresa.id;
      if (cambiaEmpresa && !i.completa) {
        throw StateError('Una empresa nueva requiere una descarga completa.');
      }
      final anterior = await txn.query(
        'meta',
        where: 'clave = ?',
        whereArgs: ['sucursal_id'],
      );
      if (!i.completa &&
          anterior.isNotEmpty &&
          anterior.first['valor'] != sucursalId) {
        throw StateError(
          'El cambio de sucursal requiere una descarga completa.',
        );
      }
      if (i.completa) {
        for (final tabla in [
          'existencias',
          'variantes',
          'productos',
          'sucursales',
          'clientes',
        ]) {
          await txn.delete(tabla);
        }
      }
      final batch = txn.batch();
      for (final p in i.productos) {
        batch.insert(
          'productos',
          p.aFila(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      for (final v in i.variantes) {
        batch.insert(
          'variantes',
          v.aFila(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      for (final s in i.sucursales) {
        batch.insert(
          'sucursales',
          s.aFila(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      // Los clientes dependen de permisos actuales: no conservarlos tras perder acceso.
      await txn.delete('clientes');
      for (final c in i.clientes) {
        batch.insert(
          'clientes',
          c.aFila(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      for (final id in i.productosEliminados) {
        batch.rawDelete(
          'DELETE FROM existencias WHERE variante_id IN (SELECT id FROM variantes WHERE producto_id = ?)',
          [id],
        );
        batch.delete('variantes', where: 'producto_id = ?', whereArgs: [id]);
        batch.delete('productos', where: 'id = ?', whereArgs: [id]);
      }
      for (final id in i.variantesEliminadas) {
        batch.delete('existencias', where: 'variante_id = ?', whereArgs: [id]);
        batch.delete('variantes', where: 'id = ?', whereArgs: [id]);
      }
      await batch.commit(noResult: true);
      // Cada stock del servidor es absoluto: volver a descontar la cola local,
      // sin acumular el descuento de una actualización anterior.
      for (final e in i.existencias) {
        final pendientes = await txn.rawQuery(
          '''SELECT COALESCE(SUM(ri.cantidad),0) AS total
          FROM reserva_items_locales ri JOIN reservas_locales r ON r.id=ri.reserva_id
          WHERE r.tenant_id=? AND r.sucursal_id=? AND ri.variante_id=? AND r.estado='PENDIENTE_CONFIRMACION' ''',
          [i.empresa.id, e.sucursalId, e.varianteId],
        );
        final retenido = (pendientes.first['total'] as num).toInt();
        final disponible = (e.cantidad - retenido).clamp(0, e.cantidad);
        await txn.insert('existencias', {
          'variante_id': e.varianteId,
          'sucursal_id': e.sucursalId,
          'cantidad': disponible,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      final meta = {
        'version_instantanea': i.version,
        'descargado_en': DateTime.now().toIso8601String(),
        'sucursal_id': sucursalId,
        'tenant_id': i.empresa.id,
        if (usuarioId != null) 'catalogo_usuario_id': usuarioId,
      };
      for (final e in meta.entries) {
        await txn.insert('meta', {
          'clave': e.key,
          'valor': e.value,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
  }

  Future<DatosLocales> leer(String sucursalId) async {
    final db = await base.abrir();
    return DatosLocales(
      productos: (await db.query(
        'productos',
        orderBy: 'nombre',
      )).map(ProductoLocal.desdeFila).toList(),
      variantes: (await db.query(
        'variantes',
      )).map(VarianteLocal.desdeFila).toList(),
      existencias: (await db.query(
        'existencias',
        where: 'sucursal_id = ?',
        whereArgs: [sucursalId],
      )).map(ExistenciaLocal.desdeFila).toList(),
      sucursales: (await db.query(
        'sucursales',
      )).map(SucursalLocal.desdeFila).toList(),
      clientes: (await db.query(
        'clientes',
        orderBy: 'nombre',
      )).map(ClienteLocal.desdeFila).toList(),
    );
  }

  Future<MetaOffline> meta() async {
    final filas = await (await base.abrir()).query('meta');
    final m = {
      for (final f in filas) f['clave'] as String: f['valor'] as String,
    };
    return MetaOffline(
      version: m['version_instantanea'],
      descargadoEn: DateTime.tryParse(m['descargado_en'] ?? ''),
      sucursalId: m['sucursal_id'],
      tenantId: m['tenant_id'],
      usuarioId: m['catalogo_usuario_id'],
    );
  }

  Future<Map<String, int>> conteos() async {
    final db = await base.abrir();
    final resultado = <String, int>{};
    for (final t in ['productos', 'variantes', 'clientes']) {
      resultado[t] =
          Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM $t')) ??
          0;
    }
    return resultado;
  }
}
