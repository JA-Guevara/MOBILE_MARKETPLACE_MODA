import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_marketplace_moda/core/network/api_exception.dart';

/// Arma el error que devolvería Dio ante una respuesta con ese cuerpo.
DioException _error(int estado, Object? cuerpo) {
  final peticion = RequestOptions(path: '/commerce/orders');
  return DioException(
    requestOptions: peticion,
    response: Response(requestOptions: peticion, statusCode: estado, data: cuerpo),
  );
}

void main() {
  group('Mensaje de error para la persona', () {
    test('usa el mensaje del envoltorio propio del backend', () {
      final error = ApiException.from(_error(409, {
        'success': false,
        'error': {'code': 'conflict', 'message': 'Solo se pueden devolver pedidos ya entregados.'},
      }));
      expect(error.message, 'Solo se pueden devolver pedidos ya entregados.');
      expect(error.statusCode, 409);
    });

    test('entiende el detalle en texto de FastAPI', () {
      final error = ApiException.from(_error(400, {'detail': 'El carrito esta vacio.'}));
      expect(error.message, 'El carrito esta vacio.');
    });

    test('resume los errores de validación campo por campo', () {
      final error = ApiException.from(_error(422, {
        'detail': [
          {'loc': ['body', 'reason'], 'msg': 'demasiado corto'},
          {'loc': ['body', 'items'], 'msg': 'no puede estar vacío'},
        ],
      }));
      expect(error.message, contains('body.reason: demasiado corto'));
      expect(error.message, contains('body.items: no puede estar vacío'));
    });

    test('sin respuesta del servidor habla de la conexión, no de un 500', () {
      final error = ApiException.from(
        DioException(requestOptions: RequestOptions(path: '/health')),
      );
      expect(error.sinConexion, isTrue);
      expect(error.message, contains('conexión'));
    });

    test('un 403 sin cuerpo explica que falta permiso', () {
      final error = ApiException.from(_error(403, null));
      expect(error.message, contains('permiso'));
    });
  });
}
