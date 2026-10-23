import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/offline/base_local.dart';
import '../../usuarios_catalogo/application/session_controller.dart';
import '../../usuarios_catalogo/domain/usuario.dart';
import '../../ventas_pagos/infrastructure/commerce_api.dart';
import '../domain/catalogo_local.dart';
import '../domain/reserva_local.dart';
import '../infrastructure/reservas_locales_dao.dart';
import 'catalogo_offline_controller.dart';

class EstadoReservaOffline {
  const EstadoReservaOffline({
    this.items = const [],
    this.sucursalId,
    this.agendadaPara,
    this.clienteId,
    this.notas = '',
    this.error,
    this.guardando = false,
    this.creadaId,
  });
  final List<ItemReservaLocal> items;
  final String? sucursalId, clienteId, error, creadaId;
  final DateTime? agendadaPara;
  final String notas;
  final bool guardando;
  EstadoReservaOffline copyWith({
    List<ItemReservaLocal>? items,
    String? sucursalId,
    DateTime? agendadaPara,
    String? clienteId,
    String? notas,
    String? error,
    bool? guardando,
    String? creadaId,
    bool limpiarCliente = false,
  }) => EstadoReservaOffline(
    items: items ?? this.items,
    sucursalId: sucursalId ?? this.sucursalId,
    agendadaPara: agendadaPara ?? this.agendadaPara,
    clienteId: limpiarCliente ? null : clienteId ?? this.clienteId,
    notas: notas ?? this.notas,
    error: error,
    guardando: guardando ?? this.guardando,
    creadaId: creadaId,
  );
}

class ReservaOfflineController extends StateNotifier<EstadoReservaOffline> {
  ReservaOfflineController(
    this.base,
    this.dao,
    this.usuario,
    this.catalogo,
    this.actualizar,
  ) : super(const EstadoReservaOffline());
  final BaseLocal base;
  final ReservasLocalesDao dao;
  final Usuario? usuario;
  final EstadoCatalogoOffline Function() catalogo;
  final Future<void> Function() actualizar;
  String? agregar(VarianteLocal v, {int cantidad = 1}) {
    if (state.guardando) return 'La reserva se está guardando.';
    if (!puedeOperarOffline(usuario) ||
        usuario?.suscripcion?.permite('reservations') != true) {
      return 'Tu suscripción permite consultar, pero no registrar reservas sin conexión.';
    }
    if (!v.activa) return 'Esta variante no está activa.';
    final c = catalogo();
    if (c.version == null || c.sucursalId == null) {
      return 'Descargá primero el catálogo de tu empresa.';
    }
    final error = puedeAgregar(
      state.items,
      v.id,
      cantidad,
      c.datos.stock(v.id),
    );
    if (error != null) {
      state = state.copyWith(error: error);
      return error;
    }
    final anteriores = state.items.where((i) => i.varianteId == v.id);
    final total =
        cantidad + (anteriores.isEmpty ? 0 : anteriores.first.cantidad);
    state = state.copyWith(
      items: [
        ...state.items.where((i) => i.varianteId != v.id),
        ItemReservaLocal(reservaId: '', varianteId: v.id, cantidad: total),
      ],
      sucursalId: c.sucursalId,
    );
    return null;
  }

  void quitar(String varianteId) {
    if (!state.guardando) {
      state = state.copyWith(
        items: state.items.where((i) => i.varianteId != varianteId).toList(),
      );
    }
  }

  void configurar({
    DateTime? visita,
    String? clienteId,
    String? notas,
    bool limpiarCliente = false,
  }) {
    if (!state.guardando) {
      state = state.copyWith(
        agendadaPara: visita,
        clienteId: clienteId,
        notas: notas,
        limpiarCliente: limpiarCliente,
      );
    }
  }

  void vaciar() => state = const EstadoReservaOffline();
  Future<String?> confirmar() async {
    if (state.guardando) return null;
    final u = usuario;
    if (!puedeOperarOffline(u) ||
        u?.suscripcion?.permite('reservations') != true) {
      state = state.copyWith(
        error: 'Tu suscripción no permite registrar reservas.',
      );
      return null;
    }
    if (state.items.isEmpty) {
      state = state.copyWith(error: 'Agregá al menos una prenda.');
      return null;
    }
    if (state.agendadaPara == null ||
        validarVisita(state.agendadaPara!, DateTime.now()) != null) {
      state = state.copyWith(error: 'Elegí una fecha y hora futuras.');
      return null;
    }
    if (state.clienteId != null &&
        (!u!.puede('reservations.write') ||
            !catalogo().datos.clientes.any((c) => c.id == state.clienteId))) {
      state = state.copyWith(
        error: 'El cliente no está disponible para tu perfil.',
      );
      return null;
    }
    state = state.copyWith(guardando: true);
    try {
      final dispositivo = await base.dispositivoId();
      final id = CommerceApi.nuevaClaveSolicitud();
      final ahora = DateTime.now();
      final r = ReservaLocal(
        id: id,
        tenantId: u!.empresa!.id,
        sucursalId: state.sucursalId!,
        usuarioId: u.id,
        clienteId: state.clienteId,
        agendadaPara: state.agendadaPara!,
        notas: state.notas.trim().isEmpty ? null : state.notas.trim(),
        creadaEn: ahora,
      );
      final items = state.items
          .map(
            (i) => ItemReservaLocal(
              reservaId: id,
              varianteId: i.varianteId,
              cantidad: i.cantidad,
            ),
          )
          .toList();
      final op = OperacionPendiente(
        id: CommerceApi.nuevaClaveSolicitud(),
        tenantId: r.tenantId,
        sucursalId: r.sucursalId,
        usuarioId: r.usuarioId,
        dispositivoId: dispositivo,
        payload: construirPayload(r, items, dispositivo),
        creadaEn: ahora,
        actualizadaEn: ahora,
      );
      await dao.registrar(r, items, op);
      await actualizar();
      if (mounted) state = EstadoReservaOffline(creadaId: id);
      return id;
    } catch (error) {
      if (mounted) {
        state = state.copyWith(
          guardando: false,
          error: 'No se guardó la reserva. $error',
        );
      }
      return null;
    }
  }

  Future<void> cancelar(String id) async {
    await dao.cancelar(id);
    await actualizar();
  }
}

final reservasLocalesDaoProvider = Provider((ref) {
  final u = ref.watch(sessionProvider.select((s) => s.usuario));
  return ReservasLocalesDao(
    ref.watch(baseLocalProvider),
    tenantId: u?.empresa?.id ?? '',
    usuarioId: u?.id ?? '',
  );
});
final reservasLocalesProvider = FutureProvider.autoDispose(
  (ref) => ref.watch(reservasLocalesDaoProvider).listar(),
);
final reservaLocalProvider = FutureProvider.autoDispose
    .family<ReservaLocalVista?, String>(
      (ref, id) => ref.watch(reservasLocalesDaoProvider).obtener(id),
    );
final reservaOfflineProvider =
    StateNotifierProvider<ReservaOfflineController, EstadoReservaOffline>((
      ref,
    ) {
      final usuario = ref.watch(sessionProvider.select((s) => s.usuario));
      return ReservaOfflineController(
        ref.watch(baseLocalProvider),
        ref.watch(reservasLocalesDaoProvider),
        usuario,
        () => ref.read(catalogoOfflineProvider),
        () async {
          await ref.read(catalogoOfflineProvider.notifier).iniciar();
          ref.invalidate(reservasLocalesProvider);
          ref.invalidate(reservaLocalProvider);
        },
      );
    });
