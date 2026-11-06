import '../../../core/network/api_client.dart';
import '../domain/sincronizacion.dart';

class SyncApi {
  const SyncApi(this._api);
  final ApiClient _api;

  Future<SyncBatchResponse> postBatch(
    List<SyncOperationWire> operaciones,
  ) async {
    if (operaciones.isEmpty) {
      throw ArgumentError('El lote no puede estar vacío.');
    }
    if (operaciones.map((op) => op.deviceId).toSet().length != 1) {
      throw ArgumentError('Un lote debe pertenecer a un solo dispositivo.');
    }
    final res = await _api.post<Map<String, dynamic>>(
      '/sync/batch',
      body: {
        'device_id': operaciones.first.deviceId,
        'client_version': const String.fromEnvironment(
          'APP_VERSION',
          defaultValue: '0.1.0',
        ),
        'operations': operaciones.map((o) => o.toJson()).toList(),
      },
    );
    final results = (res['results'] as List<dynamic>? ?? [])
        .cast<Map<String, dynamic>>();
    return SyncBatchResponse.fromJson({
      ...res,
      'received': res['received'] ?? operaciones.length,
      'confirmed':
          res['confirmed'] ??
          results.where((r) => r['status'] == 'CONFIRMED').length,
      'conflicts':
          res['conflicts'] ??
          results.where((r) => r['status'] == 'CONFLICT').length,
      'rejected':
          res['rejected'] ??
          results.where((r) => r['status'] == 'REJECTED').length,
    });
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
