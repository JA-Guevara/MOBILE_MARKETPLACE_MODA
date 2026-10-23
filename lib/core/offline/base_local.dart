import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';

import '../../features/ventas_pagos/infrastructure/commerce_api.dart';
import 'esquema_local.dart';

class BaseLocal {
  BaseLocal({DatabaseFactory? fabrica, String? ruta})
    : _fabrica = fabrica,
      _ruta = ruta;
  static const nombre = 'fashionstore_offline.db';
  final DatabaseFactory? _fabrica;
  final String? _ruta;
  Future<Database>? _abierta;

  Future<Database> abrir() => _abierta ??= _abrir();
  Future<Database> _abrir() async {
    try {
      final fabrica = _fabrica ?? databaseFactory;
      final ruta = _ruta ?? path.join(await fabrica.getDatabasesPath(), nombre);
      return await fabrica.openDatabase(
        ruta,
        options: OpenDatabaseOptions(
          version: EsquemaLocal.version,
          onCreate: EsquemaLocal.crear,
        ),
      );
    } catch (_) {
      _abierta = null;
      rethrow;
    }
  }

  Future<String?> leerMeta(String clave) async {
    final filas = await (await abrir()).query(
      'meta',
      where: 'clave = ?',
      whereArgs: [clave],
    );
    return filas.isEmpty ? null : filas.first['valor'] as String;
  }

  Future<void> guardarMeta(String clave, String valor) async => (await abrir())
      .insert('meta', {
        'clave': clave,
        'valor': valor,
      }, conflictAlgorithm: ConflictAlgorithm.replace)
      .then((_) {});
  Future<void> borrarMeta(String clave) async => (await abrir())
      .delete('meta', where: 'clave = ?', whereArgs: [clave])
      .then((_) {});

  Future<String> dispositivoId() async {
    final db = await abrir();
    return db.transaction((txn) async {
      final filas = await txn.query(
        'meta',
        where: 'clave = ?',
        whereArgs: ['dispositivo_id'],
      );
      if (filas.isNotEmpty) return filas.first['valor'] as String;
      final id = CommerceApi.nuevaClaveSolicitud();
      await txn.insert('meta', {'clave': 'dispositivo_id', 'valor': id});
      return id;
    });
  }

  Future<void> cerrar() async {
    final abierta = _abierta;
    _abierta = null;
    if (abierta != null) await (await abierta).close();
  }
}

final baseLocalProvider = Provider<BaseLocal>((ref) => BaseLocal());
