import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_marketplace_moda/core/network/api_client.dart';
import 'package:mobile_marketplace_moda/features/reservas_vestidor/application/reservas_controller.dart';
import 'package:mobile_marketplace_moda/features/reservas_vestidor/domain/reserva.dart';
import 'package:mobile_marketplace_moda/features/reservas_vestidor/infrastructure/reservas_api.dart';
import 'package:mobile_marketplace_moda/features/ventas_pagos/infrastructure/commerce_api.dart';

class _ServidorFalso implements HttpClientAdapter {
  final List<String> pedidos = [];
  final List<Map<String, dynamic>> cuerpos = [];
  final List<Map<String, List<String>>> consultas = [];
  final Map<String, int> fallan = {};

  /// Variantes que la sucursal NO puede cubrir.
  Set<String> sinStock = {};
  Completer<void>? esperaPrimeraDisponibilidad;

  String estadoReserva = 'pending';

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    pedidos.add('${options.method} ${options.path}');
    if (options.data is Map<String, dynamic>) {
      cuerpos.add(options.data as Map<String, dynamic>);
    }
    if (options.path == '/reservations/availability') {
      consultas.add({
        for (final e in options.queryParameters.entries)
          e.key: (e.value is List)
              ? (e.value as List).map((v) => '$v').toList()
              : ['${e.value}'],
      });
      if (consultas.length == 1 && esperaPrimeraDisponibilidad != null) {
        await esperaPrimeraDisponibilidad!.future;
      }
    }

    final falla = fallan[options.path];
    if (falla != null) {
      return _json({
        'success': false,
        'error': {
          'code': 'x',
          'message': 'La sucursal elegida no tiene disponible esa talla.',
        },
      }, falla);
    }
    return _json({
      'success': true,
      'message': '',
      'data': _datoDe(options),
    }, 200);
  }

  Object _datoDe(RequestOptions options) {
    final path = options.path;
    if (path == '/commerce/branches') {
      return [
        {'id': 'b1', 'name': 'Centro', 'address': 'Av Bush'},
        {'id': 'b2', 'name': 'Norte', 'address': 'Av Banzer'},
      ];
    }
    if (path == '/reservations/availability') {
      final ids = options.queryParameters['variant_ids'];
      final lista = ids is List ? ids.map((v) => '$v').toList() : <String>[];
      return [
        for (final id in lista)
          {
            'variant_id': id,
            'available': !sinStock.contains(id),
            'quantity': sinStock.contains(id) ? 0 : 5,
            'requested': 1,
            'product': 'Polera POLO',
            'size': 'M',
            'color': 'Azul',
            'reason': sinStock.contains(id)
                ? 'Sin unidades en esta sucursal.'
                : null,
          },
      ];
    }
    if (path == '/reservations' && options.method == 'GET') {
      return {
        'items': [_reserva()],
        'total': 1,
        'page': 1,
        'page_size': 20,
        'pages': 1,
      };
    }
    return _reserva();
  }

  Map<String, dynamic> _reserva() => {
    'id': 'rs1',
    'user_id': 'u1',
    'branch_id': 'b1',
    'status': estadoReserva,
    'scheduled_at': '2026-10-01T15:00:00Z',
    'branch_name': 'Centro',
    'notes': 'Voy después del trabajo',
    'items': [
      {
        'variant_id': 'v1',
        'quantity': 2,
        'product': 'Polera POLO',
        'size': 'M',
      },
    ],
    'tracking': [
      {'status': 'pending', 'note': '', 'date': '2026-09-21T10:00:00Z'},
    ],
    'created_at': '2026-09-21T10:00:00Z',
  };

  static ResponseBody _json(Object cuerpo, int estado) =>
      ResponseBody.fromString(
        jsonEncode(cuerpo),
        estado,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );

  @override
  void close({bool force = false}) {}
}

void main() {
  late _ServidorFalso servidor;
  late ApiClient cliente;

  void montar() {
    servidor = _ServidorFalso();
    final dio = Dio(
      BaseOptions(
        baseUrl: 'http://test/api/v1',
        validateStatus: (s) => s != null && s < 400,
      ),
    );
    dio.httpClientAdapter = servidor;
    cliente = ApiClient(dio: dio);
  }

  ReservasController lista() {
    montar();
    return ReservasController(ReservasApi(cliente));
  }

  NuevaReservaController nueva() {
    montar();
    return NuevaReservaController(ReservasApi(cliente), CommerceApi(cliente));
  }

  ItemReserva item(String id, {int cantidad = 1}) => ItemReserva(
    variantId: id,
    cantidad: cantidad,
    producto: 'Polera POLO',
    talla: 'M',
  );

  group('mis reservas', () {
    test('trae las visitas agendadas', () async {
      final control = lista();

      await control.cargar();

      expect(control.state.reservas, hasLength(1));
      final reserva = control.state.reservas.first;
      expect(reserva.etiquetaEstado, 'Pendiente de confirmar');
      expect(reserva.unidades, 2);
      expect(reserva.sucursal, 'Centro');
    });

    test('una reserva pendiente se puede cancelar', () async {
      final control = lista();
      await control.cargar();

      expect(control.state.reservas.first.sePuedeCancelar, isTrue);

      await control.cancelar(control.state.reservas.first);

      expect(servidor.pedidos, contains('POST /reservations/rs1/cancel'));
      expect(control.state.mensaje, isNotNull);
    });

    test('una reserva ya atendida no se puede cancelar', () async {
      final control = lista();
      servidor.estadoReserva = 'attended';

      await control.cargar();

      expect(control.state.reservas.first.sePuedeCancelar, isFalse);
    });
  });

  group('armar la selección', () {
    test(
      'sumar la misma variante acumula en vez de duplicar la línea',
      () async {
        final control = nueva();
        await control.cargar();

        control.agregar(item('v1', cantidad: 2));
        control.agregar(item('v1', cantidad: 3));

        expect(control.state.items, hasLength(1));
        expect(control.state.items.first.cantidad, 5);
        expect(control.state.unidades, 5);
      },
    );

    test('rechaza pasarse de 10 unidades de una misma talla', () async {
      final control = nueva();
      await control.cargar();
      control.agregar(item('v1', cantidad: 8));

      final problema = control.agregar(item('v1', cantidad: 5));

      // El backend impone el mismo tope (RF09); avisar acá evita el viaje.
      expect(problema, contains('10 unidades'));
      expect(control.state.items.first.cantidad, 8);
    });

    test('rechaza pasarse de 20 prendas distintas', () async {
      final control = nueva();
      await control.cargar();
      for (var i = 0; i < maxVariantesPorReserva; i++) {
        control.agregar(item('v$i'));
      }

      final problema = control.agregar(item('otra'));

      expect(problema, contains('20 prendas'));
      expect(control.state.items, hasLength(maxVariantesPorReserva));
    });

    test('bajar la cantidad a cero quita la prenda', () async {
      final control = nueva();
      await control.cargar();
      control.agregar(item('v1', cantidad: 2));

      control.cambiarCantidad('v1', 0);

      expect(control.state.items, isEmpty);
    });
  });

  group('disponibilidad', () {
    test(
      'ignora una respuesta antigua mientras se agregan más prendas',
      () async {
        final control = nueva();
        await control.cargar();
        final liberarPrimera = Completer<void>();
        servidor.esperaPrimeraDisponibilidad = liberarPrimera;

        control.agregar(item('v1'));
        control.elegirFecha(DateTime(2026, 10, 1, 15));
        expect(control.state.comprobandoDisponibilidad, isTrue);
        expect(control.state.sePuedeReservar, isFalse);

        control.agregar(item('v2'));
        await control.revisarDisponibilidad();
        expect(
          control.state.disponibilidad.map((d) => d.variantId),
          containsAll(['v1', 'v2']),
        );

        liberarPrimera.complete();
        await Future<void>.delayed(const Duration(milliseconds: 10));
        expect(
          control.state.disponibilidad.map((d) => d.variantId),
          containsAll(['v1', 'v2']),
        );
        expect(control.state.comprobandoDisponibilidad, isFalse);
      },
    );

    test('consulta variantes y cantidades alineadas por posición', () async {
      final control = nueva();
      await control.cargar();
      control.agregar(item('v1', cantidad: 2));
      control.agregar(item('v2', cantidad: 3));
      await control.revisarDisponibilidad();

      final ultima = servidor.consultas.last;
      // FastAPI espera parámetros repetidos, no una lista unida por comas.
      expect(ultima['variant_ids'], ['v1', 'v2']);
      expect(ultima['quantities'], ['2', '3']);
      expect(ultima['branch_id'], ['b1']);
    });

    test(
      'una sucursal sin stock bloquea la reserva y explica por qué',
      () async {
        final control = nueva();
        await control.cargar();
        servidor.sinStock = {'v1'};
        control.agregar(item('v1'));
        await control.revisarDisponibilidad();

        expect(control.state.hayFaltantes, isTrue);
        expect(
          control.state.faltantes.first.motivo,
          'Sin unidades en esta sucursal.',
        );

        control.elegirFecha(DateTime(2026, 10, 1, 15));
        expect(control.state.sePuedeReservar, isFalse);
      },
    );

    test('cambiar de sucursal vuelve a preguntar', () async {
      final control = nueva();
      await control.cargar();
      control.agregar(item('v1'));
      await control.revisarDisponibilidad();
      final antes = servidor.consultas.length;

      await control.elegirSucursal('b2');

      expect(servidor.consultas.length, greaterThan(antes));
      expect(servidor.consultas.last['branch_id'], ['b2']);
    });
  });

  group('confirmar', () {
    test('no deja confirmar sin prendas, sin fecha o con faltantes', () async {
      final control = nueva();
      await control.cargar();

      expect(control.state.sePuedeReservar, isFalse);

      control.agregar(item('v1'));
      await control.revisarDisponibilidad();
      expect(control.state.sePuedeReservar, isFalse); // falta la fecha

      control.elegirFecha(DateTime(2026, 10, 1, 15));
      expect(control.state.sePuedeReservar, isTrue);
    });

    test('manda la fecha en UTC y las prendas elegidas', () async {
      final control = nueva();
      await control.cargar();
      control.agregar(item('v1', cantidad: 2));
      await control.revisarDisponibilidad();
      final cuando = DateTime(2026, 10, 1, 15, 30);
      control.elegirFecha(cuando);
      control.escribirNotas('  Voy después del trabajo  ');

      final reserva = await control.confirmar();

      expect(reserva?.id, 'rs1');
      final cuerpo = servidor.cuerpos.last;
      // Mandar hora local sin zona correría la visita según dónde esté el server.
      expect(cuerpo['scheduled_at'], cuando.toUtc().toIso8601String());
      expect(cuerpo['items'], [
        {'variant_id': 'v1', 'quantity': 2},
      ]);
      expect(cuerpo['notes'], 'Voy después del trabajo');
      // Confirmada, la selección se vacía para no reservar dos veces lo mismo.
      expect(control.state.items, isEmpty);
    });

    test(
      'un rechazo del backend deja el motivo y conserva la selección',
      () async {
        final control = nueva();
        await control.cargar();
        control.agregar(item('v1'));
        await control.revisarDisponibilidad();
        control.elegirFecha(DateTime(2026, 10, 1, 15));
        servidor.fallan['/reservations'] = 400;

        final reserva = await control.confirmar();

        expect(reserva, isNull);
        expect(control.state.error, contains('no tiene disponible'));
        expect(control.state.items, hasLength(1));
        expect(control.state.ocupado, isFalse);
      },
    );
  });
}
