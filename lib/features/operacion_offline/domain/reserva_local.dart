import 'dart:convert';

enum EstadoOperacion {
  pendiente,
  enviada,
  confirmada,
  rechazada,
  conflicto,
  anulada;

  String get codigo => name.toUpperCase();
  static EstadoOperacion desde(String valor) =>
      values.firstWhere((e) => e.codigo == valor);
}

enum EstadoReservaLocal {
  pendienteConfirmacion,
  anuladaLocal,
  confirmada,
  rechazada;

  String get codigo => switch (this) {
    pendienteConfirmacion => 'PENDIENTE_CONFIRMACION',
    anuladaLocal => 'ANULADA_LOCAL',
    confirmada => 'CONFIRMADA',
    rechazada => 'RECHAZADA',
  };
  static EstadoReservaLocal desde(String valor) =>
      values.firstWhere((e) => e.codigo == valor);
}

class ReservaLocal {
  const ReservaLocal({
    required this.id,
    required this.tenantId,
    required this.sucursalId,
    required this.usuarioId,
    required this.agendadaPara,
    required this.creadaEn,
    this.clienteId,
    this.notas,
    this.estado = EstadoReservaLocal.pendienteConfirmacion,
  });
  final String id, tenantId, sucursalId, usuarioId;
  final String? clienteId, notas;
  final DateTime agendadaPara, creadaEn;
  final EstadoReservaLocal estado;
  factory ReservaLocal.desdeFila(Map<String, Object?> f) => ReservaLocal(
    id: f['id'] as String,
    tenantId: f['tenant_id'] as String,
    sucursalId: f['sucursal_id'] as String,
    usuarioId: f['usuario_id'] as String,
    clienteId: f['cliente_id'] as String?,
    notas: f['notas'] as String?,
    agendadaPara: DateTime.parse(f['agendada_para'] as String),
    creadaEn: DateTime.parse(f['creada_en'] as String),
    estado: EstadoReservaLocal.desde(f['estado'] as String),
  );
  Map<String, Object?> aFila() => {
    'id': id,
    'tenant_id': tenantId,
    'sucursal_id': sucursalId,
    'usuario_id': usuarioId,
    'cliente_id': clienteId,
    'agendada_para': agendadaPara.toIso8601String(),
    'notas': notas,
    'estado': estado.codigo,
    'creada_en': creadaEn.toIso8601String(),
  };
}

class ItemReservaLocal {
  const ItemReservaLocal({
    required this.reservaId,
    required this.varianteId,
    required this.cantidad,
  });
  final String reservaId, varianteId;
  final int cantidad;
  factory ItemReservaLocal.desdeFila(Map<String, Object?> f) =>
      ItemReservaLocal(
        reservaId: f['reserva_id'] as String,
        varianteId: f['variante_id'] as String,
        cantidad: (f['cantidad'] as num).toInt(),
      );
  Map<String, Object?> aFila() => {
    'reserva_id': reservaId,
    'variante_id': varianteId,
    'cantidad': cantidad,
  };
}

class OperacionPendiente {
  const OperacionPendiente({
    required this.id,
    required this.tenantId,
    required this.sucursalId,
    required this.usuarioId,
    required this.dispositivoId,
    required this.payload,
    required this.creadaEn,
    required this.actualizadaEn,
    this.tipo = 'RESERVA',
    this.estado = EstadoOperacion.pendiente,
    this.intentos = 0,
    this.ultimoError,
  });
  final String id, tipo, tenantId, sucursalId, usuarioId, dispositivoId;
  final Map<String, dynamic> payload;
  final DateTime creadaEn, actualizadaEn;
  final EstadoOperacion estado;
  final int intentos;
  final String? ultimoError;
  factory OperacionPendiente.desdeFila(Map<String, Object?> f) =>
      OperacionPendiente(
        id: f['id'] as String,
        tipo: f['tipo'] as String,
        tenantId: f['tenant_id'] as String,
        sucursalId: f['sucursal_id'] as String,
        usuarioId: f['usuario_id'] as String,
        dispositivoId: f['dispositivo_id'] as String,
        payload: jsonDecode(f['payload'] as String) as Map<String, dynamic>,
        creadaEn: DateTime.parse(f['creada_en'] as String),
        actualizadaEn: DateTime.parse(f['actualizada_en'] as String),
        estado: EstadoOperacion.desde(f['estado'] as String),
        intentos: (f['intentos'] as num).toInt(),
        ultimoError: f['ultimo_error'] as String?,
      );
  Map<String, Object?> aFila() => {
    'id': id,
    'tipo': tipo,
    'estado': estado.codigo,
    'tenant_id': tenantId,
    'sucursal_id': sucursalId,
    'usuario_id': usuarioId,
    'dispositivo_id': dispositivoId,
    'payload': jsonEncode(payload),
    'intentos': intentos,
    'ultimo_error': ultimoError,
    'creada_en': creadaEn.toIso8601String(),
    'actualizada_en': actualizadaEn.toIso8601String(),
  };
}

class ReservaLocalVista {
  const ReservaLocalVista(
    this.reserva,
    this.items,
    this.operacion, {
    this.sucursalNombre,
  });
  final ReservaLocal reserva;
  final List<ItemReservaLocal> items;
  final OperacionPendiente operacion;
  final String? sucursalNombre;
  int get unidades => items.fold(0, (n, i) => n + i.cantidad);
}

String? puedeAgregar(
  List<ItemReservaLocal> items,
  String varianteId,
  int cantidad,
  int stockLocal,
) {
  if (cantidad < 1) return 'La cantidad debe ser mayor a cero.';
  final existentes = items
      .where((i) => i.varianteId == varianteId)
      .fold<int>(0, (n, i) => n + i.cantidad);
  if (cantidad + existentes > 10) {
    return 'Puedes reservar un máximo de 10 unidades por variante.';
  }
  if (cantidad + existentes > stockLocal) {
    return 'Sin existencia local suficiente';
  }
  if (existentes == 0 && items.length >= 20) {
    return 'Puedes reservar un máximo de 20 variantes.';
  }
  return null;
}

String? validarVisita(DateTime agendadaPara, DateTime ahora) =>
    !agendadaPara.isAfter(ahora) ? 'Elegí una fecha y hora futuras.' : null;
Map<String, dynamic> construirPayload(
  ReservaLocal r,
  List<ItemReservaLocal> items,
  String dispositivoId,
) => {
  'branch_id': r.sucursalId,
  'scheduled_at': r.agendadaPara.toUtc().toIso8601String(),
  'items': items
      .map((i) => {'variant_id': i.varianteId, 'quantity': i.cantidad})
      .toList(),
  'notes': r.notas,
  'client_key': r.id,
  'origin': 'OFFLINE',
  'device_id': dispositivoId,
  'client_created_at': r.creadaEn.toUtc().toIso8601String(),
  if (r.clienteId != null) 'customer_id': r.clienteId,
};
bool puedeCancelarLocal(OperacionPendiente op) =>
    op.estado == EstadoOperacion.pendiente;
