import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_marketplace_moda/core/network/api_client.dart';
import 'package:mobile_marketplace_moda/features/operacion_offline/domain/sincronizacion.dart';
import 'package:mobile_marketplace_moda/features/operacion_offline/infrastructure/sync_api.dart';

class ClienteCaptura extends ApiClient {
  ClienteCaptura(this.respuesta);
  final Map<String, dynamic> respuesta;
  String? ruta;
  Object? enviado;
  @override
  Future<T> post<T>(
    String path, {
    Object? body,
    Map<String, dynamic>? query,
  }) async {
    ruta = path;
    enviado = body;
    return respuesta as T;
  }
}

const operacion = SyncOperationWire(
  clientRequestId: '00000000-0000-0000-0000-000000000001',
  type: 'SALE',
  branchId: '00000000-0000-0000-0000-000000000002',
  deviceId: 'dispositivo-persistido',
  clientCreatedAt: '2026-11-06T00:00:00Z',
  payload: {},
);

void main() {
  test('envía device_id y client_version requeridos por SyncBatchIn', () async {
    final cliente = ClienteCaptura({'batch_id': 'batch', 'results': []});
    await SyncApi(cliente).postBatch([operacion]);
    expect(cliente.ruta, '/sync/batch');
    final body = cliente.enviado as Map<String, dynamic>;
    expect(body['device_id'], operacion.deviceId);
    expect(body['client_version'], isNotEmpty);
    expect((body['operations'] as List).single, operacion.toJson());
  });

  test(
    'normaliza contadores desde results sin perder códigos ni RETRY',
    () async {
      final statuses = ['CONFIRMED', 'CONFLICT', 'REJECTED', 'RETRY'];
      final cliente = ClienteCaptura({
        'batch_id': 'batch',
        'results': [
          for (final status in statuses)
            {
              'client_request_id': status,
              'status': status,
              'message': 'Resultado $status',
              'reason_code': 'subscription_read_only',
            },
        ],
      });
      final response = await SyncApi(cliente).postBatch([operacion]);
      expect(response.confirmed, 1);
      expect(response.conflicts, 1);
      expect(response.rejected, 1);
      expect(response.results.map((r) => r.status), statuses);
      expect(response.results.last.reasonCode, 'subscription_read_only');
    },
  );

  test('conserva contadores explícitos del formato anterior', () async {
    final cliente = ClienteCaptura({
      'batch_id': 'batch',
      'received': 3,
      'confirmed': 2,
      'conflicts': 1,
      'rejected': 0,
      'results': [],
    });
    final response = await SyncApi(cliente).postBatch([operacion]);
    expect(response.received, 3);
    expect(response.confirmed, 2);
    expect(response.conflicts, 1);
  });

  test('rechaza lotes vacíos antes de usar la red', () async {
    final cliente = ClienteCaptura({});
    await expectLater(SyncApi(cliente).postBatch([]), throwsArgumentError);
    expect(cliente.ruta, isNull);
  });
}
