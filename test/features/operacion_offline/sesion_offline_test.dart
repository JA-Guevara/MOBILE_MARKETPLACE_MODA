import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:mobile_marketplace_moda/core/network/api_client.dart';
import 'package:mobile_marketplace_moda/core/network/api_exception.dart';
import 'package:mobile_marketplace_moda/core/offline/base_local.dart';
import 'package:mobile_marketplace_moda/core/storage/token_store.dart';
import 'package:mobile_marketplace_moda/features/usuarios_catalogo/application/session_controller.dart';
import 'package:mobile_marketplace_moda/features/usuarios_catalogo/infrastructure/auth_api.dart';
import 'package:mobile_marketplace_moda/features/usuarios_catalogo/domain/usuario.dart';
import 'fixtures.dart';

class TokensMemoria extends TokenStore {
  String? token;
  @override
  Future<String?> leerRefresh() async => token;
  @override
  Future<void> guardarRefresh(String token) async {
    this.token = token;
  }

  @override
  Future<void> limpiar() async {
    token = null;
  }
}

class AuthFalsa extends AuthApi {
  AuthFalsa() : super(ApiClient());
  Object? fallo;
  Usuario usuario = usuarioOffline();
  Sesion get sesion => Sesion(
    accessToken: 'acceso-prueba-no-real',
    refreshToken: 'renovacion-prueba-no-real',
    usuario: usuario,
  );
  @override
  Future<Sesion> iniciarSesion(String email, String password) async => sesion;
  @override
  Future<Sesion> renovar(String refreshToken) async {
    if (fallo != null) throw fallo!;
    return sesion;
  }

  @override
  Future<Usuario> yo() async => usuario;
  @override
  Future<void> cerrarSesion(String refreshToken) async {}
}

void main() {
  sqfliteFfiInit();
  late BaseLocal base;
  late TokensMemoria tokens;
  late AuthFalsa auth;
  late SessionController control;
  setUp(() {
    base = BaseLocal(fabrica: databaseFactoryFfi, ruta: inMemoryDatabasePath);
    tokens = TokensMemoria();
    auth = AuthFalsa();
    control = SessionController(auth, tokens, baseLocal: base);
  });
  tearDown(() async {
    control.dispose();
    await base.cerrar();
  });
  test('guarda perfil explícito sin credenciales ni tokens', () async {
    await control.iniciarSesion('ana@example.test', 'irrelevante');
    final perfil = (await base.leerMeta('usuario_offline'))!;
    expect(perfil, contains('tenant-a'));
    expect(perfil, isNot(contains('acceso-prueba')));
    expect(perfil, isNot(contains('renovacion-prueba')));
    expect(jsonDecode(perfil), auth.usuario.aJson());
    expect(control.state.autenticado, true);
  });
  test(
    'solo un error de red restaura perfil, sin sesión autenticada',
    () async {
      await control.iniciarSesion('a', 'b');
      control.dispose();
      control = SessionController(auth, tokens, baseLocal: base);
      auth.fallo = const ApiException('Sin red');
      await control.restaurar();
      expect(control.state.usuario!.id, 'u1');
      expect(control.state.sinConexion, true);
      expect(control.state.autenticado, false);
      expect(control.accessToken, isNull);
    },
  );
  test(
    'refresh revocado borra perfil y nunca reabre como usuario offline',
    () async {
      await control.iniciarSesion('a', 'b');
      auth.fallo = const ApiException('Revocado', statusCode: 401);
      await control.restaurar();
      expect(control.state.usuario, isNull);
      expect(await base.leerMeta('usuario_offline'), isNull);
      expect(tokens.token, isNull);
    },
  );
  test(
    'cierre explícito borra perfil; no queda restauración sin red',
    () async {
      await control.iniciarSesion('a', 'b');
      await control.cerrarSesion();
      auth.fallo = const ApiException('Sin red');
      await control.restaurar();
      expect(control.state.usuario, isNull);
      expect(await base.leerMeta('usuario_offline'), isNull);
    },
  );
  test(
    'recargar usuario actualiza plan guardado y cambio de cuenta lo reemplaza',
    () async {
      await control.iniciarSesion('a', 'b');
      auth.usuario = usuarioOffline(estado: 'SUSPENDIDA');
      await control.recargarUsuario();
      expect((await base.leerMeta('usuario_offline'))!, contains('SUSPENDIDA'));
      auth.usuario = usuarioOffline(id: 'u2', tenant: 'tenant-b');
      await control.iniciarSesion('b', 'b');
      final perfil = (await base.leerMeta('usuario_offline'))!;
      expect(perfil, contains('tenant-b'));
      expect(perfil, isNot(contains('tenant-a')));
    },
  );
}
