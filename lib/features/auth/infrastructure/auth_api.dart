import 'package:dio/dio.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../domain/usuario.dart';

/// Llamadas al módulo `/auth` del backend. No guarda estado: solo traduce
/// JSON a objetos del dominio.
class AuthApi {
  const AuthApi(this._api);

  final ApiClient _api;

  Future<Sesion> iniciarSesion(String email, String password) async {
    final data = await _api.post<Map<String, dynamic>>(
      '/auth/login',
      body: {'email': email.trim().toLowerCase(), 'password': password},
    );
    return Sesion.desdeJson(data);
  }

  Future<Sesion> renovar(String refreshToken) async {
    final data = await _api.post<Map<String, dynamic>>(
      '/auth/refresh',
      body: {'refresh_token': refreshToken},
    );
    return Sesion.desdeJson(data);
  }

  Future<void> cerrarSesion(String refreshToken) =>
      _api.post<dynamic>('/auth/logout', body: {'refresh_token': refreshToken});

  Future<Usuario> yo() async {
    final data = await _api.get<Map<String, dynamic>>('/auth/me');
    return Usuario.desdeJson(data);
  }

  Future<String> registrarse({
    required String email,
    required String password,
    required String nombre,
    required String apellido,
    String? telefono,
  }) =>
      _mensaje('/auth/register', body: {
        'email': email.trim().toLowerCase(),
        'password': password,
        'first_name': nombre,
        'last_name': apellido,
        if (telefono != null && telefono.isNotEmpty) 'phone': telefono,
      });

  Future<String> recuperarContrasena(String email) =>
      _mensaje('/auth/forgot-password', body: {'email': email.trim().toLowerCase()});

  Future<String> restablecerContrasena(String token, String nuevaContrasena) =>
      _mensaje('/auth/reset-password', body: {'token': token, 'new_password': nuevaContrasena});

  Future<String> cambiarContrasena(String contrasenaActual, String nuevaContrasena) =>
      _mensaje('/auth/change-password',
          body: {'current_password': contrasenaActual, 'new_password': nuevaContrasena});

  Future<String> verificarCorreo(String token) =>
      _mensaje('/auth/verify-email', body: {'token': token});

  Future<String> reenviarVerificacion(String email) =>
      _mensaje('/auth/resend-verification', body: {'email': email.trim().toLowerCase()});

  /// Ejecuta el POST y devuelve el `message` del envoltorio. Los endpoints que
  /// no están acá devuelven datos para parsear; estos solo confirman una
  /// operación (register, recuperar, verificar…) y el mensaje es lo que la
  /// pantalla muestra como éxito.
  Future<String> _mensaje(String path, {Object? body}) async {
    try {
      final respuesta = await _api.dio.post<Map<String, dynamic>>(path, data: body);
      return respuesta.data?['message'] as String? ?? '';
    } on DioException catch (error) {
      throw ApiException.from(error);
    }
  }
}
