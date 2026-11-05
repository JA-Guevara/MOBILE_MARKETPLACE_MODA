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
    this.empresa,
    this.suscripcion,
    this.sucursalesAutorizadas = const [],
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
  final EmpresaResumen? empresa;
  final SuscripcionResumen? suscripcion;
  final List<SucursalAutorizada> sucursalesAutorizadas;
  List<ModuloEfectivo> get modulos => suscripcion?.modulos ?? const [];

  /// Lista explícita de campos del perfil: no incluye credenciales.
  Map<String, dynamic> aJson() => {
    'id': id,
    'email': email,
    'first_name': nombre,
    'last_name': apellido,
    'phone': telefono,
    'is_verified': verificado,
    'roles': [
      {'permissions': permisos.toList()},
    ],
    'tenant': empresa?.aJson(),
    'subscription': suscripcion?.aJson(),
    'authorized_branches': sucursalesAutorizadas.map((s) => s.aJson()).toList(),
  };

  String get nombreCompleto => '$nombre $apellido'.trim();

  bool get esCuentaPlataforma =>
      empresa == null && permisos.contains('tenants.read');

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
      empresa: json['tenant'] is Map<String, dynamic>
          ? EmpresaResumen.desdeJson(json['tenant'] as Map<String, dynamic>)
          : null,
      suscripcion: json['subscription'] is Map<String, dynamic>
          ? SuscripcionResumen.desdeJson(
              json['subscription'] as Map<String, dynamic>,
            )
          : null,
      sucursalesAutorizadas:
          (json['authorized_branches'] as List<dynamic>? ?? const [])
              .map(
                (s) => SucursalAutorizada.desdeJson(s as Map<String, dynamic>),
              )
              .toList(),
      permisos: roles
          .expand(
            (rol) =>
                (rol as Map<String, dynamic>)['permissions']
                    as List<dynamic>? ??
                const [],
          )
          .map((permiso) => permiso is Map ? '${permiso['code']}' : '$permiso')
          .toSet(),
    );
  }
}

class SucursalAutorizada {
  const SucursalAutorizada({
    required this.id,
    required this.codigo,
    required this.nombre,
    this.predeterminada = false,
  });
  final String id, codigo, nombre;
  final bool predeterminada;
  factory SucursalAutorizada.desdeJson(Map<String, dynamic> j) =>
      SucursalAutorizada(
        id: '${j['id']}',
        codigo: j['code'] as String,
        nombre: j['name'] as String,
        predeterminada: j['is_default'] == true,
      );
  Map<String, dynamic> aJson() => {
    'id': id,
    'code': codigo,
    'name': nombre,
    'is_default': predeterminada,
  };
}

class EmpresaResumen {
  const EmpresaResumen({
    required this.id,
    required this.slug,
    required this.nombre,
    required this.estado,
  });
  final String id, slug, nombre, estado;
  factory EmpresaResumen.desdeJson(Map<String, dynamic> j) => EmpresaResumen(
    id: '${j['id']}',
    slug: j['slug'] as String,
    nombre: j['trade_name'] as String,
    estado: j['status'] as String,
  );
  Map<String, dynamic> aJson() => {
    'id': id,
    'slug': slug,
    'trade_name': nombre,
    'status': estado,
  };
}

class SuscripcionResumen {
  const SuscripcionResumen({
    required this.codigoPlan,
    required this.nombrePlan,
    required this.estado,
    this.inicio,
    this.fin,
    this.diasRestantes = 0,
    this.funciones = const {},
    this.limites = const {},
    this.modulos = const [],
  });
  final String codigoPlan, nombrePlan, estado;
  final String? inicio, fin;
  final int diasRestantes;
  final Map<String, bool> funciones;
  final Map<String, int> limites;
  final List<ModuloEfectivo> modulos;
  bool get soloLectura => estado != 'ACTIVA';
  bool permite(String codigo) => funciones[codigo] == true;
  factory SuscripcionResumen.desdeJson(Map<String, dynamic> j) =>
      SuscripcionResumen(
        codigoPlan: j['plan_code'] as String,
        nombrePlan: j['plan_name'] as String,
        estado: j['status'] as String,
        inicio: j['start_date'] as String?,
        fin: j['end_date'] as String?,
        diasRestantes: (j['days_left'] as num?)?.toInt() ?? 0,
        funciones: (j['features'] as Map<String, dynamic>? ?? {}).map(
          (k, v) => MapEntry(k, v == true),
        ),
        limites: (j['limits'] as Map<String, dynamic>? ?? {}).map(
          (k, v) => MapEntry(k, (v as num).toInt()),
        ),
        modulos: (j['modules'] as List<dynamic>? ?? const [])
            .map((m) => ModuloEfectivo.desdeJson(m as Map<String, dynamic>))
            .toList(),
      );
  Map<String, dynamic> aJson() => {
    'plan_code': codigoPlan,
    'plan_name': nombrePlan,
    'status': estado,
    'start_date': inicio,
    'end_date': fin,
    'days_left': diasRestantes,
    'features': funciones,
    'limits': limites,
    'modules': modulos.map((m) => m.aJson()).toList(),
  };
}

/// La lista del servidor contiene solo módulos efectivos. `features` sigue
/// siendo la fuente de habilitación; el origen explica plan, extra o prueba.
class ModuloEfectivo {
  const ModuloEfectivo({
    required this.codigo,
    required this.nombre,
    required this.origen,
    this.expira,
  });
  final String codigo, nombre, origen;
  final DateTime? expira;
  bool get enPrueba => origen == 'TRIAL';
  factory ModuloEfectivo.desdeJson(Map<String, dynamic> j) => ModuloEfectivo(
    codigo: j['code'] as String,
    nombre: j['name'] as String? ?? j['code'] as String,
    origen: j['origin'] as String,
    expira: j['expires_at'] == null
        ? null
        : DateTime.parse(j['expires_at'] as String),
  );
  Map<String, dynamic> aJson() => {
    'code': codigo,
    'name': nombre,
    'origin': origen,
    'expires_at': expira?.toUtc().toIso8601String(),
  };
}

/// Par de tokens de una sesión iniciada.
class Sesion {
  const Sesion({
    required this.accessToken,
    required this.refreshToken,
    required this.usuario,
  });

  final String accessToken;
  final String refreshToken;
  final Usuario usuario;

  factory Sesion.desdeJson(Map<String, dynamic> json) => Sesion(
    accessToken: json['access_token'] as String,
    refreshToken: json['refresh_token'] as String,
    usuario: Usuario.desdeJson(json['user'] as Map<String, dynamic>),
  );
}
