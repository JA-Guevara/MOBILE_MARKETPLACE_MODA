import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_marketplace_moda/features/operacion_offline/domain/reserva_local.dart';
import 'fixtures.dart';

void main() {
  test('stock cero, límite 20 variantes y máximo 10 unidades', () {
    expect(puedeAgregar([], 'v1', 1, 0), 'Sin existencia local suficiente');
    expect(puedeAgregar([], 'v1', 11, 100), contains('10 unidades'));
    final items = List.generate(
      20,
      (n) => ItemReservaLocal(reservaId: 'r', varianteId: '$n', cantidad: 1),
    );
    expect(puedeAgregar(items, 'otra', 1, 10), contains('20 variantes'));
    expect(puedeAgregar(items, '0', 1, 10), isNull);
  });
  test('payload usa UTC e identidad idempotente sin tokens', () {
    final r = reserva();
    expect(construirPayload(r, itemsPara(r), 'dispositivo-test'), {
      'branch_id': 'b1',
      'scheduled_at': '2030-10-25T14:30:00.000Z',
      'items': [
        {'variant_id': 'v1', 'quantity': 2},
      ],
      'notes': null,
      'client_key': r.id,
      'origin': 'OFFLINE',
      'device_id': 'dispositivo-test',
      'client_created_at': '2026-10-23T20:42:00.000Z',
    });
    final op = operacion(r, itemsPara(r));
    expect(op.aFila()['estado'], 'PENDIENTE');
    expect(op.aFila()['tipo'], 'RESERVA');
    expect(OperacionPendiente.desdeFila(op.aFila()).payload, op.payload);
  });
  test('valida fecha futura y solo cancela pendientes', () {
    final ahora = DateTime.now();
    expect(validarVisita(ahora, ahora), isNotNull);
    final r = reserva();
    final op = operacion(r, itemsPara(r));
    expect(puedeCancelarLocal(op), true);
    final fila = op.aFila()..['estado'] = 'CONFIRMADA';
    expect(puedeCancelarLocal(OperacionPendiente.desdeFila(fila)), false);
  });
}
