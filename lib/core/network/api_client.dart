import 'package:dio/dio.dart';

import '../config/environment.dart';
import 'api_exception.dart';

/// Único punto por donde la app habla con el backend.
///
/// Es el par de `api.service.ts` del frontend web: agrega el prefijo, desarma
/// el envoltorio `{ success, message, data }` y convierte cualquier fallo en un
/// [ApiException] con mensaje en español. Ninguna pantalla debería usar `Dio`
/// directamente.
class ApiClient {
  ApiClient({Dio? dio})
      : dio = dio ??
            Dio(BaseOptions(
              baseUrl: Environment.apiUrl,
              // Un teléfono cambia de red en medio de una petición; sin tiempo
              // límite la pantalla se queda cargando para siempre.
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 30),
              headers: {'Accept': 'application/json'},
              // El error se traduce acá, no en cada pantalla.
              validateStatus: (status) => status != null && status < 400,
            ));

  final Dio dio;

  Future<T> get<T>(String path, {Map<String, dynamic>? query}) =>
      _pedir<T>(() => dio.get(path, queryParameters: _limpiar(query)));

  Future<T> post<T>(String path, {Object? body, Map<String, dynamic>? query}) =>
      _pedir<T>(() => dio.post(path, data: body, queryParameters: _limpiar(query)));

  Future<T> put<T>(String path, {Object? body}) => _pedir<T>(() => dio.put(path, data: body));

  Future<T> patch<T>(String path, {Object? body}) => _pedir<T>(() => dio.patch(path, data: body));

  Future<T> delete<T>(String path, {Object? body}) =>
      _pedir<T>(() => dio.delete(path, data: body));

  /// Ejecuta la petición y devuelve solo el `data` del envoltorio.
  Future<T> _pedir<T>(Future<Response<dynamic>> Function() peticion) async {
    try {
      final respuesta = await peticion();
      final cuerpo = respuesta.data;
      if (cuerpo is Map<String, dynamic> && cuerpo.containsKey('data')) {
        return cuerpo['data'] as T;
      }
      // Algunos endpoints (webhooks, health) responden sin envoltorio.
      return cuerpo as T;
    } on DioException catch (error) {
      throw ApiException.from(error);
    }
  }

  /// Quita los parámetros vacíos y manda las listas repetidas (`?id=a&id=b`),
  /// que es lo que espera FastAPI; unirlas por coma llega como un valor único
  /// e inválido. Es la misma corrección que ya tiene el frontend web.
  Map<String, dynamic>? _limpiar(Map<String, dynamic>? query) {
    if (query == null) return null;
    final limpio = <String, dynamic>{};
    query.forEach((clave, valor) {
      if (valor == null || valor == '') return;
      if (valor is List) {
        final items = valor.where((v) => v != null && v != '').toList();
        if (items.isNotEmpty) limpio[clave] = items;
        return;
      }
      limpio[clave] = valor;
    });
    return limpio;
  }
}
