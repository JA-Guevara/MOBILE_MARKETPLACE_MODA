import 'dart:async';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:workmanager/workmanager.dart';

import '../network/api_client.dart';
import '../network/retry_policy.dart';
import '../../features/usuarios_catalogo/domain/usuario.dart';
import 'base_local.dart';
import '../../features/operacion_offline/domain/sincronizacion.dart';
import '../../features/operacion_offline/infrastructure/operaciones_dao.dart';
import '../../features/operacion_offline/infrastructure/sync_api.dart';

const String kSincronizacionFondoTask = 'com.fashionstore.sincronizacion_fondo';
const String kSincronizacionChannelId = 'fashionstore_sync_channel';
const String kSincronizacionChannelName = 'Sincronización en segundo plano';

abstract class RegistradorSincronizacion {
  Future<void> inicializar();
  Future<void> programar(Duration frecuencia);
  Future<void> cancelar();
}

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    try {
      final resultado = await SincronizacionFondo.ejecutarSincronizacion();
      return resultado;
    } catch (_) {
      return false;
    }
  });
}

class SincronizacionFondo {
  static final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();
  static bool _inicializado = false;

  static Future<void> inicializar({
    bool isInDebugMode = false,
    bool omitirWorkmanager = false,
    RegistradorSincronizacion? registrador,
  }) async {
    if (_inicializado) return;

    // Inicializar notificaciones locales
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    const initSettings = InitializationSettings(
      android: androidInit,
      iOS: iosInit,
    );

    try {
      await _notifications.initialize(settings: initSettings);
    } catch (_) {
      // Ignorar en entornos sin soporte de plataforma nativa
    }

    if (!omitirWorkmanager) {
      try {
        await Workmanager().initialize(
          callbackDispatcher,
          isInDebugMode: isInDebugMode,
        );
      } catch (_) {
        // En tests o plataformas de escritorio/web
      }
    }

    _inicializado = true;
  }

  static Future<void> programar({
    Duration frecuencia = const Duration(minutes: 15),
    RegistradorSincronizacion? registrador,
  }) async {
    try {
      await Workmanager().registerPeriodicTask(
        'fs_periodic_sync',
        kSincronizacionFondoTask,
        frequency: frecuencia,
        constraints: Constraints(
          networkType: NetworkType.connected,
          requiresBatteryNotLow: true,
        ),
        existingWorkPolicy: ExistingWorkPolicy.keep,
      );
    } catch (_) {
      // Ignorar en tests o plataformas sin workmanager
    }
  }

  static Future<void> cancelar() async {
    try {
      await Workmanager().cancelByUniqueName('fs_periodic_sync');
    } catch (_) {}
  }

  static Future<bool> ejecutarSincronizacion({
    BaseLocal? base,
    SyncApi? api,
    FlutterLocalNotificationsPlugin? notificaciones,
    RetryPolicy? retryPolicy,
    Usuario? usuario,
    Future<bool> Function()? hayRed,
    DateTime Function()? ahora,
  }) async {
    final baseLocal = base ?? BaseLocal();
    final dao = OperacionesDao(baseLocal);
    final syncApi = api ?? SyncApi(ApiClient());
    final notifs = notificaciones ?? _notifications;
    final policy = retryPolicy ?? RetryPolicy();

    try {
      final pendientes = await dao.tomarParaEnvio(limite: 50);
      if (pendientes.isEmpty) {
        return true;
      }

      final lotes = enLotes(pendientes, 50);
      int totalConfirmadas = 0;
      int totalConflictos = 0;
      int totalRechazadas = 0;

      for (final lote in lotes) {
        final ops = lote.map(SyncOperationWire.desdeOperacion).toList();
        try {
          final resp = await syncApi.postBatch(ops);
          await dao.aplicarResultados(resp.results);
          totalConfirmadas += resp.confirmed;
          totalConflictos += resp.conflicts;
          totalRechazadas += resp.rejected;
        } catch (_) {
          // Si falla un lote, aplicar backoff de reintento según retryPolicy
          policy.esperaPara(1, null);
          return false;
        }
      }

      if (totalConfirmadas > 0 || totalConflictos > 0) {
        await _mostrarNotificacion(
          notifs: notifs,
          titulo: 'Sincronización en segundo plano',
          cuerpo:
              'Operaciones sincronizadas: $totalConfirmadas confirmadas'
              '${totalConflictos > 0 ? ', $totalConflictos en conflicto' : ''}'
              '${totalRechazadas > 0 ? ', $totalRechazadas rechazadas' : ''}.',
        );
      }

      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<void> _mostrarNotificacion({
    required FlutterLocalNotificationsPlugin notifs,
    required String titulo,
    required String cuerpo,
  }) async {
    const androidDetails = AndroidNotificationDetails(
      kSincronizacionChannelId,
      kSincronizacionChannelName,
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
    );
    const iosDetails = DarwinNotificationDetails();
    const notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    try {
      await notifs.show(
        id: 1001,
        title: titulo,
        body: cuerpo,
        notificationDetails: notificationDetails,
      );
    } catch (_) {}
  }
}
