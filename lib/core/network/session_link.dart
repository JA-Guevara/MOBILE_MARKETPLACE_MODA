/// Acceso diferido a la sesión, sin dependencias circulares entre proveedores.
/// No persiste credenciales ni crea una segunda sesión.
class SessionLink {
  Object? _owner;
  String? Function()? _token;
  String? Function()? _tenant;
  Future<bool> Function()? _refresh;
  void Function()? _expired;

  String? get accessToken => _token?.call();
  String? get tenantSlug => _tenant?.call();
  Future<bool> refresh() async => await _refresh?.call() ?? false;
  void expired() => _expired?.call();

  void bind({
    required Object owner,
    required String? Function() token,
    required String? Function() tenant,
    required Future<bool> Function() refresh,
    required void Function() expired,
  }) {
    _owner = owner;
    _token = token;
    _tenant = tenant;
    _refresh = refresh;
    _expired = expired;
  }

  void unbind(Object owner) {
    if (!identical(owner, _owner)) return;
    _owner = null;
    _token = null;
    _tenant = null;
    _refresh = null;
    _expired = null;
  }
}
