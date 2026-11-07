import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/offline/base_local.dart';
import '../../../core/network/api_exception.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/auth_interceptor.dart';
import '../../../core/network/session_link.dart';
import '../../../core/storage/token_store.dart';
import '../domain/usuario.dart';
import '../infrastructure/auth_api.dart';

/// Estado de la sesión que ve la interfaz.
class EstadoSesion {
  const EstadoSesion({
    this.usuario,
    this.restaurando = true,
    this.sinConexion = false,
    this.lifecycleState = 'active',
    this.graceUntil,
    this.readOnlySince,
    this.soloLecturaPorSuscripcion = false,
    this.mensajeSoloLectura,
  });
  final bool sinConexion;

  /// Quién está dentro. `null` es visitante: el catálogo igual se puede ver.
  final Usuario? usuario;

  /// Mientras es `true` todavía se está probando el refresh guardado, así que
  /// la app no debe mandar a iniciar sesión: sería un parpadeo en cada arranque.
  final bool restaurando;

  final String lifecycleState;
  final String? graceUntil;
  final String? readOnlySince;
  final bool soloLecturaPorSuscripcion;
  final String? mensajeSoloLectura;

  bool get autenticado => usuario != null && !sinConexion;

  bool get soloLectura =>
      soloLecturaPorSuscripcion ||
      lifecycleState == 'read_only' ||
      lifecycleState == 'canceled' ||
      (usuario?.suscripcion != null &&
          usuario!.suscripcion!.soloLectura &&
          lifecycleState != 'grace');

  bool get enGracia => lifecycleState == 'grace';

  bool get porVencer =>
      lifecycleState == 'expiring' ||
      (usuario?.suscripcion != null &&
          usuario!.suscripcion!.diasRestantes <= 3 &&
          usuario!.suscripcion!.diasRestantes >= 0 &&
          lifecycleState != 'grace' &&
          !soloLectura);

  EstadoSesion copyWith({
    Usuario? usuario,
    bool? restaurando,
    bool? sinConexion,
    String? lifecycleState,
    String? graceUntil,
    String? readOnlySince,
    bool? soloLecturaPorSuscripcion,
    String? mensajeSoloLectura,
  }) => EstadoSesion(
    usuario: usuario ?? this.usuario,
    restaurando: restaurando ?? this.restaurando,
    sinConexion: sinConexion ?? this.sinConexion,
    lifecycleState: lifecycleState ?? this.lifecycleState,
    graceUntil: graceUntil ?? this.graceUntil,
    readOnlySince: readOnlySince ?? this.readOnlySince,
    soloLecturaPorSuscripcion:
        soloLecturaPorSuscripcion ?? this.soloLecturaPorSuscripcion,
    mensajeSoloLectura: mensajeSoloLectura ?? this.mensajeSoloLectura,
  );
}

/// Dueño de la sesión: tokens, usuario y renovación.
///
/// El access token vive solo acá, en memoria. El refresh se persiste cifrado
/// para poder reabrir la app sin volver a escribir la contraseña.
class SessionController extends StateNotifier<EstadoSesion> {
  SessionController(
    this._api,
    this._store, {
    BaseLocal? baseLocal,
    ApiClient? apiClient,
  }) : _base = baseLocal,
       _client = apiClient,
       super(const EstadoSesion());
  final BaseLocal? _base;
  final ApiClient? _client;

  final AuthApi _api;
  final TokenStore _store;

  String? _accessToken;
  String? _refreshToken;
  Timer? _subscriptionTimer;

  String? get accessToken => _accessToken;
  String? get tenantSlug => state.usuario?.empresa?.slug;

  @override
  void dispose() {
    _detenerTemporizadorSuscripcion();
    super.dispose();
  }

  void _iniciarTemporizadorSuscripcion() {
    _subscriptionTimer?.cancel();
    _subscriptionTimer = Timer.periodic(const Duration(minutes: 30), (_) {
      refrescarSuscripcion();
    });
  }

  void _detenerTemporizadorSuscripcion() {
    _subscriptionTimer?.cancel();
    _subscriptionTimer = null;
  }

  void marcarSoloLectura([String? mensaje]) {
    state = state.copyWith(
      lifecycleState: 'read_only',
      soloLecturaPorSuscripcion: true,
      mensajeSoloLectura:
          mensaje ??
          'Modo solo lectura activado. Las ventas y reservas están bloqueadas.',
    );
  }

  void manejarError403(dynamic error) {
    if (error is ApiException && error.statusCode == 403) {
      if (error.message.contains('subscription_read_only') ||
          error.message.contains('solo lectura') ||
          error.message.contains('solo_lectura')) {
        marcarSoloLectura(error.message);
      }
    } else if (error is DioException && error.response?.statusCode == 403) {
      final msg = error.response?.data?.toString() ?? '';
      if (msg.contains('subscription_read_only') ||
          msg.contains('solo lectura') ||
          msg.contains('solo_lectura')) {
        marcarSoloLectura('Modo solo lectura: $msg');
      }
    }
  }

  Future<void> refrescarSuscripcion() async {
    if (state.usuario == null ||
        state.usuario?.empresa == null ||
        state.usuario?.puede('my_subscription.read') != true ||
        state.sinConexion) {
      return;
    }
    final client = _client;
    if (client == null) return;
    try {
      final res = await client.get<Map<String, dynamic>>(
        '/tenant/subscription',
      );
      final current = res['current'] is Map<String, dynamic>
          ? res['current'] as Map<String, dynamic>
          : res;
      final lState = current['lifecycle_state'] as String? ?? 'active';
      final grace = current['grace_until'] as String?;
      final roSince = current['read_only_since'] as String?;
      final isReadOnly = lState == 'read_only' || lState == 'canceled';

      state = state.copyWith(
        lifecycleState: lState,
        graceUntil: grace,
        readOnlySince: roSince,
        soloLecturaPorSuscripcion: isReadOnly,
        mensajeSoloLectura: isReadOnly
            ? 'Tu suscripción está vencida y en modo solo lectura.'
            : null,
      );
    } on ApiException catch (e) {
      if (e.statusCode == 403 &&
          (e.message.contains('subscription_read_only') ||
              e.message.contains('solo lectura'))) {
        marcarSoloLectura(
          'Tu suscripción está vencida y en modo solo lectura.',
        );
      }
    } catch (_) {
      // Sin conexión o fallo temporal: se conserva el estado actual
    }
  }

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
      state = state.copyWith(restaurando: false);
      if (state.usuario != null && !state.sinConexion) {
        _iniciarTemporizadorSuscripcion();
        unawaited(refrescarSuscripcion());
      }
    }
  }

  Future<void> iniciarSesion(
    String email,
    String password, {
    String? empresaSlug,
    bool plataforma = false,
  }) async {
    final sesion = empresaSlug == null && !plataforma
        ? await _api.iniciarSesion(email, password)
        : await _api.iniciarSesionEnEmpresa(
            email,
            password,
            empresaSlug: empresaSlug,
            plataforma: plataforma,
          );
    await _aplicar(sesion);
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
      final isRo = usuario.suscripcion?.soloLectura == true;
      state = state.copyWith(
        usuario: usuario,
        restaurando: false,
        soloLecturaPorSuscripcion: isRo || state.soloLecturaPorSuscripcion,
      );
      await _guardarPerfil(usuario);
      unawaited(refrescarSuscripcion());
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
    _detenerTemporizadorSuscripcion();
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
    final isRo = sesion.usuario.suscripcion?.soloLectura == true;
    state = EstadoSesion(
      usuario: sesion.usuario,
      restaurando: false,
      lifecycleState: isRo ? 'read_only' : 'active',
      soloLecturaPorSuscripcion: isRo,
      mensajeSoloLectura: isRo
          ? 'Tu suscripción está vencida y en modo solo lectura.'
          : null,
    );
    await _guardarPerfil(sesion.usuario);
    if (sesion.usuario.puede('my_subscription.read')) {
      _iniciarTemporizadorSuscripcion();
    } else {
      _detenerTemporizadorSuscripcion();
    }
    unawaited(refrescarSuscripcion());
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

// El enlace no depende del controlador. Los interceptores consultan callbacks
// enlazados al construir la sesión, sin leer sessionProvider desde el cliente.
final _sessionLinkProvider = Provider<SessionLink>((ref) => SessionLink());
final tiendaPublicaSeleccionadaProvider =
    StateProvider<({String slug, String nombre})?>((ref) => null);

/// Invalida los datos privados al cambiar de cuenta o empresa, no al renovar
/// un token ni al actualizar la vigencia de la misma suscripción.
final identidadSesionProvider = Provider(
  (ref) => ref.watch(
    sessionProvider.select((s) => (s.usuario?.id, s.usuario?.empresa?.id)),
  ),
);

final tiendaCatalogoProvider = Provider<String?>((ref) {
  final seleccion = ref.watch(tiendaPublicaSeleccionadaProvider);
  final empresa = ref.watch(sessionProvider.select((s) => s.usuario?.empresa));
  return empresa?.slug ?? seleccion?.slug;
});

final tiendasPublicasProvider =
    FutureProvider<List<({String slug, String nombre})>>((ref) async {
      final client = ref.watch(apiClientProvider);
      final response = await client.get<Map<String, dynamic>>(
        '/public/stores',
        query: {'page_size': 100},
      );
      return (response['items'] as List<dynamic>? ?? []).map((value) {
        final store = value as Map<String, dynamic>;
        return (
          slug: store['slug'] as String,
          nombre: store['trade_name'] as String,
        );
      }).toList();
    });

final Provider<ApiClient> apiClientProvider = Provider<ApiClient>((ref) {
  final cliente = ApiClient();
  final session = ref.watch(_sessionLinkProvider);
  cliente.dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) {
        final path = options.path;
        final storefront =
            path.startsWith('/catalog/') ||
            path.startsWith('/commerce/') ||
            path.startsWith('/vestidor/') ||
            path.startsWith('/tryon-ai/') ||
            path == '/auth/register';
        final selected = storefront
            ? ref.read(tiendaPublicaSeleccionadaProvider)?.slug
            : null;
        final slug = session.tenantSlug ?? selected;
        if (slug != null && slug.isNotEmpty) {
          options.headers['X-Tenant-Slug'] = slug;
        } else {
          // Un visitante sin tienda no consulta el catálogo de otra empresa
          // por un valor implícito de la compilación.
          options.headers.remove('X-Tenant-Slug');
        }
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
      accessToken: () => session.accessToken,
      refresh: session.refresh,
      onSessionExpired: session.expired,
    ),
  );
  return cliente;
});

final Provider<AuthApi> authApiProvider = Provider<AuthApi>(
  (ref) => AuthApi(ref.watch(apiClientProvider)),
);

final StateNotifierProvider<SessionController, EstadoSesion> sessionProvider =
    StateNotifierProvider<SessionController, EstadoSesion>((ref) {
      final session = SessionController(
        ref.watch(authApiProvider),
        ref.watch(tokenStoreProvider),
        baseLocal: ref.watch(baseLocalProvider),
        apiClient: ref.watch(apiClientProvider),
      );
      final link = ref.watch(_sessionLinkProvider);
      link.bind(
        owner: session,
        token: () => session.accessToken,
        tenant: () => session.tenantSlug,
        refresh: session.renovar,
        expired: session.limpiar,
      );
      ref.onDispose(() => link.unbind(session));
      return session;
    });
