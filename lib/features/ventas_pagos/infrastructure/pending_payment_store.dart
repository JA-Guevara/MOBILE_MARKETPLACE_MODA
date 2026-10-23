import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Conserva el pedido que debe verificarse al volver del navegador de Stripe.
class PendingPaymentStore {
  PendingPaymentStore([FlutterSecureStorage? storage])
      : _storage = storage ?? const FlutterSecureStorage(
          aOptions: AndroidOptions(encryptedSharedPreferences: true),
        );

  static const _key = 'fashionstore.pending_payment_order';
  final FlutterSecureStorage _storage;
  String? _enMemoria;

  Future<String?> read() async {
    try {
      return await _storage.read(key: _key) ?? _enMemoria;
    } catch (_) {
      return _enMemoria;
    }
  }

  Future<void> save(String orderId) async {
    _enMemoria = orderId;
    try {
      await _storage.write(key: _key, value: orderId);
    } catch (_) {
      // Con el almacén bloqueado, al menos se recupera al volver a esta sesión.
    }
  }

  Future<void> clear() async {
    _enMemoria = null;
    try {
      await _storage.delete(key: _key);
    } catch (_) {
      // Si el borrado falla, la próxima consulta es idempotente.
    }
  }
}

final pendingPaymentStoreProvider = Provider<PendingPaymentStore>(
  (ref) => PendingPaymentStore(),
);
