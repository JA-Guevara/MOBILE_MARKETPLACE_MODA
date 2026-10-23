import 'package:sqflite/sqflite.dart';

/// Esquema compartido con la PWA; los tokens nunca se guardan en esta base.
class EsquemaLocal {
  static const version = 1;
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

  static Future<void> crear(Database db, int version) async {
    // onCreate ya se ejecuta en una transacción de sqflite.
    final batch = db.batch();
    for (final sql in tablas) {
      batch.execute(sql);
    }
    batch.execute('CREATE INDEX variantes_producto ON variantes(producto_id)');
    batch.execute(
      'CREATE INDEX operaciones_estado ON operaciones_pendientes(estado)',
    );
    await batch.commit(noResult: true);
  }
}
