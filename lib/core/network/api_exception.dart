import 'package:dio/dio.dart';

/// Error ya traducido a algo que una persona puede leer.
///
/// El backend responde `{ error: { message, details } }`, pero FastAPI también
/// puede devolver `{ detail: "..." }` o `{ detail: [{ loc, msg }] }` cuando la
/// validación falla antes de llegar al caso de uso. Los tres casos terminan en
/// el mismo mensaje, igual que en `shared/errors.ts` del frontend web.
class ApiException implements Exception {
  const ApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  /// El servidor no respondió: interrupción de conexión o servicio caído.
  bool get sinConexion => statusCode == null;

  @override
  String toString() => message;

  factory ApiException.from(DioException error) {
    final respuesta = error.response;
    if (respuesta == null) {
      return const ApiException(
        'No recibimos una respuesta del servidor. Revisá tu conexión e intentá nuevamente.',
      );
    }
    final cuerpo = respuesta.data;
    if (cuerpo is! Map<String, dynamic>) {
      return ApiException(_porEstado(respuesta.statusCode), statusCode: respuesta.statusCode);
    }
    final envoltorio = cuerpo['error'];
    final detalle = (envoltorio is Map<String, dynamic> ? envoltorio['details'] : null) ?? cuerpo['detail'];
    final mensaje = (envoltorio is Map<String, dynamic> ? envoltorio['message'] as String? : null) ??
        (detalle is String ? detalle : null) ??
        _porEstado(respuesta.statusCode);
    final campos = detalle is List
        ? detalle.map(_campo).where((t) => t.isNotEmpty).join(' · ')
        : '';
    return ApiException(
      [mensaje, campos].where((t) => t.isNotEmpty).join(' '),
      statusCode: respuesta.statusCode,
    );
  }

  /// Un error de validación de FastAPI: `{ loc: [...], msg: "..." }`.
  static String _campo(dynamic issue) {
    if (issue is! Map) return '';
    final ubicacion = issue['field'] ?? issue['loc'];
    final campo = ubicacion is List ? ubicacion.join('.') : '${ubicacion ?? ''}';
    final texto = issue['message'] ?? issue['msg'] ?? '';
    return [campo, texto].where((t) => '$t'.isNotEmpty).join(': ');
  }

  static String _porEstado(int? estado) => switch (estado) {
        401 => 'Tu sesión venció. Volvé a iniciar sesión.',
        403 => 'No tenés permiso para esta operación.',
        404 => 'No encontramos lo que buscabas.',
        _ => 'No se pudo completar la operación.',
      };
}

