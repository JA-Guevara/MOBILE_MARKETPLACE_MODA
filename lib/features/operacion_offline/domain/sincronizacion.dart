import 'dart:math';
import 'reserva_local.dart';

class SyncOperationWire {
  const SyncOperationWire({
    required this.clientRequestId,
    required this.type,
    required this.branchId,
    required this.deviceId,
    required this.clientCreatedAt,
    required this.payload,
  });

  final String clientRequestId;
  final String type; // 'SALE' or 'RESERVATION'
  final String branchId;
  final String deviceId;
  final String clientCreatedAt;
  final Map<String, dynamic> payload;

  Map<String, dynamic> toJson() => {
    'client_request_id': clientRequestId,
    'type': type,
    'branch_id': branchId,
    'device_id': deviceId,
    'client_created_at': clientCreatedAt,
    'payload': payload,
  };

  factory SyncOperationWire.desdeOperacion(OperacionPendiente op) =>
      SyncOperationWire(
        clientRequestId: op.id,
        type: op.tipo == 'VENTA' || op.tipo == 'SALE' ? 'SALE' : 'RESERVATION',
        branchId: op.sucursalId,
        deviceId: op.dispositivoId,
        clientCreatedAt: op.creadaEn.toIso8601String(),
        payload: op.payload,
      );
}

class SyncResult {
  const SyncResult({
    required this.clientRequestId,
    required this.status,
    required this.message,
    this.serverRef,
    this.serverNumber,
    this.conflictId,
    this.conflictType,
    this.reasonCode,
    this.replay = false,
    this.refundAmount,
    this.refundStatus,
  });

  final String clientRequestId;
  final String status; // 'CONFIRMED', 'CONFLICT', 'REJECTED', 'RETRY'
  final String message;
  final String? serverRef;
  final String? serverNumber;
  final String? conflictId;
  final String? conflictType;
  final String? reasonCode;
  final bool replay;
  final String? refundAmount, refundStatus;

  bool get isConfirmed => status == 'CONFIRMED';
  bool get isConflict => status == 'CONFLICT';
  bool get isRejected => status == 'REJECTED';

  factory SyncResult.fromJson(Map<String, dynamic> json) => SyncResult(
    clientRequestId: json['client_request_id'] as String,
    status: json['status'] as String? ?? 'UNKNOWN',
    message: json['message'] as String? ?? '',
    serverRef: json['server_ref'] as String?,
    serverNumber: json['server_number'] as String?,
    conflictId: json['conflict_id'] as String?,
    conflictType: json['conflict_type'] as String?,
    reasonCode: json['reason_code'] as String?,
    replay: json['replay'] as bool? ?? false,
    refundAmount: json['refund_amount'] as String?,
    refundStatus: json['refund_status'] as String?,
  );
}

class SyncBatchResponse {
  const SyncBatchResponse({
    required this.batchId,
    required this.received,
    required this.confirmed,
    required this.conflicts,
    required this.rejected,
    required this.results,
  });

  final String batchId;
  final int received, confirmed, conflicts, rejected;
  final List<SyncResult> results;

  factory SyncBatchResponse.fromJson(Map<String, dynamic> json) =>
      SyncBatchResponse(
        batchId: json['batch_id'] as String? ?? '',
        received: json['received'] as int? ?? 0,
        confirmed: json['confirmed'] as int? ?? 0,
        conflicts: json['conflicts'] as int? ?? 0,
        rejected: json['rejected'] as int? ?? 0,
        results: (json['results'] as List<dynamic>? ?? [])
            .map((e) => SyncResult.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

int backoffMs(int intento, {int baseMs = 5000, int maxMs = 300000}) {
  final exp = pow(2, intento).toInt();
  final val = baseMs * exp;
  return min(val, maxMs);
}

List<List<T>> enLotes<T>(List<T> items, int tamanoLote) {
  final lotes = <List<T>>[];
  for (var i = 0; i < items.length; i += tamanoLote) {
    lotes.add(items.sublist(i, min(i + tamanoLote, items.length)));
  }
  return lotes;
}

/// Fila de `historial_sync`: resultado de un envío de lote al servidor.
class RegistroSincronizacion {
  const RegistroSincronizacion({
    required this.id,
    required this.iniciadoEn,
    this.terminadoEn,
    required this.enviadas,
    required this.confirmadas,
    required this.conflictos,
    required this.rechazadas,
    this.error,
    this.codigoError,
    this.httpStatus,
    this.loteId,
  });

  final int id;
  final DateTime iniciadoEn;
  final DateTime? terminadoEn;
  final int enviadas, confirmadas, conflictos, rechazadas;
  final String? error, codigoError, loteId;
  final int? httpStatus;

  bool get fallido => codigoError != null || error != null;

  /// Mensaje legible para el operador; nunca expone detalles técnicos crudos.
  String? get mensajeError {
    if (!fallido) return null;
    if (error != null && error!.trim().isNotEmpty) return error;
    if (codigoError == 'NETWORK') {
      return 'Sin conexión con el servidor. Las operaciones siguieron pendientes.';
    }
    if (httpStatus == 429 || httpStatus == 503) {
      return 'Servidor ocupado (HTTP $httpStatus). Se reintentará más tarde.';
    }
    return 'El servidor no aceptó el lote${httpStatus != null ? ' (HTTP $httpStatus)' : ''}. Las operaciones siguieron pendientes.';
  }

  factory RegistroSincronizacion.desdeFila(Map<String, Object?> f) {
    int entero(Object? v) => (v as num?)?.toInt() ?? 0;
    return RegistroSincronizacion(
      id: entero(f['id']),
      iniciadoEn:
          DateTime.tryParse(f['iniciado_en'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      terminadoEn: DateTime.tryParse(f['terminado_en'] as String? ?? ''),
      enviadas: entero(f['enviadas']),
      confirmadas: entero(f['confirmadas']),
      conflictos: entero(f['conflictos']),
      rechazadas: entero(f['rechazadas']),
      error: f['error'] as String?,
      codigoError: f['codigo_error'] as String?,
      httpStatus: (f['http_status'] as num?)?.toInt(),
      loteId: f['lote_id'] as String?,
    );
  }
}
