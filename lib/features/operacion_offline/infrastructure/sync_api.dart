import '../../../core/network/api_client.dart';
import '../domain/sincronizacion.dart';

class SyncApi {
  const SyncApi(this._api);
  final ApiClient _api;

  Future<SyncBatchResponse> postBatch(List<SyncOperationWire> operaciones) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/sync/batch',
      body: {
        'operations': operaciones.map((o) => o.toJson()).toList(),
      },
    );
    return SyncBatchResponse.fromJson(res);
  }

  Future<Map<String, dynamic>> obtenerConflictos({
    String? sucursalId,
    String? estado,
    int page = 1,
    int pageSize = 20,
  }) async {
    return await _api.get<Map<String, dynamic>>(
      '/sync/conflicts',
      query: {
        if (sucursalId != null) 'branch_id': sucursalId,
        if (estado != null) 'status': estado,
        'page': page,
        'page_size': pageSize,
      },
    );
  }

  Future<Map<String, dynamic>> resolverConflicto(
    String conflictoId, {
    required String resolucion,
    String? notas,
    Map<String, int>? ajustesLinea,
  }) async {
    return await _api.post<Map<String, dynamic>>(
      '/sync/conflicts/$conflictoId/resolve',
      body: {
        'resolution': resolucion,
        if (notas != null) 'resolution_notes': notas,
        if (ajustesLinea != null) 'line_adjustments': ajustesLinea,
      },
    );
  }
}
