import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../usuarios_catalogo/application/session_controller.dart';
import '../../usuarios_catalogo/domain/usuario.dart';
import '../../../core/offline/conectividad.dart';
import '../domain/sincronizacion.dart';
import '../infrastructure/catalogo_local_dao.dart';
import 'catalogo_offline_controller.dart';

class CatalogoAutoSync {
  CatalogoAutoSync({
    required this.controller,
    required this.dao,
    required this.online,
    this.usuario,
    this.esWifi = false,
  });

  final CatalogoOfflineController controller;
  final CatalogoLocalDao dao;
  final bool online;
  final Usuario? usuario;
  final bool esWifi;

  bool _ejecutando = false;
  Timer? _timer;

  void iniciarTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(minutes: 5), (_) {
      unawaited(notificar('timer'));
    });
  }

  void detenerTimer() {
    _timer?.cancel();
    _timer = null;
  }

  void dispose() {
    detenerTimer();
  }

  Future<bool> notificar(String evento) async {
    final tieneModulo = puedeOperarOffline(usuario);
    final sesionReal = usuario != null && usuario!.empresa != null;

    if (!online || !sesionReal || !tieneModulo) return false;

    final meta = await dao.meta();
    final versionLocal = meta.version;
    final ultimaDescarga = meta.descargadoEn;

    final ev = evento == 'foreground' ? 'visible' : evento;

    final debe = evento == 'manual' ||
        debeActualizarCatalogo(
          online: online,
          sesionReal: sesionReal,
          tieneModuloOffline: tieneModulo,
          versionLocal: versionLocal,
          ultimaDescarga: ultimaDescarga,
          evento: ev,
        );

    if (!debe) return false;
    if (_ejecutando || controller.descargando) return false;

    _ejecutando = true;
    try {
      final imagenesConDatos =
          await dao.base.leerMeta('imagenes_con_datos') == 'true';
      final descargarImagenes = esWifi || imagenesConDatos;

      await controller.descargar(
        sucursalId: meta.sucursalId,
        descargarImagenes: descargarImagenes,
      );
      return true;
    } finally {
      _ejecutando = false;
    }
  }
}

final catalogoAutoSyncProvider = Provider<CatalogoAutoSync>((ref) {
  final controller = ref.watch(catalogoOfflineProvider.notifier);
  final dao = ref.watch(catalogoLocalDaoProvider);
  final usuario = ref.watch(sessionProvider.select((s) => s.usuario));
  final online = ref.watch(conectividadProvider).asData?.value ?? true;

  final autoSync = CatalogoAutoSync(
    controller: controller,
    dao: dao,
    online: online,
    usuario: usuario,
    esWifi: false,
  );

  ref.onDispose(autoSync.dispose);
  return autoSync;
});
