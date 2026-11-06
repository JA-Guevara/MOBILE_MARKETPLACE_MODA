import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_marketplace_moda/core/network/api_client.dart';
import 'package:mobile_marketplace_moda/core/offline/sincronizacion_fondo.dart';
import 'package:mobile_marketplace_moda/core/storage/token_store.dart';
import 'package:mobile_marketplace_moda/features/usuarios_catalogo/application/session_controller.dart';
import 'package:mobile_marketplace_moda/features/usuarios_catalogo/domain/usuario.dart';
import 'package:mobile_marketplace_moda/features/usuarios_catalogo/infrastructure/auth_api.dart';
import 'package:mobile_marketplace_moda/main.dart';

class SesionFalsa extends SessionController {
  SesionFalsa() : super(AuthApi(ApiClient()), TokenStore());
  void emitir(EstadoSesion estado) => state = estado;
}

class RegistroFalso implements RegistradorSincronizacion {
  int inicios = 0, registros = 0, cancelaciones = 0;
  @override
  Future<void> inicializar() async => inicios++;
  @override
  Future<void> programar(Duration frecuencia) async => registros++;
  @override
  Future<void> cancelar() async => cancelaciones++;
}

const usuario = Usuario(
  id: 'usuario',
  email: 'operador@example.com',
  nombre: 'Operador',
  apellido: 'Prueba',
  empresa: EmpresaResumen(
    id: 'empresa',
    slug: 'tienda',
    nombre: 'Tienda',
    estado: 'ACTIVA',
  ),
);

void main() {
  testWidgets('solo inicia tras sesión remota y cancela al salir', (
    tester,
  ) async {
    final sesion = SesionFalsa();
    final registro = RegistroFalso();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [sessionProvider.overrideWith((ref) => sesion)],
        child: InicioSincronizacion(
          registrador: registro,
          child: const SizedBox(),
        ),
      ),
    );
    sesion.emitir(const EstadoSesion(restaurando: false));
    await tester.pumpAndSettle();
    expect(registro.registros, 0);
    sesion.emitir(
      const EstadoSesion(
        usuario: usuario,
        restaurando: false,
        sinConexion: true,
      ),
    );
    await tester.pumpAndSettle();
    expect(registro.registros, 0); // Un perfil local no acredita sesión remota.
    sesion.emitir(const EstadoSesion(usuario: usuario, restaurando: false));
    await tester.pumpAndSettle();
    expect(registro.inicios, 1);
    expect(registro.registros, 1);
    sesion.emitir(
      const EstadoSesion(
        usuario: usuario,
        restaurando: false,
        lifecycleState: 'expiring',
      ),
    );
    await tester.pumpAndSettle();
    expect(registro.registros, 1);
    sesion.emitir(const EstadoSesion(restaurando: false));
    await tester.pumpAndSettle();
    expect(registro.cancelaciones, 2); // Visitante inicial y logout.
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  testWidgets('el arranque de escritorio no llama a plugins móviles', (
    tester,
  ) async {
    final sesion = SesionFalsa();
    final registro = RegistroFalso();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [sessionProvider.overrideWith((ref) => sesion)],
        child: InicioSincronizacion(
          registrador: registro,
          child: const SizedBox(),
        ),
      ),
    );
    sesion.emitir(const EstadoSesion(usuario: usuario, restaurando: false));
    await tester.pumpAndSettle();
    expect(registro.inicios, 0);
    expect(registro.registros, 0);
    expect(registro.cancelaciones, 0);
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));
}
