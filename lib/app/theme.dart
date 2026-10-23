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
      extensions: [
        brillo == Brightness.light ? ColoresEstado.claro : ColoresEstado.oscuro,
      ],
      colorScheme: esquema,
      scaffoldBackgroundColor: fondo,
      appBarTheme: AppBarTheme(
        centerTitle: false,
        backgroundColor: fondo,
        foregroundColor: brillo == Brightness.light
            ? _tinta
            : esquema.onSurface,
        elevation: 0,
      ),
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(),
        // Espacio suficiente para que el dedo no toque dos campos a la vez.
        contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          // Alto suficiente para el dedo, pero **sin** fijar el ancho: un
          // `Size.fromHeight` pide ancho infinito y revienta el layout apenas
          // el boton cae en un contexto sin ancho definido (una `Row`, una
          // lista horizontal). En las pantallas de formulario el boton ya es
          // hijo directo de un `ListView`, que le da el ancho completo.
          minimumSize: const Size(64, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
    );
  }
}

@immutable
class ColoresEstado extends ThemeExtension<ColoresEstado> {
  const ColoresEstado({
    required this.exito,
    required this.advertencia,
    required this.peligro,
    required this.info,
    required this.fondoExito,
    required this.fondoAdvertencia,
    required this.fondoPeligro,
    required this.fondoInfo,
  });
  final Color exito,
      advertencia,
      peligro,
      info,
      fondoExito,
      fondoAdvertencia,
      fondoPeligro,
      fondoInfo;
  static const claro = ColoresEstado(
    exito: Color(0xFF2F7D55),
    advertencia: Color(0xFFA86A12),
    peligro: Color(0xFFA7352D),
    info: Color(0xFF2F5F8A),
    fondoExito: Color(0xFFE4F1EA),
    fondoAdvertencia: Color(0xFFFBF0DC),
    fondoPeligro: Color(0xFFF9E4E1),
    fondoInfo: Color(0xFFE2EDF7),
  );
  static const oscuro = ColoresEstado(
    exito: Color(0xFF86D5A8),
    advertencia: Color(0xFFF0C577),
    peligro: Color(0xFFF3A59D),
    info: Color(0xFF9EC7EF),
    fondoExito: Color(0xFF173B28),
    fondoAdvertencia: Color(0xFF463514),
    fondoPeligro: Color(0xFF482522),
    fondoInfo: Color(0xFF1D3449),
  );
  @override
  ColoresEstado copyWith({
    Color? exito,
    Color? advertencia,
    Color? peligro,
    Color? info,
    Color? fondoExito,
    Color? fondoAdvertencia,
    Color? fondoPeligro,
    Color? fondoInfo,
  }) => ColoresEstado(
    exito: exito ?? this.exito,
    advertencia: advertencia ?? this.advertencia,
    peligro: peligro ?? this.peligro,
    info: info ?? this.info,
    fondoExito: fondoExito ?? this.fondoExito,
    fondoAdvertencia: fondoAdvertencia ?? this.fondoAdvertencia,
    fondoPeligro: fondoPeligro ?? this.fondoPeligro,
    fondoInfo: fondoInfo ?? this.fondoInfo,
  );
  @override
  ColoresEstado lerp(covariant ColoresEstado? other, double t) {
    if (other == null) return this;
    return ColoresEstado(
      exito: Color.lerp(exito, other.exito, t)!,
      advertencia: Color.lerp(advertencia, other.advertencia, t)!,
      peligro: Color.lerp(peligro, other.peligro, t)!,
      info: Color.lerp(info, other.info, t)!,
      fondoExito: Color.lerp(fondoExito, other.fondoExito, t)!,
      fondoAdvertencia: Color.lerp(
        fondoAdvertencia,
        other.fondoAdvertencia,
        t,
      )!,
      fondoPeligro: Color.lerp(fondoPeligro, other.fondoPeligro, t)!,
      fondoInfo: Color.lerp(fondoInfo, other.fondoInfo, t)!,
    );
  }
}
