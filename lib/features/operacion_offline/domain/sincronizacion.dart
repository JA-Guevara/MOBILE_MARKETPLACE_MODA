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

String estadoIndicador({
  bool sincronizando = false,
  bool sesionVencida = false,
  bool online = true,
  bool servidorAlcanzable = true,
  int conflictosCount = 0,
  int pendientesCount = 0,
}) {
  if (sincronizando) return 'SINCRONIZANDO';
  if (sesionVencida) return 'SESION_VENCIDA';
  if (!online) return 'SIN_CONEXION';
  if (!servidorAlcanzable) return 'SERVIDOR_NO_RESPONDE';
  if (conflictosCount > 0) return 'CONFLICTO';
  if (pendientesCount > 0) return 'PENDIENTES';
  return 'AL_DIA';
}

String _pad2(int n) => n < 10 ? '0$n' : '$n';

String formatearFechaCorta(DateTime d) =>
    '${_pad2(d.day)}/${_pad2(d.month)} ${_pad2(d.hour)}:${_pad2(d.minute)}';

String textoIndicador(
  String estado, {
  int pendientesCount = 0,
  int conflictosCount = 0,
  int? minutosDesdeDescarga,
  DateTime? fechaDatos,
  int? reintentoEnSegundos,
  bool desactualizado = false,
}) {
  final esDesactualizado =
      desactualizado ||
      (minutosDesdeDescarga != null && minutosDesdeDescarga > 1440);
  if (esDesactualizado && fechaDatos != null) {
    return 'datos del ${formatearFechaCorta(fechaDatos)}, pueden estar desactualizados';
  }

  switch (estado) {
    case 'SINCRONIZANDO':
      final n = pendientesCount > 0 ? pendientesCount : 1;
      return n == 1 ? 'Sincronizando 1 operación…' : 'Sincronizando $n operaciones…';
    case 'SESION_VENCIDA':
      final n = pendientesCount > 0 ? pendientesCount : 1;
      return '$n ventas por subir · Iniciá sesión para enviarlas';
    case 'SIN_CONEXION':
      if (pendientesCount > 0) {
        return 'Sin conexión · $pendientesCount por subir · se enviarán solas';
      }
      if (fechaDatos != null) {
        return 'Sin conexión · datos del ${formatearFechaCorta(fechaDatos)}';
      }
      return 'Sin conexión';
    case 'SERVIDOR_NO_RESPONDE':
      return 'El servidor no responde · reintentando';
    case 'CONFLICTO':
      final n = conflictosCount > 0 ? conflictosCount : 1;
      return n == 1 ? '1 operación necesita revisión' : '$n operaciones necesitan revisión';
    case 'PENDIENTES':
      final n = pendientesCount > 0 ? pendientesCount : 1;
      if (reintentoEnSegundos != null) {
        return '$n por subir · reintento en $reintentoEnSegundos s';
      }
      return '$n por subir';
    case 'AL_DIA':
    default:
      if (minutosDesdeDescarga != null) {
        return 'Todo sincronizado · datos de hace $minutosDesdeDescarga min';
      }
      return 'Todo sincronizado';
  }
}

String etiquetaEstado(String estado) {
  switch (estado.toUpperCase()) {
    case 'PENDIENTE':
      return 'Por subir';
    case 'ENVIADA':
      return 'Enviando';
    case 'CONFIRMADA':
      return 'Confirmada';
    case 'CONFLICTO':
      return 'Necesita revisión';
    case 'RECHAZADA':
      return 'Rechazada';
    case 'ANULADA':
      return 'Anulada';
    default:
      return estado;
  }
}

String etiquetaTipo(String tipo) {
  switch (tipo.toUpperCase()) {
    case 'VENTA':
    case 'SALE':
      return 'Venta de contado';
    case 'RESERVA':
    case 'RESERVATION':
      return 'Reserva';
    default:
      return tipo;
  }
}

bool debeActualizarCatalogo({
  required bool online,
  required bool sesionReal,
  required bool tieneModuloOffline,
  String? versionLocal,
  DateTime? ultimaDescarga,
  DateTime? ahora,
  String? evento,
}) {
  if (!online || !sesionReal || !tieneModuloOffline) return false;
  if (versionLocal == null || versionLocal.isEmpty) return true;

  final ahoraTime = ahora ?? DateTime.now();
  final ultimaTime = ultimaDescarga ?? DateTime.fromMillisecondsSinceEpoch(0);
  final diffMs = ahoraTime.difference(ultimaTime).inMilliseconds;

  if (evento == 'sync_confirmed') return true;
  if (evento == 'login' || evento == 'reconnect') return true;
  if (evento == 'visible') return diffMs >= 60000;

  return diffMs >= 300000;
}

