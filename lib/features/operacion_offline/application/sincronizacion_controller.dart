import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/network/retry_policy.dart';
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
    this.reintentarEn,
  });

  final bool sincronizando;
  final int pendientes;
  final DateTime? ultimoSync;
  final String? ultimoError;
  final SyncBatchResponse? ultimoResultado;
  final DateTime? reintentarEn;

  SincronizacionEstado copyWith({
    bool? sincronizando,
    int? pendientes,
    DateTime? ultimoSync,
    String? ultimoError,
    SyncBatchResponse? ultimoResultado,
    DateTime? reintentarEn,
    bool limpiarEspera = false,
  }) => SincronizacionEstado(
    sincronizando: sincronizando ?? this.sincronizando,
    pendientes: pendientes ?? this.pendientes,
    ultimoSync: ultimoSync ?? this.ultimoSync,
    ultimoError: ultimoError,
    ultimoResultado: ultimoResultado ?? this.ultimoResultado,
    reintentarEn: limpiarEspera ? null : reintentarEn ?? this.reintentarEn,
  );
}

final sincronizacionControllerProvider =
    StateNotifierProvider<SincronizacionController, SincronizacionEstado>((
      ref,
    ) {
      final base = ref.watch(baseLocalProvider);
      final dao = OperacionesDao(base);
      final api = SyncApi(ref.watch(apiClientProvider));
      final identity = ref.watch(
        sessionProvider.select((s) => (s.usuario?.empresa?.id, s.usuario?.id)),
      );

      return SincronizacionController(
        dao: dao,
        api: api,
        tenantId: identity.$1,
        usuarioId: identity.$2,
        habilitado: identity.$1 != null && identity.$2 != null,
      );
    });

class SincronizacionController extends StateNotifier<SincronizacionEstado> {
  SincronizacionController({
    required this.dao,
    required this.api,
    RetryPolicy? retryPolicy,
    this.tenantId,
    this.usuarioId,
    this.habilitado = true,
  }) : retryPolicy = retryPolicy ?? RetryPolicy(),
       super(const SincronizacionEstado()) {
    actualizarContadores();
  }

  final OperacionesDao dao;
  final SyncApi api;
  final RetryPolicy retryPolicy;
  final String? tenantId, usuarioId;
  final bool habilitado;
  Timer? _retryTimer;
  int _intentos = 0;

  @override
  void dispose() {
    _retryTimer?.cancel();
    super.dispose();
  }

  Future<void> actualizarContadores() async {
    if (!habilitado) return;
    try {
      final pendientes = await dao.listarPendientes(
        tenantId: tenantId,
        usuarioId: usuarioId,
      );
      if (!mounted) return;
      state = state.copyWith(pendientes: pendientes.length);
    } catch (_) {}
  }

  Future<SyncBatchResponse?> sincronizarAhora() async {
    if (!mounted || !habilitado || state.sincronizando) return null;
    if (state.reintentarEn?.isAfter(DateTime.now()) ?? false) return null;
    _retryTimer?.cancel();

    state = state.copyWith(
      sincronizando: true,
      ultimoError: null,
      limpiarEspera: true,
    );
    final ahora = DateTime.now();

    try {
      if (tenantId != null && usuarioId != null) {
        final operations = await dao.listarTodas(tenantId!, usuarioId!);
        final unresolved = operations
            .where(
              (op) =>
                  op['estado'] == 'CONFLICTO' ||
                  op['estado'] == 'ENVIADA' ||
                  op['refund_status'] == 'pending',
            )
            .take(200)
            .map((op) => op['id'] as String)
            .toList();
        if (unresolved.isNotEmpty) {
          await dao.aplicarResultados(await api.obtenerEstado(unresolved));
        }
      }
      final pendientes = await dao.tomarParaEnvio(
        limite: 50,
        tenantId: tenantId,
        usuarioId: usuarioId,
      );
      if (pendientes.isEmpty) {
        state = state.copyWith(sincronizando: false, pendientes: 0);
        return null;
      }

      final lotes = enLotes(pendientes, 50);
      SyncBatchResponse? ultimaRespuesta;

      for (final lote in lotes) {
        final ops = lote
            .map((op) => SyncOperationWire.desdeOperacion(op))
            .toList();

        try {
          final resp = await api.postBatch(ops);
          final ids = lote.map((op) => op.id).toSet();
          if (resp.results.any(
            (result) => !ids.contains(result.clientRequestId),
          )) {
            throw StateError('El resultado no corresponde a este lote.');
          }
          ultimaRespuesta = resp;
          await dao.aplicarResultados(resp.results);
          final recibidas = resp.results
              .map((result) => result.clientRequestId)
              .toSet();
          await dao.liberarEnvio(
            lote
                .where((op) => !recibidas.contains(op.id))
                .map((op) => op.id)
                .toList(),
          );

          await dao.registrarHistorialSync(
            tenantId: tenantId,
            usuarioId: usuarioId,
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
          await dao.liberarEnvio(lote.map((op) => op.id).toList());
          if (!mounted) return null;
          final retry =
              e is ApiException &&
              (e.sinConexion || e.statusCode == 429 || e.statusCode == 503);
          if (retry) {
            _intentos += 1;
            final wait = retryPolicy.esperaPara(_intentos, e.retryAfter);
            state = state.copyWith(
              ultimoError:
                  'En espera · reintenta en ${wait.inSeconds} s. Tus operaciones siguen pendientes.',
              reintentarEn: DateTime.now().add(wait),
            );
          } else {
            state = state.copyWith(
              ultimoError:
                  'No se pudo enviar el lote. Tus operaciones siguen pendientes.',
            );
          }
          await dao.registrarHistorialSync(
            tenantId: tenantId,
            usuarioId: usuarioId,
            iniciadoEn: ahora,
            terminadoEn: DateTime.now(),
            enviadas: ops.length,
            confirmadas: 0,
            conflictos: 0,
            rechazadas: 0,
            httpStatus: e is ApiException ? e.statusCode : null,
            codigoError: e is ApiException && e.statusCode != null
                ? 'HTTP_${e.statusCode}'
                : 'NETWORK',
          );
          break;
        }
      }

      final restantes = await dao.listarPendientes(
        tenantId: tenantId,
        usuarioId: usuarioId,
      );
      if (!mounted) return null;
      if (state.reintentarEn == null) _intentos = 0;
      state = state.copyWith(
        sincronizando: false,
        pendientes: restantes.length,
        ultimoSync: DateTime.now(),
        ultimoResultado: ultimaRespuesta,
        ultimoError: state.ultimoError,
      );
      return ultimaRespuesta;
    } catch (_) {
      if (mounted) {
        state = state.copyWith(
          ultimoError:
              'El servidor no respondió. Las operaciones siguen guardadas.',
        );
      }
      return null;
    } finally {
      if (mounted && state.sincronizando) {
        state = state.copyWith(
          sincronizando: false,
          ultimoError: state.ultimoError,
        );
      }
      if (mounted && state.reintentarEn != null) {
        final remaining = state.reintentarEn!.difference(DateTime.now());
        _retryTimer?.cancel();
        _retryTimer = Timer(
          remaining.isNegative ? Duration.zero : remaining,
          () {
            if (mounted) unawaited(sincronizarAhora());
          },
        );
      }
    }
  }
}
