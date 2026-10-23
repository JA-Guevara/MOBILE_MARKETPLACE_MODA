import '../../usuarios_catalogo/domain/producto.dart';

/// La variante elegida en catálogo gobierna el recurso y el color de la guía.
/// Si el enlace no indica color, se elige una variante activa con identificador
/// para que la sesión del backend corresponda a ese mismo color.
Variante? varianteParaProbador(Producto producto, String? colorId) {
  final disponibles = producto.variantesDisponibles;
  if (colorId != null && colorId.isNotEmpty) {
    for (final variante in disponibles) {
      if (variante.colorId == colorId) return variante;
    }
    return null;
  }
  for (final variante in disponibles) {
    if (variante.colorId != null && variante.colorId!.isNotEmpty) {
      return variante;
    }
  }
  return disponibles.isEmpty ? null : disponibles.first;
}

/// Sin hexadecimal confiable no se inventa el color de una foto: la silueta
/// de respaldo se muestra gris y el nombre de catálogo sigue visible.
bool tieneColorHexValido(Variante? variante) {
  final hex = variante?.hexColor?.trim() ?? '';
  return RegExp(r'^#(?:[0-9a-fA-F]{3}|[0-9a-fA-F]{6})$').hasMatch(hex);
}

String colorGuiaDeVariante(Variante? variante) =>
    tieneColorHexValido(variante) ? variante!.hexColor!.trim() : '#888888';
