/// Dónde vive el backend, según cómo se compile la aplicación.
///
/// Equivale a `src/environments/` del frontend web, pero sin reemplazo de
/// archivos: el valor entra por `--dart-define`, así un mismo código sirve para
/// el backend local y para el de Railway.
///
/// Ejemplos:
///   flutter run   // usa el por defecto (backend de producción)
///   flutter run --dart-define=API_URL=http://10.0.2.2:8000/api/v1  // backend local
///   flutter run --dart-define-from-file=.env                       // lo que diga el .env
class Environment {
  const Environment._();

  /// Backend por defecto: el de producción. Para probar contra el backend
  /// local, pasar `--dart-define=API_URL=http://10.0.2.2:8000/api/v1` (emulador)
  /// o el IP de la máquina (teléfono físico).
  static const String apiUrl = String.fromEnvironment(
    'API_URL',
    defaultValue: 'https://backendmarketplacemoda-production.up.railway.app/api/v1',
  );

  /// El checkout de Stripe vuelve a las páginas del frontend web, así que la
  /// app necesita saber cuál es para reconocer el retorno.
  static const String webUrl = String.fromEnvironment(
    'WEB_URL',
    defaultValue: 'https://frontendmarketplacemoda-production.up.railway.app',
  );

  static bool get isProduction =>
      apiUrl.startsWith('https://') && !apiUrl.contains('localhost');
}

