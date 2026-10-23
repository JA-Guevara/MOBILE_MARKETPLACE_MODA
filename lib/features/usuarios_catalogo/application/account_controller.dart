import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../domain/address.dart';
import '../infrastructure/direcciones_api.dart';
import 'session_controller.dart';

/// Estado de la cuenta que muestra la pantalla «Mi cuenta».
class EstadoCuenta {
  const EstadoCuenta({this.direcciones = const [], this.cargando = true});

  final List<Direccion> direcciones;
  final bool cargando;
}

/// Dueño de las acciones sobre la cuenta: perfil y direcciones.
///
/// Equivale a `account-page.component.ts` de la web: la parte de sesión sigue
/// en [SessionController] y acá queda lo que toca `/commerce/profile` y
/// `/users/me/addresses`. Los errores se dejan subir como `ApiException` para
/// que la pantalla decida cómo mostrarlos.
class AccountController extends StateNotifier<EstadoCuenta> {
  AccountController(this._api, this._direcciones) : super(const EstadoCuenta());

  final ApiClient _api;
  final DireccionesApi _direcciones;

  Future<void> cargarDirecciones() async {
    state = EstadoCuenta(direcciones: state.direcciones, cargando: true);
    try {
      state = EstadoCuenta(direcciones: await _direcciones.listar(), cargando: false);
    } catch (_) {
      // El mensaje lo muestra la pantalla; lo que no puede quedar es el
      // `cargando` prendido: la seccion de direcciones se quedaba girando
      // para siempre cuando la peticion fallaba.
      state = EstadoCuenta(direcciones: state.direcciones, cargando: false);
      rethrow;
    }
  }

  /// El backend deja una sola predeterminada: al marcar esta, limpia el resto.
  Future<void> marcarPredeterminada(Direccion direccion) async {
    await _direcciones.actualizar(direccion.id, {'is_default': true});
    await cargarDirecciones();
  }

  Future<void> guardarPerfil({
    required String nombre,
    required String apellido,
    String? telefono,
  }) =>
      _api.patch<dynamic>(
        '/commerce/profile',
        body: {
          'first_name': nombre,
          'last_name': apellido,
          if (telefono != null && telefono.isNotEmpty) 'phone': telefono,
        },
      );
}

final StateNotifierProvider<AccountController, EstadoCuenta> accountControllerProvider =
    StateNotifierProvider<AccountController, EstadoCuenta>((ref) => AccountController(
          ref.watch(apiClientProvider),
          ref.watch(direccionesApiProvider),
        ));
