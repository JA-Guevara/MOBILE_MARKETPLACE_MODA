import 'package:flutter/material.dart';

/// Identidad visual compartida con la web.
///
/// Los colores salen de `styles.scss` del frontend (`--accent`, `--ink`,
/// `--paper`, `--line`) para que la app no parezca otro producto. Material 3
/// deriva el resto del esquema desde el acento vino de la web, que ya resuelve
/// estados, contraste y modo oscuro sin listas de colores paralelas.
class AppTheme {
  const AppTheme._();

  // styles.scss: --accent #74394e, --ink #24231f, --paper #faf9f6, --line #e5e2da.
  static const Color _acento = Color(0xFF74394E);
  static const Color _tinta = Color(0xFF24231F);
  static const Color _papel = Color(0xFFFAF9F6);
  static const Color _linea = Color(0xFFE5E2DA);

  static ThemeData get claro => _construir(Brightness.light);
  static ThemeData get oscuro => _construir(Brightness.dark);

  static ThemeData _construir(Brightness brillo) {
    final semilla = ColorScheme.fromSeed(
      seedColor: _acento,
      brightness: brillo,
    );
    final esquema = brillo == Brightness.light
        ? semilla.copyWith(
            primary: _acento,
            onPrimary: const Color(0xFFFFFFFF),
            surface: _papel,
            onSurface: _tinta,
            outline: _linea,
          )
        : semilla;
    final fondo = brillo == Brightness.light ? _papel : esquema.surface;
    return ThemeData(
      useMaterial3: true,
      colorScheme: esquema,
      scaffoldBackgroundColor: fondo,
      appBarTheme: AppBarTheme(
        centerTitle: false,
        backgroundColor: fondo,
        foregroundColor: brillo == Brightness.light ? _tinta : esquema.onSurface,
        elevation: 0,
      ),
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(),
        // Espacio suficiente para que el dedo no toque dos campos a la vez.
        contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(48),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      ),
    );
  }
}

