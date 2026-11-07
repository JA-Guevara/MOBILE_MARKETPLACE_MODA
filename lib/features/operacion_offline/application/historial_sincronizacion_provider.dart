import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/offline/base_local.dart';
import '../../usuarios_catalogo/application/session_controller.dart';
import '../domain/sincronizacion.dart';
import '../infrastructure/operaciones_dao.dart';

/// CU-19: resultados de sincronización guardados en este dispositivo para la
/// cuenta actual. La empresa y el usuario salen de la sesión (RN03).
final historialSincronizacionProvider =
    FutureProvider.autoDispose<List<RegistroSincronizacion>>((ref) async {
      final identidad = ref.watch(
        sessionProvider.select((s) => (s.usuario?.empresa?.id, s.usuario?.id)),
      );
      final tenantId = identidad.$1, usuarioId = identidad.$2;
      if (tenantId == null || usuarioId == null) return const [];
      return OperacionesDao(
        ref.watch(baseLocalProvider),
      ).listarHistorial(tenantId: tenantId, usuarioId: usuarioId);
    });
