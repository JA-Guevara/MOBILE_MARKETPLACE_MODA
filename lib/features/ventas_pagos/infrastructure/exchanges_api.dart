import '../../../core/network/api_client.dart';
import '../domain/cambio.dart';

class ExchangesApi {
  ExchangesApi(this._client);

  final ApiClient _client;

  Future<ExchangePolicy> getPolicy() async {
    final res = await _client.get<Map<String, dynamic>>('/commerce/admin/exchanges/policy');
    return ExchangePolicy.fromJson(res);
  }

  Future<ExchangeOrderLookup> lookupOrder(String query) async {
    final res = await _client.get<Map<String, dynamic>>(
      '/commerce/admin/exchanges/lookup/${Uri.encodeComponent(query.trim())}',
    );
    return ExchangeOrderLookup.fromJson(res);
  }

  Future<ExchangeCalculationResult> calculate({
    String? orderId,
    required String branchId,
    required List<Map<String, dynamic>> lines,
  }) async {
    final res = await _client.post<Map<String, dynamic>>(
      '/commerce/admin/exchanges/calculate',
      body: {'branch_id': branchId, 'lines': lines,if(orderId!=null)'original_order_id':orderId},
    );
    return ExchangeCalculationResult.fromJson(res);
  }

  Future<ExchangeDetail> executeExchange(Map<String, dynamic> payload) async {
    final res = await _client.post<Map<String, dynamic>>(
      '/commerce/admin/exchanges',
      body: payload,
    );
    return ExchangeDetail.fromJson(res);
  }
}
