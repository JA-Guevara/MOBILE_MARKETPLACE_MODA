import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Dónde viven los tokens de sesión en el teléfono.
///
/// El **access token** se queda en memoria y muere con el proceso: es corto y
/// no vale la pena persistirlo. El **refresh token**, en cambio, es lo que
/// permite seguir con la sesión abierta al reabrir la app, así que se guarda
/// cifrado por el sistema (Keystore en Android, Keychain en iOS) y nunca en
/// `SharedPreferences`, que es texto plano legible en un equipo con root.
///
/// Es la misma decisión que toma el frontend web, que deja el access token en
/// memoria y solo persiste el refresh.
class TokenStore {
  TokenStore([FlutterSecureStorage? storage])
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
            );

  static const _clave = 'fashionstore.refresh';
  final FlutterSecureStorage _storage;

  Future<String?> leerRefresh() async {
    try {
      return await _storage.read(key: _clave);
    } catch (_) {
      // Un almacén no disponible no debe impedir usar la app: se pide login.
      return null;
    }
  }

  Future<void> guardarRefresh(String token) async {
    try {
      await _storage.write(key: _clave, value: token);
    } catch (_) {
      // Sesión solo en memoria: al cerrar la app habrá que iniciar de nuevo.
    }
  }

  Future<void> limpiar() async {
    try {
      await _storage.delete(key: _clave);
    } catch (_) {
      // Nada que borrar.
    }
  }
}
