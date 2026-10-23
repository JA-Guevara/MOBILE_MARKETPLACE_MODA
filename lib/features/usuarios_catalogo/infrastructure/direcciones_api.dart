import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../application/session_controller.dart';
import '../domain/address.dart';

/// Direcciones del perfil (`/users/me/addresses`).
///
/// Vive aparte del controlador de la cuenta porque tres pantallas distintas
/// las necesitan —«Mi cuenta», el ABM de direcciones y el carrito, que ofrece
/// las guardadas al comprar— y duplicar las rutas en cada una es la forma
/// segura de que un día dejen de coincidir.
class DireccionesApi {
  const DireccionesApi(this._api);

  final ApiClient _api;

  Future<List<Direccion>> listar() async {
    final filas = await _api.get<List<dynamic>>('/users/me/addresses');
    return filas
        .map((fila) => Direccion.desdeJson(fila as Map<String, dynamic>))
        .toList();
  }

  Future<Direccion> crear(Map<String, dynamic> datos) async {
    final json = await _api.post<Map<String, dynamic>>(
      '/users/me/addresses',
      body: datos,
    );
    return Direccion.desdeJson(json);
  }

  Future<Direccion> actualizar(String id, Map<String, dynamic> datos) async {
    final json = await _api.patch<Map<String, dynamic>>(
      '/users/me/addresses/$id',
      body: datos,
    );
    return Direccion.desdeJson(json);
  }

  Future<void> eliminar(String id) =>
      _api.delete<void>('/users/me/addresses/$id');

  /// Cuerpo que espera el backend. Se arma acá y no en cada pantalla para que
  /// los nombres de los campos (`recipient_name`, `address_line`) estén
  /// escritos una sola vez.
  static Map<String, dynamic> cuerpo({
    required String etiqueta,
    required String destinatario,
    required String telefono,
    required String linea,
    required String ciudad,
    String? codigoPostal,
    String pais = 'BO',
    bool? predeterminada,
  }) =>
      {
        'label': etiqueta,
        'recipient_name': destinatario,
        'phone': telefono,
        'address_line': linea,
        'city': ciudad,
        'postal_code': (codigoPostal?.isEmpty ?? true) ? null : codigoPostal,
        'country': pais.isEmpty ? 'BO' : pais,
        if (predeterminada != null) 'is_default': predeterminada,
      };
}

final Provider<DireccionesApi> direccionesApiProvider = Provider<DireccionesApi>(
    (ref) => DireccionesApi(ref.watch(apiClientProvider)));
