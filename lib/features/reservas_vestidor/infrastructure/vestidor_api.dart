import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/config/environment.dart';

/// Recurso público que el backend preparó para superponer sobre la cámara.
/// `assetUrl` apunta a PNG/WebP transparente; no se usa la foto original con
/// fondo del catálogo.
class RecursoVestidor {
  const RecursoVestidor({
    required this.assetUrl,
    this.region,
    this.tipo,
    this.anclajes,
  });

  final String assetUrl;
  final String? region;
  final String? tipo;
  final Map<String, List<double>?>? anclajes;

  factory RecursoVestidor.desdeJson(Map<String, dynamic> json) {
    final crudos = json['anchor_points'];
    final anclajes = <String, List<double>?>{};
    if (crudos is Map) {
      crudos.forEach((clave, valor) {
        if (valor is List &&
            valor.length >= 2 &&
            valor[0] is num &&
            valor[1] is num) {
          anclajes['$clave'] = [
            (valor[0] as num).toDouble(),
            (valor[1] as num).toDouble(),
          ];
        }
      });
    }
    final urlCruda = json['asset_url'] as String? ?? '';
    final uri = Uri.tryParse(urlCruda);
    final servidor = Uri.parse(Environment.apiUrl);
    // Un recurso generado en desarrollo puede quedar guardado con
    // `http://localhost:8000/...`. En un teléfono «localhost» es el propio
    // teléfono, no Railway, por lo que la cámara queda funcionando pero nunca
    // descarga la prenda. Conservamos ruta y query, reemplazando solo el
    // origen local por el origen público configurado para la aplicación.
    final esOrigenLocal =
        uri != null &&
        (uri.host == 'localhost' ||
            uri.host == '127.0.0.1' ||
            uri.host == '10.0.2.2');
    final url = uri != null && uri.hasScheme && !esOrigenLocal
        ? urlCruda
        : '${servidor.origin}'
              '${uri?.path ?? (urlCruda.startsWith('/') ? '' : '/') + urlCruda}'
              '${uri != null && uri.hasQuery ? '?${uri.query}' : ''}';
    return RecursoVestidor(
      assetUrl: url,
      region: json['body_region'] as String?,
      tipo: json['garment_type'] as String?,
      anclajes: anclajes.isEmpty ? null : anclajes,
    );
  }
}

/// Contrato del móvil con `POST /vestidor/sessions`.
class VestidorApi {
  const VestidorApi(this._api);

  final ApiClient _api;

  Future<RecursoVestidor> iniciar({
    required String productoId,
    required String colorId,
  }) async {
    final json = await _api.post<Map<String, dynamic>>(
      '/vestidor/sessions',
      body: {'product_id': productoId, 'color_id': colorId},
    );
    if (json['color_id'] != colorId) {
      throw const ApiException(
        'El servidor devolvió una imagen de otro color. No la mostraremos.',
      );
    }
    return RecursoVestidor.desdeJson(json);
  }
}
