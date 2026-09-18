import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/application/session_controller.dart';
import '../features/auth/presentation/account_screen.dart';
import '../features/auth/presentation/cambiar_contrasena_screen.dart';
import '../features/auth/presentation/login_screen.dart';
import '../features/auth/presentation/recuperar_contrasena_screen.dart';
import '../features/auth/presentation/register_screen.dart';
import '../features/auth/presentation/verificar_correo_screen.dart';
import '../features/usuarios_catalogo/presentation/catalog_screen.dart';
import '../shared/widgets/pantalla_pendiente.dart';
import 'home_shell.dart';

/// Rutas de la aplicación, con los mismos nombres que la web.
///
/// Mantener las rutas en español y con la misma forma que el frontend web
/// (`/prendas/:slug`, `/mi-cuenta/pedidos`) no es cosmético: los correos que
/// manda el backend enlazan a esas direcciones, así que más adelante un enlace
/// profundo puede abrir la app en el mismo lugar sin inventar un mapa aparte.
///
/// **La administración no está acá.** El panel de gestión (pedidos, caja,
/// stock, devoluciones, bitácora, reportes) sigue siendo web: es trabajo de
/// escritorio, con tablas y formularios largos. La app es para el cliente.

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
      final exigeSesion = _rutasPrivadas.any(destino.startsWith);
      if (exigeSesion && !sesion.autenticado) {
        return '/iniciar-sesion?volverA=${Uri.encodeComponent(destino)}';
      }
      return null;
    },
    routes: [
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
        builder: (context, estado) => PantallaPendiente(
          titulo: 'Prenda',
          descripcion:
              'Detalle de "${estado.pathParameters['slug']}": fotos, tallas, colores, '
              'disponibilidad por sucursal y botón de probador.',
          endpoints: [
            'GET /catalog/products/{slug}',
            'GET /commerce/branches',
            'PUT /commerce/cart/items/{variant_id}',
          ],
        ),
      ),
      GoRoute(
        path: '/prendas/:slug/vestidor',
        parentNavigatorKey: _raiz,
        builder: (context, estado) => const PantallaPendiente(
          titulo: 'Probador virtual',
          descripcion:
              'Cámara en vivo con detección de pose en el dispositivo y la prenda '
              'dibujada sobre el cuerpo (RF13). Es el equivalente nativo de lo que '
              'en la web hace MediaPipe: acá lo resuelve google_mlkit_pose_detection.',
          endpoints: [
            'POST /vestidor/sessions',
            'GET /catalog/products/{slug}',
          ],
        ),
      ),
      GoRoute(
        path: '/reservar',
        parentNavigatorKey: _raiz,
        builder: (context, estado) => const PantallaPendiente(
          titulo: 'Agendar visita',
          descripcion: 'Elegir sucursal, horario y prendas para probarse (RF09, RF10).',
          endpoints: [
            'GET /reservations/availability',
            'POST /reservations',
          ],
        ),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, estado, navegacion) => HomeShell(navegacion: navegacion),
        branches: [
          StatefulShellBranch(
            navigatorKey: _catalogo,
            routes: [
              GoRoute(
                path: '/',
                builder: (context, estado) => const CatalogScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            navigatorKey: _carrito,
            routes: [
              GoRoute(
                path: '/carrito',
                builder: (context, estado) => const PantallaPendiente(
                  titulo: 'Carrito',
                  descripcion:
                      'Prendas elegidas, sucursal de retiro, dirección de entrega y '
                      'pago (RF14, RF16). El checkout de Stripe se abre en el '
                      'navegador y al volver la app concilia el pago.',
                  endpoints: [
                    'GET /commerce/cart',
                    'POST /commerce/orders',
                    'POST /commerce/orders/{id}/checkout',
                    'POST /commerce/orders/{id}/payment-status',
                  ],
                ),
              ),
            ],
          ),
          StatefulShellBranch(
            navigatorKey: _reservas,
            routes: [
              GoRoute(
                path: '/mi-cuenta/reservas',
                builder: (context, estado) => const PantallaPendiente(
                  titulo: 'Mis reservas',
                  descripcion: 'Visitas agendadas y su estado (RF12).',
                  endpoints: [
                    'GET /reservations',
                    'POST /reservations/{id}/cancel',
                  ],
                ),
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
                    builder: (context, estado) => const PantallaPendiente(
                      titulo: 'Mis pedidos',
                      descripcion:
                          'Seguimiento del pedido etapa por etapa y solicitud de '
                          'devolución de prendas entregadas (CU19).',
                      endpoints: [
                        'GET /commerce/orders',
                        'GET /commerce/orders/{id}/returns',
                        'POST /commerce/orders/{id}/returns',
                      ],
                    ),
                  ),
                  GoRoute(
                    path: 'reservas',
                    builder: (context, estado) => const PantallaPendiente(
                      titulo: 'Mis reservas',
                      descripcion: 'Visitas agendadas y su estado (RF12).',
                      endpoints: [
                        'GET /reservations',
                        'POST /reservations/{id}/cancel',
                      ],
                    ),
                  ),
                  GoRoute(
                    path: 'direcciones',
                    builder: (context, estado) => const PantallaPendiente(
                      titulo: 'Mis direcciones',
                      descripcion:
                          'Direcciones guardadas para no volver a escribirlas en cada compra.',
                      endpoints: [
                        'GET /users/me/addresses',
                        'POST /users/me/addresses',
                        'PATCH /users/me/addresses/{id}',
                      ],
                    ),
                  ),
                  GoRoute(
                    path: 'seguridad',
                    builder: (context, estado) => const CambiarContrasenaScreen(),
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
const _rutasPrivadas = ['/mi-cuenta', '/carrito', '/reservar'];
