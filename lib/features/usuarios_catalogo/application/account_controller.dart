import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../domain/address.dart';
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
  AccountController(this._api) : super(const EstadoCuenta());

  final ApiClient _api;

  Future<void> cargarDirecciones() async {
    state = EstadoCuenta(direcciones: state.direcciones, cargando: true);
    final filas = await _api.get<List<dynamic>>('/users/me/addresses');
    state = EstadoCuenta(
      direcciones: filas
          .map((fila) => Direccion.desdeJson(fila as Map<String, dynamic>))
          .toList(),
      cargando: false,
    );
  }

  /// El backend deja una sola predeterminada: al marcar esta, limpia el resto.
  Future<void> marcarPredeterminada(Direccion direccion) async {
    await _api.patch<dynamic>(
      '/users/me/addresses/${direccion.id}',
      body: {'is_default': true},
    );
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
    StateNotifierProvider<AccountController, EstadoCuenta>(
        (ref) => AccountController(ref.watch(apiClientProvider)));
