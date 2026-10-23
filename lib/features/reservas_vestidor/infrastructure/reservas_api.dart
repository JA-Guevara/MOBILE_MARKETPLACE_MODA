import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../shared/models/api_response.dart';
import '../../usuarios_catalogo/application/session_controller.dart';
import '../domain/reserva.dart';

/// Cliente de `/reservations`. Equivale a `reservas.service.ts` de la web.
class ReservasApi {
  const ReservasApi(this._api);

  final ApiClient _api;

  Future<Page<Reserva>> mias({int page = 1, int pageSize = 20, String? estado}) async {
    final json = await _api.get<Map<String, dynamic>>('/reservations', query: {
      'page': page,
      'page_size': pageSize,
      if (estado != null && estado.isNotEmpty) 'status': estado,
    });
    return Page.from(json, Reserva.desdeJson);
  }

  Future<Reserva> detalle(String id) async {
    final json = await _api.get<Map<String, dynamic>>('/reservations/$id');
    return Reserva.desdeJson(json);
  }

  /// Pregunta si la sucursal alcanza para las tallas y cantidades pedidas.
  ///
  /// `variant_ids` y `quantities` viajan como parámetros **repetidos** y
  /// alineados por posición: es lo que espera FastAPI y lo que `ApiClient`
  /// ya sabe serializar.
  Future<List<DisponibilidadVariante>> disponibilidad({
    required String branchId,
    required List<ItemReserva> items,
  }) async {
    final filas = await _api.get<List<dynamic>>(
      '/reservations/availability',
      query: {
        'branch_id': branchId,
        'variant_ids': items.map((i) => i.variantId).toList(),
        'quantities': items.map((i) => i.cantidad).toList(),
      },
    );
    return filas
        .whereType<Map<String, dynamic>>()
        .map(DisponibilidadVariante.desdeJson)
        .toList();
  }

  Future<Reserva> crear({
    required String branchId,
    required DateTime agendadaPara,
    required List<ItemReserva> items,
    String? notas,
    String? claveCliente,
  }) async {
    final json = await _api.post<Map<String, dynamic>>(
      '/reservations',
      body: {
        'branch_id': branchId,
        // El backend guarda en UTC; mandar la hora local sin zona correría la
        // visita según dónde esté el servidor.
        'scheduled_at': agendadaPara.toUtc().toIso8601String(),
        'items': items.map((i) => i.aJson()).toList(),
        if (notas != null && notas.isNotEmpty) 'notes': notas,
        if (claveCliente != null) 'client_key': claveCliente,
      },
    );
    return Reserva.desdeJson(json);
  }

  Future<Reserva> cancelar(String id) async {
    final json = await _api.post<Map<String, dynamic>>('/reservations/$id/cancel');
    return Reserva.desdeJson(json);
  }
}

final Provider<ReservasApi> reservasApiProvider =
    Provider<ReservasApi>((ref) => ReservasApi(ref.watch(apiClientProvider)));
