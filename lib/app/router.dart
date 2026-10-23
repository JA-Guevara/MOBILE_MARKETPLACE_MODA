import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/usuarios_catalogo/application/session_controller.dart';
import '../features/usuarios_catalogo/presentation/account_screen.dart';
import '../features/usuarios_catalogo/presentation/cambiar_contrasena_screen.dart';
import '../features/usuarios_catalogo/presentation/login_screen.dart';
import '../features/usuarios_catalogo/presentation/prenda_screen.dart';
import '../features/ventas_pagos/presentation/carrito_screen.dart';
import '../features/ventas_pagos/presentation/pedido_detalle_screen.dart';
import '../features/ventas_pagos/presentation/pedidos_screen.dart';
import '../features/ventas_pagos/presentation/favoritos_screen.dart';
import '../features/ventas_pagos/presentation/sucursales_screen.dart';
import '../features/usuarios_catalogo/presentation/direcciones_screen.dart';
import '../features/usuarios_catalogo/presentation/recuperar_contrasena_screen.dart';
import '../features/usuarios_catalogo/presentation/register_screen.dart';
import '../features/usuarios_catalogo/presentation/verificar_correo_screen.dart';
import '../features/usuarios_catalogo/presentation/catalog_screen.dart';
import '../features/reservas_vestidor/presentation/vestidor_screen.dart';
import '../features/reservas_vestidor/presentation/mis_reservas_screen.dart';
import '../features/reservas_vestidor/presentation/nueva_reserva_screen.dart';
import 'home_shell.dart';
import '../features/operacion_offline/presentation/catalogo_adaptable.dart';
import '../features/operacion_offline/presentation/preparar_offline_screen.dart';
import '../features/operacion_offline/presentation/catalogo_offline_screen.dart';
import '../features/operacion_offline/presentation/reserva_offline_screen.dart';
import '../features/operacion_offline/presentation/reservas_locales_screen.dart';
import '../features/operacion_offline/presentation/comprobante_reserva_screen.dart';

/// Rutas de la aplicación, con los mismos nombres que la web.
///
/// Mantener las rutas en español y con la misma forma que el frontend web
/// (`/prendas/:slug`, `/mi-cuenta/pedidos`) no es cosmético: los correos que
/// manda el backend enlazan a esas direcciones, así que más adelante un enlace
/// profundo puede abrir la app en el mismo lugar sin inventar un mapa aparte.
///
/// El flujo de cliente está completo: catálogo, detalle, carrito, pedidos,
/// devoluciones, favoritos, direcciones, sucursales, reservas y probador.
/// La administración se suma aparte y filtrada por permisos.

final _raiz = GlobalKey<NavigatorState>();
final _catalogo = GlobalKey<NavigatorState>();
final _carrito = GlobalKey<NavigatorState>();
final _reservas = GlobalKey<NavigatorState>();
final _cuenta = GlobalKey<NavigatorState>();

final routerProvider = Provider<GoRouter>((ref) {
  // GoRouter solo vuelve a evaluar `redirect` cuando algo se lo avisa. Este
  // puente hace que cerrar sesión (o que venza el refresh) saque al usuario de
  // una pantalla privada en el momento, sin esperar a la próxima navegación.
  final cambios = ValueNotifier<int>(0);
  ref.listen(sessionProvider, (_, __) => cambios.value++);
  ref.onDispose(cambios.dispose);

  return GoRouter(
    navigatorKey: _raiz,
    initialLocation: '/',
    refreshListenable: cambios,
    redirect: (context, estado) {
      final sesion = ref.read(sessionProvider);
      // Mientras se restaura la sesión guardada no se decide nada: mandar a
      // login en ese instante haría parpadear la pantalla en cada arranque.
      if (sesion.restaurando) return null;
      final destino = estado.matchedLocation;
      // El espejo en vivo es público, igual que en la web; una cuenta se pide
      // recién para guardar una foto IA o consultar información personal.
      final exigeSesion = _rutasPrivadas.any(destino.startsWith);
      if (exigeSesion && !sesion.autenticado) {
        return '/iniciar-sesion?volverA=${Uri.encodeComponent(destino)}';
      }
      return null;
    },
    routes: [
      GoRoute(
        path: '/sin-conexion',
        parentNavigatorKey: _raiz,
        builder: (context, estado) => const PrepararOfflineScreen(),
      ),
      GoRoute(
        path: '/sin-conexion/catalogo',
        parentNavigatorKey: _raiz,
        builder: (context, estado) => const CatalogoOfflineScreen(),
      ),
      GoRoute(
        path: '/sin-conexion/reservar',
        parentNavigatorKey: _raiz,
        builder: (context, estado) => const ReservaOfflineScreen(),
      ),
      GoRoute(
        path: '/sin-conexion/reservas',
        parentNavigatorKey: _raiz,
        builder: (context, estado) => const ReservasLocalesScreen(),
      ),
      GoRoute(
        path: '/sin-conexion/reservas/:id',
        parentNavigatorKey: _raiz,
        builder: (context, estado) =>
            ComprobanteReservaScreen(id: estado.pathParameters['id']!),
      ),
      GoRoute(
        path: '/iniciar-sesion',
        builder: (context, estado) =>
            LoginScreen(volverA: estado.uri.queryParameters['volverA']),
      ),
      GoRoute(
        path: '/registrarse',
        builder: (context, estado) => const RegisterScreen(),
      ),
      GoRoute(
        path: '/recuperar-contrasena',
        builder: (context, estado) => RecuperarContrasenaScreen(
          token: estado.uri.queryParameters['token'] ?? '',
        ),
      ),
      GoRoute(
        path: '/verificar-correo',
        builder: (context, estado) => VerificarCorreoScreen(
          token: estado.uri.queryParameters['token'] ?? '',
          email: estado.uri.queryParameters['email'] ?? '',
        ),
      ),
      GoRoute(
        path: '/reenviar-verificacion',
        builder: (context, estado) => VerificarCorreoScreen(
          email: estado.uri.queryParameters['email'] ?? '',
        ),
      ),
      // Igual que la web: la contraseña se cambia desde el espacio personal.
      GoRoute(
        path: '/cambiar-contrasena',
        redirect: (context, estado) => '/mi-cuenta/seguridad',
      ),
      // Detalle y probador salen del shell: ocupan la pantalla entera.
      GoRoute(
        path: '/prendas/:slug',
        parentNavigatorKey: _raiz,
        builder: (context, estado) => PrendaScreen(
          slug: estado.pathParameters['slug'] ?? '',
          paraReserva: estado.uri.queryParameters['paraReserva'] == '1',
        ),
      ),
      GoRoute(
        path: '/sucursales',
        parentNavigatorKey: _raiz,
        builder: (context, estado) => const SucursalesScreen(),
      ),
      GoRoute(
        path: '/prendas/:slug/vestidor',
        parentNavigatorKey: _raiz,
        builder: (context, estado) => VestidorScreen(
          slug: estado.pathParameters['slug'] ?? '',
          colorId: estado.uri.queryParameters['color'],
        ),
      ),
      GoRoute(
        path: '/reservar',
        parentNavigatorKey: _raiz,
        builder: (context, estado) => const NuevaReservaScreen(),
      ),
      GoRoute(
        path: '/elegir-prendas',
        parentNavigatorKey: _raiz,
        builder: (context, estado) => const CatalogScreen(paraReserva: true),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, estado, navegacion) =>
            HomeShell(navegacion: navegacion),
        branches: [
          StatefulShellBranch(
            navigatorKey: _catalogo,
            routes: [
              GoRoute(
                path: '/',
                builder: (context, estado) => const CatalogoAdaptable(),
              ),
            ],
          ),
          StatefulShellBranch(
            navigatorKey: _carrito,
            routes: [
              GoRoute(
                path: '/carrito',
                builder: (context, estado) => const CarritoScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            navigatorKey: _reservas,
            routes: [
              GoRoute(
                path: '/mi-cuenta/reservas',
                builder: (context, estado) => const MisReservasScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            navigatorKey: _cuenta,
            routes: [
              GoRoute(
                path: '/mi-cuenta',
                builder: (context, estado) => const AccountScreen(),
                routes: [
                  GoRoute(
                    path: 'pedidos',
                    builder: (context, estado) => const PedidosScreen(),
                    routes: [
                      GoRoute(
                        path: ':id',
                        builder: (context, estado) => PedidoDetalleScreen(
                          id: estado.pathParameters['id'] ?? '',
                        ),
                      ),
                    ],
                  ),

                  GoRoute(
                    path: 'direcciones',
                    builder: (context, estado) => const DireccionesScreen(),
                  ),
                  GoRoute(
                    path: 'favoritos',
                    builder: (context, estado) => const FavoritosScreen(),
                  ),
                  GoRoute(
                    path: 'seguridad',
                    builder: (context, estado) =>
                        const CambiarContrasenaScreen(),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    ],
  );
});

/// Rutas que no tienen sentido sin sesión iniciada.
const _rutasPrivadas = [
  '/mi-cuenta',
  '/carrito',
  '/reservar',
  '/elegir-prendas',
];
