import 'dart:developer' as developer;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

/// Deja en la consola qué pidió la app y qué contestó el servidor.
///
/// Sin esto el único lugar donde se ve un fallo de red es la pantalla del
/// teléfono, que no queda registrada en ningún lado: se sabe que «algo falló»
/// pero no cuál de las peticiones ni por qué.
///
/// **Solo registra método, ruta, estado y tipo de error.** Nunca el cuerpo ni
/// las cabeceras: por ahí viajan la contraseña y el bearer, y la consola de
/// `flutter run` queda en el historial de la terminal.
///
/// En compilaciones de release no se instala, así que no cuesta nada.
class RegistroInterceptor extends Interceptor {
  const RegistroInterceptor();

  static bool get habilitado => kDebugMode;

  void _linea(String texto) => developer.log(texto, name: 'api');

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    _linea('→ ${options.method} ${options.path}');
    handler.next(options);
  }

  @override
  void onResponse(Response<dynamic> response, ResponseInterceptorHandler handler) {
    _linea('← ${response.statusCode} ${response.requestOptions.path}');
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final estado = err.response?.statusCode;
    // Sin `statusCode` el servidor no contestó: el `type` de Dio es lo único
    // que distingue un tiempo agotado de un corte de red o un certificado.
    _linea('✗ ${estado ?? err.type.name} ${err.requestOptions.path}'
        '${estado == null ? ' · ${err.message}' : ''}');
    handler.next(err);
  }
}
