import 'package:dio/dio.dart';

/// Error ya traducido a algo que una persona puede leer.
///
/// El backend responde `{ error: { message, details } }`, pero FastAPI también
/// puede devolver `{ detail: "..." }` o `{ detail: [{ loc, msg }] }` cuando la
/// validación falla antes de llegar al caso de uso. Los tres casos terminan en
/// el mismo mensaje, igual que en `shared/errors.ts` del frontend web.
class ApiException implements Exception {
  const ApiException(
    this.message, {
    this.statusCode,
    this.retryAfter,
    this.conexionInterrumpida,
  });

  final String message;
  final int? statusCode;
  final String? retryAfter;
  final bool? conexionInterrumpida;

  /// El servidor no respondió: interrupción de conexión o servicio caído.
  bool get sinConexion => conexionInterrumpida ?? statusCode == null;

  @override
  String toString() => message;

  factory ApiException.from(DioException error) {
    final respuesta = error.response;
    if (respuesta == null) {
      final falloInterno = error.error is Error;
      return ApiException(
        falloInterno
            ? 'La aplicación no pudo preparar la consulta. Reintentá; si continúa, actualizá la aplicación.'
            : _sinRespuesta(error.type),
        conexionInterrumpida:
            !falloInterno && error.type != DioExceptionType.cancel,
      );
    }
    final cuerpo = respuesta.data;
    if (respuesta.statusCode == 429 || respuesta.statusCode == 503) {
      final wait = respuesta.headers.value('retry-after');
      return ApiException(
        respuesta.statusCode == 429
            ? 'Demasiadas solicitudes. Esperá antes de volver a intentar.'
            : 'El servicio no está disponible o está en mantenimiento. Tus operaciones pendientes se conservarán.',
        statusCode: respuesta.statusCode,
        retryAfter: wait,
      );
    }
    if (cuerpo is! Map<String, dynamic>) {
      return ApiException(
        _porEstado(respuesta.statusCode),
        statusCode: respuesta.statusCode,
      );
    }
    final envoltorio = cuerpo['error'];
    final detalle =
        (envoltorio is Map<String, dynamic> ? envoltorio['details'] : null) ??
        cuerpo['detail'];
    final codigo = envoltorio is Map ? envoltorio['code'] : null;
    if (codigo == 'module_not_enabled' || codigo == 'feature_not_in_plan') {
      final datos = detalle is Map ? detalle : const {};
      final modulo =
          datos['module_name'] ??
          datos['feature_name'] ??
          datos['module_code'] ??
          datos['module'] ??
          datos['feature'];
      if (modulo is String && modulo.isNotEmpty) {
        final nombre =
            const {
              'products': 'Catálogo',
              'sales': 'Ventas',
              'reservations': 'Reservas',
              'offline': 'Operación sin conexión',
              'conventional_reports': 'Reportes convencionales',
              'ai_reports': 'Reportes con IA',
              'ml_analytics': 'Analítica ML',
              'exchanges': 'Cambios de prenda',
              'promotions': 'Ofertas y promociones',
              'devices_audit': 'Dispositivos y auditoría',
            }[modulo] ??
            modulo;
        return ApiException(
          'El módulo «$nombre» no está habilitado para tu empresa. Consultá con tu administrador.',
          statusCode: respuesta.statusCode,
        );
      }
    }
    final mensaje =
        (envoltorio is Map<String, dynamic>
            ? envoltorio['message'] as String?
            : null) ??
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
    final campo = ubicacion is List
        ? ubicacion.join('.')
        : '${ubicacion ?? ''}';
    final texto = issue['message'] ?? issue['msg'] ?? '';
    return [campo, texto].where((t) => '$t'.isNotEmpty).join(': ');
  }

  /// El servidor no contesto. Distinguir *por que* no contesto es lo unico
  /// que despues permite diagnosticar: un tiempo agotado (backend dormido,
  /// telefono en una red lenta) no se arregla igual que un certificado que el
  /// telefono no valida (reloj desajustado) ni que un corte de red.
  static String _sinRespuesta(DioExceptionType tipo) => switch (tipo) {
    DioExceptionType.connectionTimeout ||
    DioExceptionType.sendTimeout ||
    DioExceptionType.receiveTimeout =>
      'El servidor tardó demasiado en responder. Revisá tu conexión y volvé a intentar.',
    DioExceptionType.badCertificate =>
      'No pudimos validar el certificado del servidor. Revisá la fecha y hora del teléfono y tu conexión.',
    DioExceptionType.cancel => 'La operación fue cancelada.',
    _ =>
      'No recibimos una respuesta del servidor. Revisá tu conexión e intentá nuevamente.',
  };

  static String _porEstado(int? estado) => switch (estado) {
    401 => 'Tu sesión venció. Volvé a iniciar sesión.',
    403 => 'No tenés permiso para esta operación.',
    404 => 'No encontramos lo que buscabas.',
    _ => 'No se pudo completar la operación.',
  };
}
