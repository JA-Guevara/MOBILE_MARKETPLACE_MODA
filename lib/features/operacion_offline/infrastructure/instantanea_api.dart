import '../../../core/network/api_client.dart';
import '../domain/catalogo_local.dart';

class InstantaneaApi {
  const InstantaneaApi(this._api);
  final ApiClient _api;
  Future<InstantaneaCatalogo> obtener({
    String? sucursalId,
    String? desde,
  }) async => InstantaneaCatalogo.desdeJson(
    await _api.get<Map<String, dynamic>>(
      '/offline/snapshot',
      query: {'branch_id': sucursalId, 'since': desde},
    ),
  );
}
