import 'dart:async';
import 'dart:ui';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:workmanager/workmanager.dart';

import '../network/api_client.dart';
import '../network/api_exception.dart';
import '../network/retry_policy.dart';
import '../storage/token_store.dart';
import '../../features/usuarios_catalogo/domain/usuario.dart';
import '../../features/usuarios_catalogo/infrastructure/auth_api.dart';
import 'base_local.dart';
import 'conectividad.dart';
import '../../features/operacion_offline/domain/sincronizacion.dart';
import '../../features/operacion_offline/infrastructure/operaciones_dao.dart';
import '../../features/operacion_offline/infrastructure/sync_api.dart';
import '../../features/operacion_offline/infrastructure/catalogo_local_dao.dart';
import '../../features/operacion_offline/infrastructure/instantanea_api.dart';

const String kSincronizacionFondoTask = 'com.fashionstore.sincronizacion_fondo';
const String kSincronizacionChannelId = 'fashionstore_sync_channel';
const String kSincronizacionChannelName = 'Sincronización en segundo plano';

abstract class RegistradorSincronizacion {
  Future<void> inicializar();
  Future<void> programar(Duration frecuencia);
  Future<void> cancelar();
}

class _RegistradorNativo implements RegistradorSincronizacion {
  @override
  Future<void> inicializar() async {
    await Workmanager().initialize(callbackDispatcher);
    await SincronizacionFondo._iniciarNotificaciones(pedirPermiso: true);
  }

  @override
  Future<void> programar(Duration frecuencia) =>
      Workmanager().registerPeriodicTask(
        kSincronizacionFondoTask,
        kSincronizacionFondoTask,
        frequency: frecuencia,
        constraints: Constraints(
          networkType: NetworkType.connected,
          requiresBatteryNotLow: true,
        ),
        existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
      );

  @override
  Future<void> cancelar() =>
      Workmanager().cancelByUniqueName(kSincronizacionFondoTask);
}

@pragma('vm:entry-point')
void callbackDispatcher() {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  Workmanager().executeTask((task, inputData) async {
    if (task != kSincronizacionFondoTask &&
        task != Workmanager.iOSBackgroundTask) {
      return true;
    }
    return SincronizacionFondo.ejecutarSincronizacion();
  });
}

class SincronizacionFondo {
  static final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();
  static RegistradorSincronizacion _registrador = _RegistradorNativo();
  static Future<void>? _inicializacion;
  static Future<void>? _programacion;
  static bool _enviando = false;

  static void _usarRegistrador(RegistradorSincronizacion? nuevo) {
    if (nuevo != null && !identical(nuevo, _registrador)) {
      _registrador = nuevo;
      _inicializacion = null;
      _programacion = null;
    }
  }

  static Future<void> inicializar({
    bool isInDebugMode = false,
    bool omitirWorkmanager = false,
    RegistradorSincronizacion? registrador,
  }) {
    _usarRegistrador(registrador);
    return _inicializacion ??= _inicializar(omitirWorkmanager);
  }

  static Future<void> _inicializar(bool omitirWorkmanager) async {
    try {
      if (!omitirWorkmanager) await _registrador.inicializar();
    } catch (_) {
      _inicializacion = null;
      rethrow;
    }
  }

  static Future<void> programar({
    Duration frecuencia = const Duration(minutes: 15),
    RegistradorSincronizacion? registrador,
  }) {
    _usarRegistrador(registrador);
    return _programacion ??= _programar(frecuencia);
  }

  static Future<void> _programar(Duration frecuencia) async {
    try {
      await inicializar();
      await _registrador.programar(
        frecuencia < const Duration(minutes: 15)
            ? const Duration(minutes: 15)
            : frecuencia,
      );
    } catch (_) {
      _programacion = null;
      rethrow;
    }
  }

  static Future<void> cancelar({RegistradorSincronizacion? registrador}) async {
    _usarRegistrador(registrador);
    await _programacion;
    await _registrador.cancelar();
    _programacion = null;
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
    if (_enviando) return false;
    _enviando = true;
    final baseLocal = base ?? BaseLocal();
    final dao = OperacionesDao(baseLocal);
    final reloj = ahora ?? DateTime.now;
    final policy = retryPolicy ?? RetryPolicy(ahora: reloj);
    ApiClient? cliente;
    try {
      // El requisito del planificador no sustituye comprobar la red al ejecutar.
      final conectado =
          await (hayRed ??
              () async =>
                  hayConexion(await Connectivity().checkConnectivity()))();
      if (!conectado) return false;
      var identidad = usuario;
      var syncApi = api;
      if (syncApi == null) {
        final store = TokenStore();
        final refresh = await store.leerRefresh();
        if (refresh == null) return false;
        cliente = ApiClient();
        final sesion = await AuthApi(cliente).renovar(refresh);
        await store.guardarRefresh(sesion.refreshToken);
        identidad = sesion.usuario;
        cliente.dio.options.headers['Authorization'] =
            'Bearer ${sesion.accessToken}';
        cliente.dio.options.headers['X-Tenant-Slug'] = identidad.empresa?.slug;
        syncApi = SyncApi(cliente);
      }
      // El perfil SQLite nunca acredita una sesión remota; la identidad viene
      // del refresh validado o de un cliente autenticado explícito del llamador.
      final tenantId = identidad?.empresa?.id;
      if (identidad == null ||
          tenantId == null ||
          identidad.empresa?.estado != 'ACTIVA' ||
          identidad.suscripcion?.soloLectura == true) {
        return false;
      }
      final claveEspera = 'sync_fondo_hasta:$tenantId:${identidad.id}';
      final hasta = DateTime.tryParse(
        await baseLocal.leerMeta(claveEspera) ?? '',
      );
      if (hasta != null && hasta.isAfter(reloj())) return false;
      final pendientes = await dao.tomarParaEnvio(
        limite: 50,
        tenantId: tenantId,
        usuarioId: identidad.id,
      );
      if (pendientes.isEmpty) return true;
      var confirmadas = 0;
      var conflictos = 0;
      var rechazadas = 0;
      for (final lote in enLotes(pendientes, 50)) {
        try {
          final resp = await syncApi.postBatch(
            lote.map(SyncOperationWire.desdeOperacion).toList(),
          );
          // Un resultado ajeno al lote nunca modifica SQLite de otra cuenta.
          final ids = lote.map((op) => op.id).toSet();
          if (resp.results.any((r) => !ids.contains(r.clientRequestId))) {
            await dao.liberarEnvio(ids.toList());
            return false;
          }
          await dao.aplicarResultados(resp.results);
          final recibidas = resp.results
              .map((result) => result.clientRequestId)
              .toSet();
          await dao.liberarEnvio(ids.difference(recibidas).toList());
          confirmadas += resp.confirmed;
          conflictos += resp.conflicts;
          rechazadas += resp.rejected;
          await baseLocal.borrarMeta(claveEspera);
        } on ApiException catch (e) {
          await dao.liberarEnvio(lote.map((op) => op.id).toList());
          if (e.sinConexion || e.statusCode == 429 || e.statusCode == 503) {
            final espera = policy.esperaPara(1, e.retryAfter);
            await baseLocal.guardarMeta(
              claveEspera,
              reloj().add(espera).toIso8601String(),
            );
          }
          return false;
        }
      }
      if (confirmadas > 0 || conflictos > 0) {
        if (notificaciones == null) {
          await _iniciarNotificaciones(pedirPermiso: false);
        }
        await _mostrarNotificacion(
          notifs: notificaciones ?? _notifications,
          titulo: 'Sincronización en segundo plano',
          cuerpo:
              'Operaciones sincronizadas: $confirmadas confirmadas'
              '${conflictos > 0 ? ', $conflictos en conflicto' : ''}'
              '${rechazadas > 0 ? ', $rechazadas rechazadas' : ''}.',
        );
      }
      try {
        final catalogoDao = CatalogoLocalDao(baseLocal);
        final meta = await catalogoDao.meta();
        final instApi = InstantaneaApi(cliente ?? ApiClient());
        final snap = await instApi.obtener(
          sucursalId: meta.sucursalId,
          desde: meta.version,
        );
        if (snap.sucursales.isNotEmpty) {
          final branch = meta.sucursalId ?? snap.sucursales.first.id;
          await catalogoDao.guardar(snap, branch, usuarioId: identidad.id);
        }
      } catch (_) {
        // El fallo al actualizar catálogo en segundo plano no anula la sincronización.
      }
      return true;
    } catch (_) {
      // No hay consumo de intentos ni eliminación de la cola ante un fallo.
      return false;
    } finally {
      cliente?.dio.close(force: true);
      try {
        if (base == null) await baseLocal.cerrar();
      } finally {
        _enviando = false;
      }
    }
  }

  static Future<void> _iniciarNotificaciones({
    required bool pedirPermiso,
  }) async {
    const settings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      ),
    );
    try {
      await _notifications.initialize(settings: settings);
      if (pedirPermiso) {
        await _notifications
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >()
            ?.requestNotificationsPermission();
        await _notifications
            .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin
            >()
            ?.requestPermissions(alert: true, badge: true, sound: true);
      }
    } catch (_) {
      // La denegación de notificaciones no impide sincronizar ni altera la cola.
    }
  }

  static Future<void> _mostrarNotificacion({
    required FlutterLocalNotificationsPlugin notifs,
    required String titulo,
    required String cuerpo,
  }) async {
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        kSincronizacionChannelId,
        kSincronizacionChannelName,
        importance: Importance.defaultImportance,
        priority: Priority.defaultPriority,
      ),
      iOS: DarwinNotificationDetails(),
    );
    try {
      await notifs.show(
        id: 1001,
        title: titulo,
        body: cuerpo,
        notificationDetails: details,
      );
    } catch (_) {
      // La sincronización ya confirmada no se revierte por una notificación.
    }
  }
}
