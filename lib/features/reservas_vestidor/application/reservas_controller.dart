import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../ventas_pagos/application/commerce_providers.dart';
import '../../ventas_pagos/domain/commerce_models.dart';
import '../../ventas_pagos/infrastructure/commerce_api.dart';
import '../domain/reserva.dart';
import '../infrastructure/reservas_api.dart';

// --- Mis reservas --------------------------------------------------------

class EstadoReservas {
  const EstadoReservas({
    this.reservas = const [],
    this.cargando = true,
    this.ocupado = false,
    this.error,
    this.mensaje,
  });

  final List<Reserva> reservas;
  final bool cargando;
  final bool ocupado;
  final String? error;
  final String? mensaje;

  EstadoReservas copyWith({
    List<Reserva>? reservas,
    bool? cargando,
    bool? ocupado,
    String? error,
    String? mensaje,
    bool limpiarAvisos = false,
  }) => EstadoReservas(
    reservas: reservas ?? this.reservas,
    cargando: cargando ?? this.cargando,
    ocupado: ocupado ?? this.ocupado,
    error: limpiarAvisos ? null : (error ?? this.error),
    mensaje: limpiarAvisos ? null : (mensaje ?? this.mensaje),
  );
}

/// «Mis reservas» (`mis-reservas.component.ts`).
class ReservasController extends StateNotifier<EstadoReservas> {
  ReservasController(this._api) : super(const EstadoReservas());

  final ReservasApi _api;

  Future<void> cargar() async {
    state = state.copyWith(cargando: true, limpiarAvisos: true);
    try {
      final pagina = await _api.mias();
      state = state.copyWith(reservas: pagina.items, cargando: false);
    } on ApiException catch (error) {
      state = state.copyWith(cargando: false, error: error.message);
    }
  }

  Future<void> cancelar(Reserva reserva) async {
    if (state.ocupado) return;
    state = state.copyWith(ocupado: true, limpiarAvisos: true);
    try {
      await _api.cancelar(reserva.id);
      await cargar();
      state = state.copyWith(ocupado: false, mensaje: 'Cancelamos tu visita.');
    } on ApiException catch (error) {
      state = state.copyWith(ocupado: false, error: error.message);
    }
  }
}

final StateNotifierProvider<ReservasController, EstadoReservas>
reservasProvider = StateNotifierProvider<ReservasController, EstadoReservas>(
  (ref) => ReservasController(ref.watch(reservasApiProvider)),
);

// --- Nueva reserva -------------------------------------------------------

class EstadoNuevaReserva {
  const EstadoNuevaReserva({
    this.sucursales = const [],
    this.sucursalId = '',
    this.fecha,
    this.items = const [],
    this.notas = '',
    this.disponibilidad = const [],
    this.comprobandoDisponibilidad = false,
    this.cargando = true,
    this.ocupado = false,
    this.error,
    this.creada,
  });

  final List<Sucursal> sucursales;
  final String sucursalId;

  /// Cuándo va a pasar por la sucursal. `null` hasta que se elige.
  final DateTime? fecha;

  final List<ItemReserva> items;
  final String notas;

  /// Lo que contestó el backend sobre el stock de esta sucursal.
  final List<DisponibilidadVariante> disponibilidad;
  final bool comprobandoDisponibilidad;

  final bool cargando;
  final bool ocupado;
  final String? error;
  final Reserva? creada;

  int get unidades => items.fold(0, (total, item) => total + item.cantidad);

  /// Variantes que la sucursal no puede cubrir.
  List<DisponibilidadVariante> get faltantes =>
      disponibilidad.where((d) => !d.disponible).toList();

  bool get hayFaltantes => faltantes.isNotEmpty;

  bool get sePuedeReservar =>
      items.isNotEmpty &&
      sucursalId.isNotEmpty &&
      fecha != null &&
      !hayFaltantes &&
      !comprobandoDisponibilidad &&
      !ocupado;

  EstadoNuevaReserva copyWith({
    List<Sucursal>? sucursales,
    String? sucursalId,
    DateTime? fecha,
    List<ItemReserva>? items,
    String? notas,
    List<DisponibilidadVariante>? disponibilidad,
    bool? comprobandoDisponibilidad,
    bool? cargando,
    bool? ocupado,
    String? error,
    Reserva? creada,
    bool limpiarError = false,
  }) => EstadoNuevaReserva(
    sucursales: sucursales ?? this.sucursales,
    sucursalId: sucursalId ?? this.sucursalId,
    fecha: fecha ?? this.fecha,
    items: items ?? this.items,
    notas: notas ?? this.notas,
    disponibilidad: disponibilidad ?? this.disponibilidad,
    comprobandoDisponibilidad:
        comprobandoDisponibilidad ?? this.comprobandoDisponibilidad,
    cargando: cargando ?? this.cargando,
    ocupado: ocupado ?? this.ocupado,
    error: limpiarError ? null : (error ?? this.error),
    creada: creada ?? this.creada,
  );
}

/// Agendar una visita al probador (`nueva-reserva.component.ts`).
///
/// La selección de prendas vive en el teléfono hasta confirmar —la web la
/// guarda en `TryOnListService`, del lado del navegador, por lo mismo—: una
/// reserva a medio armar no debería ocupar stock de la sucursal.
class NuevaReservaController extends StateNotifier<EstadoNuevaReserva> {
  NuevaReservaController(this._api, this._comercio)
    : super(const EstadoNuevaReserva());

  final ReservasApi _api;
  final CommerceApi _comercio;
  int _revisionDisponibilidad = 0;

  Future<void> cargar() async {
    state = state.copyWith(cargando: true, limpiarError: true);
    try {
      final sucursales = await _comercio.sucursales();
      state = state.copyWith(
        sucursales: sucursales,
        sucursalId: state.sucursalId.isNotEmpty
            ? state.sucursalId
            : (sucursales.isEmpty ? '' : sucursales.first.id),
        cargando: false,
      );
      await revisarDisponibilidad();
    } on ApiException catch (error) {
      state = state.copyWith(cargando: false, error: error.message);
    }
  }

  Future<void> elegirSucursal(String id) async {
    if (id == state.sucursalId) return;
    state = state.copyWith(sucursalId: id);
    await revisarDisponibilidad();
  }

  void elegirFecha(DateTime fecha) =>
      state = state.copyWith(fecha: fecha, limpiarError: true);

  void escribirNotas(String notas) => state = state.copyWith(notas: notas);

  /// Agrega una variante o le suma unidades si ya estaba.
  ///
  /// Devuelve el motivo del rechazo, o `null` si entró. Los topes son los del
  /// backend (RF09): hasta 20 variantes distintas y 10 unidades por variante.
  String? agregar(ItemReserva item) {
    final existente = state.items
        .where((i) => i.variantId == item.variantId)
        .firstOrNull;
    if (existente == null && state.items.length >= maxVariantesPorReserva) {
      return 'Ya tenés $maxVariantesPorReserva prendas en tu selección.';
    }
    final total = (existente?.cantidad ?? 0) + item.cantidad;
    if (total > maxUnidadesPorVariante) {
      return 'No podés reservar más de $maxUnidadesPorVariante unidades de la misma talla.';
    }
    final items = [
      for (final i in state.items)
        if (i.variantId == item.variantId) i.copyWith(cantidad: total) else i,
      if (existente == null) item,
    ];
    state = state.copyWith(items: items);
    revisarDisponibilidad();
    return null;
  }

  void cambiarCantidad(String variantId, int cantidad) {
    if (cantidad <= 0) return quitar(variantId);
    final valor = cantidad.clamp(1, maxUnidadesPorVariante);
    state = state.copyWith(
      items: [
        for (final i in state.items)
          if (i.variantId == variantId) i.copyWith(cantidad: valor) else i,
      ],
    );
    revisarDisponibilidad();
  }

  void quitar(String variantId) {
    state = state.copyWith(
      items: state.items.where((i) => i.variantId != variantId).toList(),
    );
    revisarDisponibilidad();
  }

  /// Pregunta al backend si la sucursal elegida cubre la selección.
  ///
  /// Se consulta antes de confirmar para no hacer viajar a nadie en vano: la
  /// web hace lo mismo desde `nueva-reserva`.
  Future<void> revisarDisponibilidad() async {
    final revision = ++_revisionDisponibilidad;
    if (state.items.isEmpty || state.sucursalId.isEmpty) {
      state = state.copyWith(
        disponibilidad: const [],
        comprobandoDisponibilidad: false,
      );
      return;
    }
    final sucursal = state.sucursalId;
    final items = state.items;
    state = state.copyWith(comprobandoDisponibilidad: true);
    try {
      final disponibilidad = await _api.disponibilidad(
        branchId: sucursal,
        items: items,
      );
      if (!mounted || revision != _revisionDisponibilidad) return;
      state = state.copyWith(
        disponibilidad: disponibilidad,
        comprobandoDisponibilidad: false,
      );
    } catch (_) {
      if (!mounted || revision != _revisionDisponibilidad) return;
      // Sin respuesta se deja pasar: el `POST` vuelve a validar del lado del
      // servidor y devuelve el detalle de lo que falta.
      state = state.copyWith(
        disponibilidad: const [],
        comprobandoDisponibilidad: false,
      );
    }
  }

  Future<Reserva?> confirmar() async {
    if (!state.sePuedeReservar) return null;
    state = state.copyWith(ocupado: true, limpiarError: true);
    try {
      final reserva = await _api.crear(
        branchId: state.sucursalId,
        agendadaPara: state.fecha!,
        items: state.items,
        notas: state.notas.trim().isEmpty ? null : state.notas.trim(),
      );
      state = state.copyWith(ocupado: false, creada: reserva, items: const []);
      return reserva;
    } on ApiException catch (error) {
      state = state.copyWith(ocupado: false, error: error.message);
      return null;
    } catch (_) {
      state = state.copyWith(
        ocupado: false,
        error: 'No pudimos confirmar la reserva. Intentá nuevamente.',
      );
      return null;
    }
  }
}

/// La selección sobrevive mientras la app esté abierta: se elige una prenda
/// desde el detalle, se vuelve al catálogo, se elige otra y recién después se
/// agenda. Por eso no es `autoDispose`.
final StateNotifierProvider<NuevaReservaController, EstadoNuevaReserva>
nuevaReservaProvider =
    StateNotifierProvider<NuevaReservaController, EstadoNuevaReserva>(
      (ref) => NuevaReservaController(
        ref.watch(reservasApiProvider),
        ref.watch(commerceApiProvider),
      ),
    );
