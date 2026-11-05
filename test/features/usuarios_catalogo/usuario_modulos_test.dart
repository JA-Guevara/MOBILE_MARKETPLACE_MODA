import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' show Size;
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_marketplace_moda/core/network/api_exception.dart';
import 'package:mobile_marketplace_moda/features/usuarios_catalogo/domain/usuario.dart';
import 'package:mobile_marketplace_moda/features/usuarios_catalogo/presentation/account_screen.dart';
import '../../support/backend_falso.dart';

Map<String, dynamic> perfil() => {
  ...BackendFalso.usuario,
  'subscription': {
    'plan_code': 'BASICO',
    'plan_name': 'Básico',
    'status': 'ACTIVA',
    'features': {'offline': true, 'ai_reports': true},
    'limits': <String, dynamic>{},
    'modules': [
      {
        'code': 'offline',
        'name': 'Operación sin conexión',
        'origin': 'PLAN',
        'expires_at': null,
      },
      {
        'code': 'ai_reports',
        'name': 'Reportes con IA',
        'origin': 'TRIAL',
        'expires_at': '2026-11-07T23:59:00Z',
      },
    ],
  },
};

class BackendConModulos extends BackendFalso {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (options.path == '/auth/login') {
      return ResponseBody.fromString(
        jsonEncode({
          'success': true,
          'data': {
            'access_token': 'token-sintetico',
            'refresh_token': 'refresh-sintetico',
            'user': perfil(),
          },
        }),
        200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
    }
    return super.fetch(options, requestStream, cancelFuture);
  }
}

void main() {
  test(
    'lee módulos TRIAL y conserva origen y vencimiento en perfil offline sin tokens',
    () {
      final usuario = Usuario.desdeJson(perfil());
      final prueba = usuario.modulos.singleWhere((m) => m.enPrueba);
      expect(prueba.codigo, 'ai_reports');
      expect(prueba.expira, DateTime.utc(2026, 11, 7, 23, 59));
      expect(Usuario.desdeJson(usuario.aJson()).modulos.last.origen, 'TRIAL');
      expect(usuario.suscripcion!.permite('ai_reports'), isTrue);
      expect(usuario.aJson().keys, isNot(contains('access_token')));
      expect(usuario.aJson().keys, isNot(contains('refresh_token')));
    },
  );

  test(
    'perfil anterior sin modules conserva features y no inventa pruebas',
    () {
      final json = perfil();
      (json['subscription'] as Map).remove('modules');
      final usuario = Usuario.desdeJson(json);
      expect(usuario.modulos, isEmpty);
      expect(usuario.suscripcion!.permite('offline'), isTrue);
    },
  );

  for (final code in ['module_not_enabled', 'feature_not_in_plan']) {
    test('$code muestra el nombre del módulo y conserva HTTP403', () {
      final request = RequestOptions(path: '/reportes');
      final error = ApiException.from(
        DioException(
          requestOptions: request,
          response: Response(
            requestOptions: request,
            statusCode: 403,
            data: {
              'error': {
                'code': code,
                'message': 'No disponible',
                'details': {'module_name': 'Reportes con IA'},
              },
            },
          ),
        ),
      );
      expect(error.message, contains('Reportes con IA'));
      expect(error.statusCode, 403);
      expect(error.sinConexion, isFalse);
    });
  }

  test('module_code del contrato backend aparece si no se envía nombre', () {
    final request = RequestOptions(path: '/reportes');
    final error = ApiException.from(
      DioException(
        requestOptions: request,
        response: Response(
          requestOptions: request,
          statusCode: 403,
          data: {
            'error': {
              'code': 'feature_not_in_plan',
              'details': {'module_code': 'ai_reports'},
            },
          },
        ),
      ),
    );
    expect(error.message, contains('Reportes con IA'));
  });

  testWidgets(
    'Mi plan presenta módulo en prueba y su fecha sin desbordar a 320px',
    (tester) async {
      tester.view.physicalSize = const Size(320, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await montarPantalla(
        tester,
        const AccountScreen(),
        backend: BackendConModulos(),
      );
      expect(find.text('Mi plan'), findsOneWidget);
      expect(find.text('Básico · ACTIVA'), findsOneWidget);
      expect(
        find.textContaining('Reportes con IA · En prueba hasta el'),
        findsOneWidget,
      );
      expect(find.textContaining('07/11/2026'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
