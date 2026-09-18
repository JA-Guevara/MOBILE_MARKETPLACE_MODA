/// Usuario autenticado, tal como lo devuelve `/auth/me` y `/auth/login`.
class Usuario {
  const Usuario({
    required this.id,
    required this.email,
    required this.nombre,
    required this.apellido,
    this.telefono,
    this.verificado = false,
    this.permisos = const <String>{},
  });

  final String id;
  final String email;
  final String nombre;
  final String apellido;
  final String? telefono;
  final bool verificado;

  /// Permisos efectivos, aplanados desde los roles. La app de cliente casi no
  /// los usa —la administración vive en la web—, pero sirven para ocultar lo
  /// que el servidor va a rechazar igual.
  final Set<String> permisos;

  String get nombreCompleto => '$nombre $apellido'.trim();

  bool puede(String permiso) => permisos.contains(permiso);

  factory Usuario.desdeJson(Map<String, dynamic> json) {
    final roles = json['roles'] as List<dynamic>? ?? const [];
    return Usuario(
      id: '${json['id']}',
      email: json['email'] as String? ?? '',
      nombre: json['first_name'] as String? ?? '',
      apellido: json['last_name'] as String? ?? '',
      telefono: json['phone'] as String?,
      verificado: json['is_verified'] as bool? ?? false,
      permisos: roles
          .expand((rol) => (rol as Map<String, dynamic>)['permissions'] as List<dynamic>? ?? const [])
          .map((permiso) => permiso is Map ? '${permiso['code']}' : '$permiso')
          .toSet(),
    );
  }
}

/// Par de tokens de una sesión iniciada.
class Sesion {
  const Sesion({required this.accessToken, required this.refreshToken, required this.usuario});

  final String accessToken;
  final String refreshToken;
  final Usuario usuario;

  factory Sesion.desdeJson(Map<String, dynamic> json) => Sesion(
        accessToken: json['access_token'] as String,
        refreshToken: json['refresh_token'] as String,
        usuario: Usuario.desdeJson(json['user'] as Map<String, dynamic>),
      );
}
