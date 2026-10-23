import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/offline/base_local.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/config/environment.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/auth_interceptor.dart';
import '../../../core/storage/token_store.dart';
import '../domain/usuario.dart';
import '../infrastructure/auth_api.dart';

/// Estado de la sesión que ve la interfaz.
class EstadoSesion {
  const EstadoSesion({
    this.usuario,
    this.restaurando = true,
    this.sinConexion = false,
  });
  final bool sinConexion;

  /// Quién está dentro. `null` es visitante: el catálogo igual se puede ver.
  final Usuario? usuario;

  /// Mientras es `true` todavía se está probando el refresh guardado, así que
  /// la app no debe mandar a iniciar sesión: sería un parpadeo en cada arranque.
  final bool restaurando;

  bool get autenticado => usuario != null && !sinConexion;
}

/// Dueño de la sesión: tokens, usuario y renovación.
///
/// El access token vive solo acá, en memoria. El refresh se persiste cifrado
/// para poder reabrir la app sin volver a escribir la contraseña.
class SessionController extends StateNotifier<EstadoSesion> {
  SessionController(this._api, this._store, {BaseLocal? baseLocal})
    : _base = baseLocal,
      super(const EstadoSesion());
  final BaseLocal? _base;

  final AuthApi _api;
  final TokenStore _store;

  String? _accessToken;
  String? _refreshToken;

  String? get accessToken => _accessToken;

  /// Reabre la sesión guardada al arrancar la app.
  Future<void> restaurar() async {
    final guardado = await _store.leerRefresh();
    if (guardado == null) {
      state = const EstadoSesion(restaurando: false);
      return;
    }
    try {
      await _aplicar(await _api.renovar(guardado));
    } on ApiException catch (error) {
      if (error.sinConexion && await _restaurarPerfil()) return;
      await limpiar();
    } catch (_) {
      // Un refresh vencido o revocado no es un error que mostrar: simplemente
      // no hay sesión y la app arranca como visitante.
      await limpiar();
    } finally {
      state = EstadoSesion(
        usuario: state.usuario,
        restaurando: false,
        sinConexion: state.sinConexion,
      );
    }
  }

  Future<void> iniciarSesion(String email, String password) async {
    await _aplicar(await _api.iniciarSesion(email, password));
  }

  /// Crea la cuenta y devuelve el mensaje del servidor. No abre sesión: el
  /// backend pide verificar el correo antes, igual que en la web.
  Future<String> registrarse({
    required String email,
    required String password,
    required String nombre,
    required String apellido,
    String? telefono,
  }) => _api.registrarse(
    email: email,
    password: password,
    nombre: nombre,
    apellido: apellido,
    telefono: telefono,
  );

  Future<String> recuperarContrasena(String email) =>
      _api.recuperarContrasena(email);

  /// Confirma el enlace del correo y elige contraseña nueva. La sesión se
  /// cierra: el token del correo no era una sesión.
  Future<String> restablecerContrasena(
    String token,
    String nuevaContrasena,
  ) async {
    final mensaje = await _api.restablecerContrasena(token, nuevaContrasena);
    await limpiar();
    return mensaje;
  }

  /// Cambia la contraseña estando adentro. El backend dice «inicie sesión
  /// nuevamente», así que la sesión se limpia igual que en la web.
  Future<String> cambiarContrasena(
    String contrasenaActual,
    String nuevaContrasena,
  ) async {
    final mensaje = await _api.cambiarContrasena(
      contrasenaActual,
      nuevaContrasena,
    );
    await limpiar();
    return mensaje;
  }

  Future<String> verificarCorreo(String token) async {
    final mensaje = await _api.verificarCorreo(token);
    // Si había sesión abierta, reflejar de inmediato que ya está verificado.
    if (state.usuario != null) {
      try {
        final usuario = await _api.yo();
        state = EstadoSesion(usuario: usuario, restaurando: false);
      } catch (_) {
        // Sin conexión, la próxima vez que se abra la app se refresca solo.
      }
    }
    return mensaje;
  }

  Future<String> reenviarVerificacion([String? email]) =>
      _api.reenviarVerificacion(email ?? state.usuario?.email ?? '');

  /// Vuelve a pedir `/auth/me` para reflejar cambios hechos por otra pantalla
  /// (perfil verificado, datos editados).
  Future<void> recargarUsuario() async {
    try {
      final usuario = await _api.yo();
      state = EstadoSesion(usuario: usuario, restaurando: false);
      await _guardarPerfil(usuario);
    } catch (_) {
      // Sin conexión se queda el caché de la memoria; no hay nada que avisar.
    }
  }

  /// Renueva el token. Devuelve si se pudo; lo usa [AuthInterceptor] ante un 401.
  Future<bool> renovar() async {
    final token = _refreshToken ?? await _store.leerRefresh();
    if (token == null) return false;
    try {
      await _aplicar(await _api.renovar(token));
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> cerrarSesion() async {
    final token = _refreshToken;
    if (token != null) {
      try {
        await _api.cerrarSesion(token);
      } catch (_) {
        // Si el servidor no responde, la sesión igual se cierra en el teléfono.
      }
    }
    await limpiar();
  }

  Future<void> limpiar() async {
    _accessToken = null;
    _refreshToken = null;
    await _store.limpiar();
    try {
      await _base?.borrarMeta('usuario_offline');
    } catch (_) {
      // La sesión remota se cierra aunque el almacenamiento local no esté disponible.
    }
    state = const EstadoSesion(restaurando: false);
  }

  Future<void> _aplicar(Sesion sesion) async {
    _accessToken = sesion.accessToken;
    _refreshToken = sesion.refreshToken;
    await _store.guardarRefresh(sesion.refreshToken);
    state = EstadoSesion(usuario: sesion.usuario, restaurando: false);
    await _guardarPerfil(sesion.usuario);
  }

  Future<void> _guardarPerfil(Usuario usuario) async {
    try {
      await _base?.guardarMeta('usuario_offline', jsonEncode(usuario.aJson()));
    } catch (_) {
      // El caché es opcional para iniciar sesión en línea. Preparar el modo
      // sin conexión muestra el error si la base local no puede abrirse.
    }
  }

  Future<bool> _restaurarPerfil() async {
    try {
      final json = await _base?.leerMeta('usuario_offline');
      if (json == null) return false;
      final usuario = Usuario.desdeJson(
        jsonDecode(json) as Map<String, dynamic>,
      );
      if (usuario.empresa == null || usuario.empresa!.estado != 'ACTIVA') {
        return false;
      }
      _accessToken = null;
      _refreshToken = null;
      state = EstadoSesion(
        usuario: usuario,
        restaurando: false,
        sinConexion: true,
      );
      return true;
    } catch (_) {
      return false;
    }
  }
}

// --- Inyección de dependencias -------------------------------------------
//
// Riverpod cumple acá el papel de los `providedIn: 'root'` de Angular: un
// único cliente HTTP y una única sesión para toda la aplicación.

final Provider<TokenStore> tokenStoreProvider = Provider<TokenStore>(
  (ref) => TokenStore(),
);

// El cliente y la sesión se referencian mutuamente, pero no hay ciclo: el
// cliente solo *construye* el interceptor con funciones, y esas funciones leen
// la sesión recién cuando sale una petición, con todo ya construido.
// El tipo va escrito a mano porque los tres proveedores se referencian entre
// sí y Dart no puede inferirlo solo.
final Provider<ApiClient> apiClientProvider = Provider<ApiClient>((ref) {
  final cliente = ApiClient();
  cliente.dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) {
        options.headers['X-Tenant-Slug'] =
            ref.read(sessionProvider).usuario?.empresa?.slug ??
            Environment.tenantSlug;
        handler.next(options);
      },
    ),
  );
  // El registro va primero para que la linea del pedido salga antes del
  // bearer y del reintento por 401; asi el orden en consola es el real.
  cliente.registrarEnConsola();
  cliente.dio.interceptors.add(
    AuthInterceptor(
      dio: cliente.dio,
      accessToken: () => ref.read(sessionProvider.notifier).accessToken,
      refresh: () => ref.read(sessionProvider.notifier).renovar(),
      onSessionExpired: () => ref.read(sessionProvider.notifier).limpiar(),
    ),
  );
  return cliente;
});

final Provider<AuthApi> authApiProvider = Provider<AuthApi>(
  (ref) => AuthApi(ref.watch(apiClientProvider)),
);

final StateNotifierProvider<SessionController, EstadoSesion> sessionProvider =
    StateNotifierProvider<SessionController, EstadoSesion>((ref) {
      return SessionController(
        ref.watch(authApiProvider),
        ref.watch(tokenStoreProvider),
        baseLocal: ref.watch(baseLocalProvider),
      );
    });
