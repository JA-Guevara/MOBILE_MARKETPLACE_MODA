import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'core/offline/sincronizacion_fondo.dart';
import 'features/usuarios_catalogo/application/session_controller.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    const ProviderScope(child: InicioSincronizacion(child: FashionStoreApp())),
  );
}

class InicioSincronizacion extends ConsumerStatefulWidget {
  const InicioSincronizacion({
    super.key,
    required this.child,
    this.registrador,
  });
  final Widget child;
  final RegistradorSincronizacion? registrador;

  @override
  ConsumerState<InicioSincronizacion> createState() =>
      InicioSincronizacionState();
}

class InicioSincronizacionState extends ConsumerState<InicioSincronizacion> {
  ProviderSubscription<EstadoSesion>? _sesion;
  String? _identidad;
  bool _observada = false;
  Future<void> _actualizacion = Future.value();

  @override
  void initState() {
    super.initState();
    if (kIsWeb ||
        !{
          TargetPlatform.android,
          TargetPlatform.iOS,
        }.contains(defaultTargetPlatform)) {
      return;
    }
    _sesion = ref.listenManual(sessionProvider, (_, actual) {
      if (actual.restaurando) return;
      final tenant = actual.usuario?.empresa;
      final identidad =
          actual.autenticado &&
              !actual.soloLectura &&
              tenant?.estado == 'ACTIVA'
          ? '${tenant!.id}:${actual.usuario!.id}'
          : null;
      if (_observada && identidad == _identidad) return;
      _observada = true;
      _identidad = identidad;
      // Serializar login/logout evita dejar un registro tardío tras salir.
      _actualizacion = _actualizacion
          .then((_) async {
            if (!mounted || identidad != _identidad) return;
            if (identidad == null) {
              await SincronizacionFondo.cancelar(
                registrador: widget.registrador,
              );
            } else {
              await SincronizacionFondo.inicializar(
                registrador: widget.registrador,
              );
              if (mounted && identidad == _identidad) {
                await SincronizacionFondo.programar();
              }
            }
          })
          .catchError((Object _) {
            debugPrint(
              'No se pudo registrar la sincronización en segundo plano. La cola local se conserva.',
            );
          });
    }, fireImmediately: true);
  }

  @override
  void dispose() {
    _sesion?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
