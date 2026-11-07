import 'dart:async';

import 'package:dio/dio.dart';

/// Pone el bearer en cada pedido y renueva la sesión una sola vez ante un 401.
///
/// Es el equivalente de `auth.interceptor.ts` del frontend web. El interceptor
/// no conoce la sesión: recibe tres funciones. Así el núcleo de red no depende
/// del módulo de autenticación y se puede probar con funciones falsas.
///
/// El reintento ocurre **una vez**: si el pedido repetido vuelve a dar 401, la
/// sesión se considera terminada. Sin ese límite, un token inválido dispara un
/// bucle de renovaciones contra el servidor.
class AuthInterceptor extends Interceptor {
  AuthInterceptor({
    required this.accessToken,
    required this.refresh,
    required this.onSessionExpired,
    required this.dio,
    this.sessionIdentity,
  });

  final String? Function() accessToken;
  final Future<bool> Function() refresh;
  final void Function() onSessionExpired;
  final Dio dio;
  final String? Function()? sessionIdentity;

  /// Renovación en curso: varias peticiones que fallan a la vez comparten una
  /// sola llamada a `/auth/refresh` en lugar de pedir un token cada una.
  Future<bool>? _renovando;
  String? _identidadRenovando;

  static const _reintentado = 'x-fashionstore-retry';
  static const _identidad = 'fashionstore-session-identity';

  bool _mismaSesion(RequestOptions request) =>
      sessionIdentity == null ||
      request.extra[_identidad] == sessionIdentity!();

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    options.extra.putIfAbsent(_identidad, () => sessionIdentity?.call());
    final token = accessToken();
    if (token != null && token.isNotEmpty) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }

  /// Consigue un token válido para reintentar.
  ///
  /// Si otra petición ya renovó mientras esta viajaba, el token en memoria ya
  /// es distinto del que se usó y alcanza con reintentar: pedir otro token
  /// serviría para gastar una renovación y, con rotación de refresh tokens,
  /// para invalidar el que acaba de emitirse.
  Future<bool> _asegurarToken(String? usado) async {
    final actual = accessToken();
    if (actual != null && actual.isNotEmpty && 'Bearer $actual' != usado) {
      return true;
    }
    final identity = sessionIdentity?.call();
    if (_renovando != null && identity == _identidadRenovando) {
      return _renovando!;
    }
    _identidadRenovando = identity;
    late final Future<bool> future;
    future = refresh().whenComplete(() {
      if (identical(_renovando, future)) {
        _renovando = null;
        _identidadRenovando = null;
      }
    });
    _renovando = future;
    return future;
  }

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    final peticion = err.requestOptions;
    final esRenovable =
        err.response?.statusCode == 401 &&
        !peticion.extra.containsKey(_reintentado) &&
        !peticion.path.contains('/auth/refresh') &&
        !peticion.path.contains('/auth/login');
    if (!esRenovable || !_mismaSesion(peticion)) {
      return handler.next(err);
    }

    final renovado = await _asegurarToken(peticion.headers['Authorization']);
    if (!_mismaSesion(peticion)) return handler.next(err);
    if (!renovado) {
      onSessionExpired();
      return handler.next(err);
    }

    try {
      peticion.extra[_reintentado] = true;
      final token = accessToken();
      if (token != null && token.isNotEmpty) {
        peticion.headers['Authorization'] = 'Bearer $token';
      }
      handler.resolve(await dio.fetch(peticion));
    } on DioException catch (error) {
      if (error.response?.statusCode == 401 && _mismaSesion(peticion)) {
        onSessionExpired();
      }
      handler.next(error);
    }
  }
}
