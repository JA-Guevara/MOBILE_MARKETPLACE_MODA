import '../../../core/network/api_client.dart';
import '../domain/reporte_ia.dart';

class ReportesIaApi {
  ReportesIaApi(this._client);

  final ApiClient _client;

  Future<List<Map<String, dynamic>>> obtenerDefiniciones() async {
    final res = await _client.get<List<dynamic>>('/analytics/ai-reports/definitions');
    return res.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<InterpretResult> interpretar(String texto, {String canal = 'TEXT'}) async {
    final res = await _client.post<Map<String, dynamic>>(
      '/analytics/ai-reports/interpret',
      body: {'text': texto, 'channel': canal},
    );
    return InterpretResult.fromJson(res);
  }

  Future<ReportResponse> ejecutar(ReportSpec spec, {String? requestId}) async {
    final res = await _client.post<Map<String, dynamic>>(
      '/analytics/ai-reports/run',
      body: {'spec': spec.toJson(), 'request_id': requestId},
    );
    return ReportResponse.fromJson(res);
  }

  Future<Map<String, dynamic>> obtenerHistorial({bool mine = false, int page = 1}) async {
    final res = await _client.get<Map<String, dynamic>>(
      '/analytics/ai-reports/history',
      query: {'mine': mine, 'page': page},
    );
    return res;
  }
}
