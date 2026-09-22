/// Reglas de contraseña, las mismas que `src/features/usuarios_catalogo/domain/password.ts`
/// de la web: no dependen de Flutter, se prueban sueltas y el backend las
/// vuelve a imponer del lado del servidor.
String? passwordError(String password, {String email = ''}) {
  if (password.length < 12 || password.length > 128) {
    return 'Usá entre 12 y 128 caracteres.';
  }
  final tieneMayuscula = password.contains(RegExp('[A-Z]'));
  final tieneMinuscula = password.contains(RegExp('[a-z]'));
  final tieneNumero = password.contains(RegExp('[0-9]'));
  final tieneSimbolo = password.contains(RegExp('[^a-zA-Z0-9\\s]'));
  if (!tieneMayuscula || !tieneMinuscula || !tieneNumero || !tieneSimbolo) {
    return 'Incluí mayúscula, minúscula, número y símbolo.';
  }
  final local = email.split('@').first.toLowerCase();
  if (local.isNotEmpty && password.toLowerCase().contains(local)) {
    return 'La contraseña no debe contener el nombre de tu correo.';
  }
  return null;
}
