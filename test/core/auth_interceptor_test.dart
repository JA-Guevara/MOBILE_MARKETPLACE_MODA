import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_marketplace_moda/core/network/auth_interceptor.dart';

/// Servidor falso: responde lo que se le indique y anota qué recibió.
class _ServidorFalso implements HttpClientAdapter {
  _ServidorFalso(this.responder);

  /// Recibe el número de petición (1, 2, ...) y devuelve el estado a responder.
  final int Function(int intento, RequestOptions peticion) responder;
  final List<RequestOptions> recibidas = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    recibidas.add(options);
    final estado = responder(recibidas.length, options);
    return ResponseBody.fromString(
      jsonEncode({'success': estado < 400, 'message': '', 'data': {'ok': estado < 400}}),
      estado,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  late Dio dio;
  late _ServidorFalso servidor;
  int renovaciones = 0;
  int expiraciones = 0;
  String token = 'viejo';

  void montar({required bool renovacionFunciona, required int Function(int, RequestOptions) responder}) {
    renovaciones = 0;
    expiraciones = 0;
    token = 'viejo';
    servidor = _ServidorFalso(responder);
    dio = Dio(BaseOptions(baseUrl: 'http://test/api/v1', validateStatus: (s) => s != null && s < 400));
    dio.httpClientAdapter = servidor;
    dio.interceptors.add(AuthInterceptor(
      dio: dio,
      accessToken: () => token,
      refresh: () async {
        renovaciones++;
        if (renovacionFunciona) token = 'nuevo';
        return renovacionFunciona;
      },
      onSessionExpired: () => expiraciones++,
    ));
  }

  test('manda el bearer en cada petición', () async {
    montar(renovacionFunciona: true, responder: (_, __) => 200);
    await dio.get<dynamic>('/commerce/cart');
    expect(servidor.recibidas.single.headers['Authorization'], 'Bearer viejo');
  });

  test('ante un 401 renueva y reintenta con el token nuevo', () async {
    montar(renovacionFunciona: true, responder: (intento, _) => intento == 1 ? 401 : 200);
    final respuesta = await dio.get<dynamic>('/commerce/orders');

    expect(renovaciones, 1);
    expect(servidor.recibidas.length, 2);
    expect(servidor.recibidas.last.headers['Authorization'], 'Bearer nuevo');
    expect(respuesta.statusCode, 200);
    expect(expiraciones, 0);
  });

  test('si la renovación falla, la sesión se da por terminada sin reintentar', () async {
    montar(renovacionFunciona: false, responder: (_, __) => 401);
    await expectLater(dio.get<dynamic>('/commerce/orders'), throwsA(isA<DioException>()));

    expect(renovaciones, 1);
    expect(expiraciones, 1);
    expect(servidor.recibidas.length, 1, reason: 'no debe reintentar sin token nuevo');
  });

  test('no entra en bucle si el reintento vuelve a dar 401', () async {
    montar(renovacionFunciona: true, responder: (_, __) => 401);
    await expectLater(dio.get<dynamic>('/commerce/orders'), throwsA(isA<DioException>()));

    // Una sola renovación y un solo reintento: dos peticiones en total.
    expect(renovaciones, 1);
    expect(servidor.recibidas.length, 2);
    expect(expiraciones, 1);
  });

  test('un 401 del propio login no dispara renovación', () async {
    montar(renovacionFunciona: true, responder: (_, __) => 401);
    await expectLater(
      dio.post<dynamic>('/auth/login', data: {'email': 'x@y.z', 'password': 'x'}),
      throwsA(isA<DioException>()),
    );

    expect(renovaciones, 0, reason: 'credenciales incorrectas no son una sesión vencida');
    expect(servidor.recibidas.length, 1);
  });

  test('varias peticiones que fallan a la vez comparten una sola renovación', () async {
    montar(
      renovacionFunciona: true,
      responder: (intento, peticion) => peticion.headers['Authorization'] == 'Bearer nuevo' ? 200 : 401,
    );
    await Future.wait([
      dio.get<dynamic>('/commerce/cart'),
      dio.get<dynamic>('/commerce/orders'),
      dio.get<dynamic>('/reservations'),
    ]);

    expect(renovaciones, 1, reason: 'no debe pedir un token por cada petición caída');
  });
}
