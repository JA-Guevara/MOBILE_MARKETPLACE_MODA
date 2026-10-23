import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_marketplace_moda/core/network/api_client.dart';
import 'package:mobile_marketplace_moda/core/network/api_exception.dart';
import 'package:mobile_marketplace_moda/features/reservas_vestidor/infrastructure/vestidor_api.dart';

class _ServidorVestidor implements HttpClientAdapter {
  _ServidorVestidor(this.colorId);

  final String colorId;
  Map<String, dynamic>? solicitud;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    solicitud = options.data as Map<String, dynamic>;
    return ResponseBody.fromString(
      jsonEncode({
        'success': true,
        'data': {
          'color_id': colorId,
          'asset_url': 'https://cdn.example.test/prenda.webp',
        },
      }),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  group('RecursoVestidor', () {
    test('reemplaza localhost por el backend público configurado', () {
      final recurso = RecursoVestidor.desdeJson({
        'asset_url': 'http://localhost:8000/api/v1/media/files/prenda.webp',
        'body_region': 'upper',
      });

      expect(
        recurso.assetUrl,
        'https://backendmarketplacemoda-production.up.railway.app/api/v1/media/files/prenda.webp',
      );
    });

    test('conserva una URL pública del recurso', () {
      final recurso = RecursoVestidor.desdeJson({
        'asset_url': 'https://cdn.example.test/prenda.webp',
      });

      expect(recurso.assetUrl, 'https://cdn.example.test/prenda.webp');
    });
  });

  test('pide un color exacto y rechaza una imagen de otro color', () async {
    final servidor = _ServidorVestidor('azul');
    final dio = Dio(BaseOptions(baseUrl: 'http://test/api/v1'));
    dio.httpClientAdapter = servidor;
    final api = VestidorApi(ApiClient(dio: dio));

    await expectLater(
      api.iniciar(productoId: 'prenda', colorId: 'rojo'),
      throwsA(isA<ApiException>()),
    );
    expect(servidor.solicitud?['color_id'], 'rojo');
  });
}
