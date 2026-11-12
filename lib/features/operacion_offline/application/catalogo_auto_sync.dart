import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
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
  bool _disposed = false;
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
    _disposed = true;
    detenerTimer();
  }

  Future<bool> notificar(String evento) async {
    if (_disposed || !controller.mounted || _ejecutando) return false;

    final tieneModulo = puedeOperarOffline(usuario);
    final sesionReal = usuario != null && usuario!.empresa != null;

    if (!online || !sesionReal || !tieneModulo) return false;

    // Reserve before the first await so foreground, reconnect, and login
    // notifications cannot all pass the same in-flight check.
    _ejecutando = true;
    try {
      final meta = await dao.meta();
      if (_disposed || !controller.mounted) return false;
      if (evento != 'manual' &&
          await dao.base.leerMeta('descarga_automatica') == 'false') {
        return false;
      }
      if (_disposed || !controller.mounted) return false;
      final versionLocal = meta.version;
      final ultimaDescarga = meta.descargadoEn;

      final ev = evento == 'foreground' ? 'visible' : evento;

      final debe =
          evento == 'manual' ||
          debeActualizarCatalogo(
            online: online,
            sesionReal: sesionReal,
            tieneModuloOffline: tieneModulo,
            versionLocal: versionLocal,
            ultimaDescarga: ultimaDescarga,
            evento: ev,
          );

      if (!debe || _disposed || !controller.mounted) return false;
      if (controller.descargando) return false;

      final imagenesConDatos =
          await dao.base.leerMeta('imagenes_con_datos') == 'true';
      if (_disposed || !controller.mounted) return false;
      var wifi = esWifi;
      if (!wifi) {
        try {
          wifi = (await Connectivity().checkConnectivity()).contains(
            ConnectivityResult.wifi,
          );
        } catch (_) {
          wifi = false;
        }
      }
      final descargarImagenes = wifi || imagenesConDatos;

      await controller.descargar(
        sucursalId: meta.sucursalId,
        descargarImagenes: descargarImagenes,
      );
      return !_disposed && controller.mounted;
    } catch (_) {
      // Un fallo temporal de SQLite/red no debe dejar un Future sin manejar
      // desde los eventos de ciclo de vida o el temporizador.
      return false;
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
  autoSync.iniciarTimer();
  return autoSync;
});
