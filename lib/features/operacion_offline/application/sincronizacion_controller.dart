import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/offline/base_local.dart';
import '../../usuarios_catalogo/application/session_controller.dart';
import '../domain/sincronizacion.dart';
import '../infrastructure/operaciones_dao.dart';
import '../infrastructure/sync_api.dart';

class SincronizacionEstado {
  const SincronizacionEstado({
    this.sincronizando = false,
    this.pendientes = 0,
    this.ultimoSync,
    this.ultimoError,
    this.ultimoResultado,
  });

  final bool sincronizando;
  final int pendientes;
  final DateTime? ultimoSync;
  final String? ultimoError;
  final SyncBatchResponse? ultimoResultado;

  SincronizacionEstado copyWith({
    bool? sincronizando,
    int? pendientes,
    DateTime? ultimoSync,
    String? ultimoError,
    SyncBatchResponse? ultimoResultado,
  }) =>
      SincronizacionEstado(
        sincronizando: sincronizando ?? this.sincronizando,
        pendientes: pendientes ?? this.pendientes,
        ultimoSync: ultimoSync ?? this.ultimoSync,
        ultimoError: ultimoError,
        ultimoResultado: ultimoResultado ?? this.ultimoResultado,
      );
}

final sincronizacionControllerProvider =
    StateNotifierProvider<SincronizacionController, SincronizacionEstado>((ref) {
  final base = ref.watch(baseLocalProvider);
  final dao = OperacionesDao(base);
  final api = SyncApi(ref.watch(apiClientProvider));

  return SincronizacionController(dao: dao, api: api);
});

class SincronizacionController extends StateNotifier<SincronizacionEstado> {
  SincronizacionController({
    required this.dao,
    required this.api,
  }) : super(const SincronizacionEstado()) {
    actualizarContadores();
  }

  final OperacionesDao dao;
  final SyncApi api;

  Future<void> actualizarContadores() async {
    try {
      final pendientes = await dao.listarPendientes();
      state = state.copyWith(pendientes: pendientes.length);
    } catch (_) {}
  }

  Future<SyncBatchResponse?> sincronizarAhora() async {
    if (state.sincronizando) return null;

    state = state.copyWith(sincronizando: true, ultimoError: null);
    final ahora = DateTime.now();

    try {
      final pendientes = await dao.tomarParaEnvio(limite: 50);
      if (pendientes.isEmpty) {
        state = state.copyWith(sincronizando: false, pendientes: 0);
        return null;
      }

      final lotes = enLotes(pendientes, 50);
      SyncBatchResponse? ultimaRespuesta;

      for (final lote in lotes) {
        final ops = lote.map((op) => SyncOperationWire.desdeOperacion(op)).toList();

        try {
          final resp = await api.postBatch(ops);
          ultimaRespuesta = resp;
          await dao.aplicarResultados(resp.results);

          await dao.registrarHistorialSync(
            iniciadoEn: ahora,
            terminadoEn: DateTime.now(),
            enviadas: ops.length,
            confirmadas: resp.confirmed,
            conflictos: resp.conflicts,
            rechazadas: resp.rejected,
            loteId: resp.batchId,
            httpStatus: 200,
          );
        } catch (e) {
          state = state.copyWith(ultimoError: 'Error al enviar lote: $e');
          await dao.registrarHistorialSync(
            iniciadoEn: ahora,
            terminadoEn: DateTime.now(),
            enviadas: ops.length,
            confirmadas: 0,
            conflictos: 0,
            rechazadas: 0,
            codigoError: 'NETWORK',
          );
          break;
        }
      }

      final restantes = await dao.listarPendientes();
      state = state.copyWith(
        sincronizando: false,
        pendientes: restantes.length,
        ultimoSync: DateTime.now(),
        ultimoResultado: ultimaRespuesta,
      );
      return ultimaRespuesta;
    } finally {
      if (state.sincronizando) {
        state = state.copyWith(sincronizando: false);
      }
    }
  }
}
