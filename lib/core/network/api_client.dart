import 'package:dio/dio.dart';

import '../config/environment.dart';
import 'api_exception.dart';
import 'log_interceptor.dart';

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
              // límite la pantalla se queda cargando para siempre. 30 s y no
              // 15: el backend de Railway se duerme y el primer pedido del día
              // paga el arranque del contenedor, que pasa de los 15 s y hacía
              // fallar la primera pantalla aunque el servidor estuviera bien.
              connectTimeout: const Duration(seconds: 30),
              receiveTimeout: const Duration(seconds: 30),
              headers: {'Accept': 'application/json'},
              // El error se traduce acá, no en cada pantalla.
              validateStatus: (status) => status != null && status < 400,
            ));

  final Dio dio;

  /// Enciende el registro de peticiones en la consola. Se llama al construir
  /// el cliente y no hace nada en release.
  void registrarEnConsola() {
    if (RegistroInterceptor.habilitado) {
      dio.interceptors.add(const RegistroInterceptor());
    }
  }

  Future<T> get<T>(String path, {Map<String, dynamic>? query}) =>
      _pedir<T>(() => dio.get(path, queryParameters: _limpiar(query)));

  Future<T> post<T>(String path, {Object? body, Map<String, dynamic>? query}) =>
      _pedir<T>(() => dio.post(path, data: body, queryParameters: _limpiar(query)));

  Future<T> put<T>(String path, {Object? body}) => _pedir<T>(() => dio.put(path, data: body));

  Future<T> patch<T>(String path, {Object? body}) => _pedir<T>(() => dio.patch(path, data: body));

  Future<T> delete<T>(String path, {Object? body}) =>
      _pedir<T>(() => dio.delete(path, data: body));

  /// Para comandos cuyo contrato confirma con `{ success: true, data: null }`.
  /// No los pasa por el deserializador genérico: convertir `null` a un mapa
  /// fue la causa de que el botón del carrito pareciera no hacer nada.
  Future<void> putSinContenido(String path, {Object? body}) =>
      _enviarSinContenido(() => dio.put(path, data: body));

  Future<void> deleteSinContenido(String path, {Object? body}) =>
      _enviarSinContenido(() => dio.delete(path, data: body));

  /// Sube un `FormData` (multipart): imágenes, Excel, la foto del probador IA.
  /// Devuelve el `data` del envoltorio como el resto de los endpoints.
  Future<T> subir<T>(String path, FormData datos, {Map<String, dynamic>? query}) =>
      _pedir<T>(() => dio.post(path, data: datos, queryParameters: _limpiar(query)));

  /// Descarga un archivo (plantilla Excel, exportación, comprobante PDF) a un
  /// archivo local. Usa `dio.download` porque el servidor responde binario,
  /// sin envoltorio y con `Content-Disposition: attachment`.
  Future<void> descargar(
    String path,
    String destino, {
    Map<String, dynamic>? query,
  }) async {
    try {
      await dio.download(
        path,
        destino,
        queryParameters: _limpiar(query),
      );
    } on DioException catch (error) {
      throw ApiException.from(error);
    }
  }

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

  Future<void> _enviarSinContenido(
    Future<Response<dynamic>> Function() peticion,
  ) async {
    try {
      await peticion();
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

