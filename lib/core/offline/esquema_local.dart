import 'dart:convert';
import 'package:sqflite/sqflite.dart';

/// Esquema compartido con la PWA; los tokens nunca se guardan en esta base.
class EsquemaLocal {
  static const version = 2;
  static const tablas = <String>[
    '''CREATE TABLE productos (id TEXT PRIMARY KEY, nombre TEXT NOT NULL, slug TEXT NOT NULL, categoria TEXT, marca TEXT, precio_base REAL NOT NULL, precio_oferta REAL, imagen_url TEXT, destacado INTEGER NOT NULL, actualizado_en TEXT)''',
    '''CREATE TABLE variantes (id TEXT PRIMARY KEY, producto_id TEXT NOT NULL, sku TEXT NOT NULL, talla TEXT NOT NULL, color TEXT NOT NULL, color_hex TEXT, precio REAL, activa INTEGER NOT NULL)''',
    '''CREATE TABLE existencias (variante_id TEXT NOT NULL, sucursal_id TEXT NOT NULL, cantidad INTEGER NOT NULL CHECK(cantidad >= 0), PRIMARY KEY(variante_id, sucursal_id))''',
    '''CREATE TABLE sucursales (id TEXT PRIMARY KEY, codigo TEXT NOT NULL, nombre TEXT NOT NULL, direccion TEXT)''',
    '''CREATE TABLE clientes (id TEXT PRIMARY KEY, nombre TEXT NOT NULL, documento_final TEXT, telefono TEXT)''',
    '''CREATE TABLE meta (clave TEXT PRIMARY KEY, valor TEXT NOT NULL)''',
    '''CREATE TABLE reservas_locales (id TEXT PRIMARY KEY, tenant_id TEXT NOT NULL, sucursal_id TEXT NOT NULL, usuario_id TEXT NOT NULL, cliente_id TEXT, agendada_para TEXT NOT NULL, notas TEXT, estado TEXT NOT NULL, creada_en TEXT NOT NULL)''',
    '''CREATE TABLE reserva_items_locales (reserva_id TEXT NOT NULL, variante_id TEXT NOT NULL, cantidad INTEGER NOT NULL CHECK(cantidad > 0), PRIMARY KEY(reserva_id, variante_id))''',
    '''CREATE TABLE operaciones_pendientes (id TEXT PRIMARY KEY, tipo TEXT NOT NULL, estado TEXT NOT NULL, tenant_id TEXT NOT NULL, sucursal_id TEXT NOT NULL, usuario_id TEXT NOT NULL, dispositivo_id TEXT NOT NULL, payload TEXT NOT NULL, intentos INTEGER NOT NULL DEFAULT 0, ultimo_error TEXT, creada_en TEXT NOT NULL, actualizada_en TEXT NOT NULL)''',
  ];

  static const _ventas =
      '''CREATE TABLE ventas_locales (id TEXT PRIMARY KEY, folio TEXT NOT NULL, tenant_id TEXT NOT NULL, sucursal_id TEXT NOT NULL, caja_id TEXT NOT NULL REFERENCES cajas(id) ON DELETE RESTRICT, usuario_id TEXT NOT NULL, cliente_id TEXT, cliente_nombre TEXT, subtotal REAL NOT NULL, descuento REAL NOT NULL, total REAL NOT NULL, recibido REAL NOT NULL, vuelto REAL NOT NULL, forma_pago TEXT NOT NULL, estado TEXT NOT NULL, catalogo_descargado_en TEXT NOT NULL, creada_en TEXT NOT NULL, anulada_en TEXT, motivo_anulacion TEXT, server_ref TEXT, server_numero TEXT)''';
  static const _items =
      '''CREATE TABLE venta_items_locales (venta_id TEXT NOT NULL REFERENCES ventas_locales(id), variante_id TEXT NOT NULL, producto_nombre TEXT NOT NULL, variante_desc TEXT NOT NULL, cantidad INTEGER NOT NULL CHECK(cantidad > 0), precio_unitario REAL NOT NULL, precio_regular REAL NOT NULL, total_linea REAL NOT NULL, PRIMARY KEY(venta_id, variante_id))''';
  static const _operaciones =
      '''CREATE TABLE operaciones_pendientes (id TEXT PRIMARY KEY, tipo TEXT NOT NULL, estado TEXT NOT NULL, tenant_id TEXT NOT NULL, sucursal_id TEXT NOT NULL, usuario_id TEXT NOT NULL, dispositivo_id TEXT NOT NULL, payload TEXT, venta_id TEXT REFERENCES ventas_locales(id), reserva_id TEXT REFERENCES reservas_locales(id), intentos INTEGER NOT NULL DEFAULT 0, ultimo_error TEXT, creada_en TEXT NOT NULL, actualizada_en TEXT NOT NULL, server_ref TEXT, server_numero TEXT, conflicto_id TEXT, motivo_codigo TEXT, proximo_intento_en TEXT, CHECK(venta_id IS NULL OR reserva_id IS NULL))''';

  static Future<void> crear(Database db, int version) async {
    final batch = db.batch();
    for (final sql in tablas) {
      batch.execute(sql);
    }
    batch.execute('CREATE INDEX variantes_producto ON variantes(producto_id)');
    batch.execute(
      'CREATE INDEX operaciones_estado ON operaciones_pendientes(estado)',
    );
    await batch.commit(noResult: true);
    await migrar(db, 1, version);
  }

  // sqflite ejecuta onCreate/onUpgrade dentro de su propia transacción.
  // DatabaseExecutor permite reutilizar la misma migración en una transacción
  // explícita al reparar una v2 incompleta, sin abrir transacciones anidadas.
  static Future<void> migrar(DatabaseExecutor db, int de, int a) async {
    if (de < 2 && a >= 2) await _asegurarV2(db);
  }

  static Future<Set<String>> _columnas(
    DatabaseExecutor db,
    String tabla,
  ) async => (await db.rawQuery(
    'PRAGMA table_info($tabla)',
  )).map((fila) => fila['name'] as String).toSet();

  static Future<void> verificarV2(Database db) async {
    final columnas = await _columnas(db, 'operaciones_pendientes');
    final ventas = await _columnas(db, 'ventas_locales');
    final historial = await _columnas(db, 'historial_sync');
    final fkVentas = await db.rawQuery(
      'PRAGMA foreign_key_list(ventas_locales)',
    );
    final fkItems = await db.rawQuery(
      'PRAGMA foreign_key_list(venta_items_locales)',
    );
    final fkOperaciones = await db.rawQuery(
      'PRAGMA foreign_key_list(operaciones_pendientes)',
    );
    if (columnas.contains('venta_id') &&
        columnas.contains('reserva_id') &&
        ventas.contains('catalogo_descargado_en') &&
        historial.contains('request_id') &&
        fkVentas.isNotEmpty &&
        fkItems.isNotEmpty &&
        fkOperaciones.length == 2) {
      return;
    }
    await db.transaction(_asegurarV2);
  }

  static Future<void> _asegurarV2(DatabaseExecutor db) async {
    await db.execute(
      '''CREATE TABLE IF NOT EXISTS cajas (id TEXT PRIMARY KEY, sucursal_id TEXT NOT NULL, codigo TEXT NOT NULL, nombre TEXT NOT NULL, activa INTEGER NOT NULL DEFAULT 1)''',
    );
    final columnasVentas = await _columnas(db, 'ventas_locales');
    final ventas = columnasVentas.isEmpty
        ? <Map<String, Object?>>[]
        : await db.query('ventas_locales');
    // La v2 preliminar no guardaba caja/fecha de catálogo. No inventarlas ni
    // borrar documentos: la transacción se revierte y la base sigue intacta.
    if (ventas.any(
      (v) => v['caja_id'] == null || v['catalogo_descargado_en'] == null,
    )) {
      throw StateError(
        'La base local v2 contiene ventas sin caja o fecha de catálogo. Conservá una copia de la base para completar su migración; no se eliminaron datos.',
      );
    }
    final columnasItems = await _columnas(db, 'venta_items_locales');
    final items = columnasItems.isEmpty
        ? <Map<String, Object?>>[]
        : await db.query('venta_items_locales');
    final operaciones = await db.query('operaciones_pendientes');
    // Primero se retiran los hijos; sus filas se restauran en esta misma
    // transacción y cualquier restricción incumplida revierte toda la reparación.
    await db.execute('DROP TABLE operaciones_pendientes');
    if (columnasItems.isNotEmpty) {
      await db.execute('DROP TABLE venta_items_locales');
    }
    if (columnasVentas.isNotEmpty) {
      await db.execute('DROP TABLE ventas_locales');
    }
    await db.execute(_ventas);
    await db.execute(_items);
    await db.execute(_operaciones);
    for (final fila in ventas) {
      await db.insert('ventas_locales', fila);
    }
    for (final fila in items) {
      await db.insert('venta_items_locales', fila);
    }
    for (final fila in operaciones) {
      final copia = Map<String, Object?>.from(fila);
      if (copia['reserva_id'] == null && copia['tipo'] == 'RESERVA') {
        try {
          final payload = jsonDecode(copia['payload'] as String? ?? 'null');
          final id = payload is Map ? payload['client_key'] : null;
          if (id is String &&
              (await db.query(
                'reservas_locales',
                columns: ['id'],
                where:
                    'id = ? AND tenant_id = ? AND usuario_id = ? AND sucursal_id = ?',
                whereArgs: [
                  id,
                  copia['tenant_id'],
                  copia['usuario_id'],
                  copia['sucursal_id'],
                ],
              )).isNotEmpty) {
            copia['reserva_id'] = id;
          }
        } on FormatException {
          /* Mantener la fila legacy para su revisión. */
        }
      }
      await db.insert('operaciones_pendientes', copia);
    }
    final historial = await _columnas(db, 'historial_sync');
    final filasHistorial = historial.isEmpty
        ? <Map<String, Object?>>[]
        : await db.query('historial_sync');
    if (historial.isNotEmpty) await db.execute('DROP TABLE historial_sync');
    await db.execute(
      '''CREATE TABLE historial_sync (id INTEGER PRIMARY KEY AUTOINCREMENT, iniciado_en TEXT NOT NULL, terminado_en TEXT, enviadas INTEGER NOT NULL, confirmadas INTEGER NOT NULL, conflictos INTEGER NOT NULL, rechazadas INTEGER NOT NULL, error TEXT, codigo_error TEXT, http_status INTEGER, request_id TEXT, lote_id TEXT)''',
    );
    for (final fila in filasHistorial) {
      await db.insert('historial_sync', fila);
    }
    await db.execute(
      'CREATE INDEX IF NOT EXISTS ix_variantes_sku ON variantes(sku)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS ix_operaciones_estado ON operaciones_pendientes(estado)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS cajas_sucursal ON cajas(sucursal_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS ventas_estado ON ventas_locales(estado)',
    );
  }
}
