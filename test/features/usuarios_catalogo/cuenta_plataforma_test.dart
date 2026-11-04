import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_marketplace_moda/app/router.dart';
import 'package:mobile_marketplace_moda/app/theme.dart';
import 'package:mobile_marketplace_moda/core/network/api_client.dart';
import 'package:mobile_marketplace_moda/features/usuarios_catalogo/application/session_controller.dart';
import 'package:mobile_marketplace_moda/features/usuarios_catalogo/domain/usuario.dart';
import 'package:mobile_marketplace_moda/features/usuarios_catalogo/infrastructure/auth_api.dart';
import 'package:mobile_marketplace_moda/features/usuarios_catalogo/presentation/cuenta_plataforma_screen.dart';

import '../../support/backend_falso.dart';

class SesionPrueba extends SessionController {
  SesionPrueba(Usuario? usuario)
      : super(AuthApi(ApiClient()), TokenStoreFalso()) {
    state = EstadoSesion(
      usuario: usuario,
      restaurando: false,
      sinConexion: false,
    );
  }

  bool sesionCerrada = false;

  @override
  Future<void> cerrarSesion() async {
    sesionCerrada = true;
    state = const EstadoSesion(restaurando: false);
  }
}

void main() {
  group('Usuario.esCuentaPlataforma', () {
    test('Usuario sin empresa con tenants.read -> esCuentaPlataforma true', () {
      final u = Usuario(
        id: 'u-admin',
        email: 'admin@fashionstore.test',
        nombre: 'Admin',
        apellido: 'Plataforma',
        permisos: {'tenants.read', 'platform_users.read'},
        empresa: null,
      );

      expect(u.esCuentaPlataforma, isTrue);
    });

    test('Cliente con empresa -> esCuentaPlataforma false', () {
      final u = Usuario(
        id: 'u-cliente',
        email: 'cliente@urbano.test',
        nombre: 'Cliente',
        apellido: 'Urbano',
        permisos: {'tenants.read'},
        empresa: const EmpresaResumen(
          id: 't-urbano',
          nombre: 'Urbano Boutique',
          slug: 'urbano-boutique',
          estado: 'active',
        ),
      );

      expect(u.esCuentaPlataforma, isFalse);
    });

    test('Usuario sin empresa y sin permiso tenants.read -> esCuentaPlataforma false', () {
      final u = Usuario(
        id: 'u-visitante',
        email: 'user@test.com',
        nombre: 'User',
        apellido: 'Test',
        permisos: {'products.read'},
        empresa: null,
      );

      expect(u.esCuentaPlataforma, isFalse);
    });
  });

  group('CuentaPlataformaScreen', () {
    testWidgets('se dibuja con mensajes y botones correspondientes', (tester) async {
      final usuarioAdmin = Usuario(
        id: 'u-admin',
        email: 'admin@fashionstore.test',
        nombre: 'Admin',
        apellido: 'Plataforma',
        permisos: {'tenants.read'},
      );
      final sesion = SesionPrueba(usuarioAdmin);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sessionProvider.overrideWith((ref) => sesion),
          ],
          child: MaterialApp(
            theme: AppTheme.claro,
            home: const CuentaPlataformaScreen(),
          ),
        ),
      );

      expect(find.text('Cuenta de plataforma'), findsWidgets);
      expect(
        find.textContaining('La administración de empresas se hace desde la consola web'),
        findsOneWidget,
      );
      expect(find.text('Abrir consola web'), findsOneWidget);
      expect(find.text('Cerrar sesión'), findsOneWidget);

      await tester.tap(find.text('Cerrar sesión'));
      await tester.pump();
      expect(sesion.sesionCerrada, isTrue);
    });
  });

  group('Router con cuenta de plataforma', () {
    testWidgets('Router con esa sesión -> muestra CuentaPlataformaScreen', (tester) async {
      final usuarioAdmin = Usuario(
        id: 'u-admin',
        email: 'admin@fashionstore.test',
        nombre: 'Admin',
        apellido: 'Plataforma',
        permisos: {'tenants.read'},
      );
      final sesion = SesionPrueba(usuarioAdmin);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sessionProvider.overrideWith((ref) => sesion),
          ],
          child: Consumer(
            builder: (context, ref, _) {
              final router = ref.watch(routerProvider);
              return MaterialApp.router(
                theme: AppTheme.claro,
                routerConfig: router,
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(CuentaPlataformaScreen), findsOneWidget);
      expect(find.text('Cuenta de plataforma'), findsWidgets);
      expect(find.text('Abrir consola web'), findsOneWidget);
    });

    testWidgets('Cliente con empresa -> catálogo normal', (tester) async {
      final clienteConEmpresa = Usuario(
        id: 'u-cliente',
        email: 'cliente@urbano.test',
        nombre: 'Cliente',
        apellido: 'Urbano',
        permisos: {'products.read'},
        empresa: const EmpresaResumen(
          id: 't-urbano',
          nombre: 'Urbano Boutique',
          slug: 'urbano-boutique',
          estado: 'active',
        ),
      );
      final sesion = SesionPrueba(clienteConEmpresa);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sessionProvider.overrideWith((ref) => sesion),
          ],
          child: Consumer(
            builder: (context, ref, _) {
              final router = ref.watch(routerProvider);
              return MaterialApp.router(
                theme: AppTheme.claro,
                routerConfig: router,
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(CuentaPlataformaScreen), findsNothing);
    });
  });
}
