// Ubicación automática de la prenda sobre el cuerpo.
//
// Port de `garment-fit.ts` de la web a Dart. El recurso preparado trae puntos
// de anclaje ("esta parte de la imagen es el hombro") y la región del cuerpo
// que cubre; la detección de pose aporta los puntos corporales. Este módulo
// empareja unos con otros y calcula posición, escala e inclinación, de modo
// que el cliente no tenga que acomodar la prenda a mano. Funciones puras.
import 'dart:math' as math;

import 'pose_projection.dart';

/// Región del cuerpo que cubre una prenda.
enum RegionCuerpo { superior, inferior, cuerpoEntero, pies }

const int _hombroIzquierdo = 11;
const int _hombroDerecho = 12;
const int _caderaIzquierda = 23;
const int _caderaDerecha = 24;
const int _tobilloIzquierdo = 27;
const int _tobilloDerecho = 28;

/// Anclajes del recurso: nombre → [x, y] normalizados dentro de la imagen.
typedef AnclajesPrenda = Map<String, List<double>?>;

/// Regla de cada región: qué par de landmarks la gobierna, qué anclajes usa y
/// cuánto más ancha dibujar la prenda que la línea de esqueleto.
class _Regla {
  const _Regla(this.izquierdo, this.derecho, this.anclajes, this.holgura, this.parte);

  final int izquierdo;
  final int derecho;
  final List<String> anclajes;
  final double holgura;
  final String parte;
}

const Map<RegionCuerpo, _Regla> _reglas = {
  RegionCuerpo.superior: _Regla(_hombroIzquierdo, _hombroDerecho, ['shoulder', 'chest'], 1.35, 'los hombros'),
  RegionCuerpo.inferior: _Regla(_caderaIzquierda, _caderaDerecha, ['waist', 'hip'], 1.3, 'la cadera'),
  RegionCuerpo.cuerpoEntero: _Regla(_hombroIzquierdo, _hombroDerecho, ['shoulder', 'waist'], 1.35, 'los hombros'),
  RegionCuerpo.pies: _Regla(_tobilloIzquierdo, _tobilloDerecho, ['top', 'hem'], 1.6, 'los pies'),
};

/// Proporción del ancho del escenario que debería ocupar la línea corporal.
/// Fuera de este rango se le pide a la persona que se acerque o se aleje.
const double _minimoEncuadre = 0.1;
const double _maximoEncuadre = 0.6;

/// Inclinación (radianes) a partir de la cual conviene pedir que se enderece.
const double _maximaInclinacion = 0.38;

/// Qué decirle a la persona en cada situación de la cámara.
enum CodigoGuia { ok, sinCamara, sinPersona, parcial, lejos, cerca, inclinado }

/// Acceso a un landmark con verificación de rango.
Landmark? _lm(List<Landmark> landmarks, int i) =>
    (i >= 0 && i < landmarks.length) ? landmarks[i] : null;

class Guia {
  const Guia({required this.codigo, required this.mensaje, required this.ok});

  final CodigoGuia codigo;
  final String mensaje;

  /// true cuando la prenda puede mostrarse ubicada.
  final bool ok;
}

/// Ajuste de la prenda sobre el escenario: desplazamiento del centro, rotación
/// en radianes y escala relativa al tamaño de la imagen.
class AjustePrenda {
  const AjustePrenda({
    required this.offsetX,
    required this.offsetY,
    required this.rotation,
    required this.scale,
  });

  final double offsetX;
  final double offsetY;
  final double rotation;
  final double scale;
}

/// Interpreta el valor de región que llega del backend (`upper_body`…).
RegionCuerpo? regionDesdeNombre(String? valor) {
  switch (valor) {
    case 'upper_body':
      return RegionCuerpo.superior;
    case 'lower_body':
      return RegionCuerpo.inferior;
    case 'full_body':
      return RegionCuerpo.cuerpoEntero;
    case 'feet':
      return RegionCuerpo.pies;
    default:
      return null;
  }
}

/// Par de anclajes utilizable para la región, en orden de preferencia.
({List<double> izquierda, List<double> derecha})? anclajeDeRegion(
  AnclajesPrenda? anclajes,
  RegionCuerpo region,
) {
  if (anclajes == null) return null;
  for (final nombre in _reglas[region]!.anclajes) {
    final izquierda = anclajes['${nombre}_left'];
    final derecha = anclajes['${nombre}_right'];
    if (izquierda != null &&
        derecha != null &&
        izquierda.length == 2 &&
        derecha.length == 2 &&
        derecha[0] - izquierda[0] > 0.02) {
      return (izquierda: izquierda, derecha: derecha);
    }
  }
  return null;
}

/// Línea corporal (en píxeles del escenario) que gobierna la región.
({double midX, double midY, double spanPx, double rotation})? lineaCorporal(
  List<Landmark> landmarks,
  RegionCuerpo region,
  CajaVideo caja,
) {
  final regla = _reglas[region]!;
  final izquierdo = _lm(landmarks, regla.izquierdo);
  final derecho = _lm(landmarks, regla.derecho);
  if (izquierdo == null || derecho == null) return null;
  if (!enRango(izquierdo) || !enRango(derecho)) return null;
  final proyectados = <({double px, double py})>[
    videoAPantalla(izquierdo.x, izquierdo.y, caja),
    videoAPantalla(derecho.x, derecho.y, caja),
  ];
  // Se ordenan por posición en pantalla: con la cámara frontal la imagen va
  // espejada y los puntos se invierten, lo que daba una rotación de 180° y
  // dibujaba la prenda cabeza abajo.
  proyectados.sort((a, b) => a.px.compareTo(b.px));
  final a = proyectados[0];
  final b = proyectados[1];
  final spanPx = _hipot(b.px - a.px, b.py - a.py);
  if (spanPx < 1) return null;
  return (
    midX: (a.px + b.px) / 2,
    midY: (a.py + b.py) / 2,
    spanPx: spanPx,
    rotation: math.atan2(b.py - a.py, b.px - a.px),
  );
}

/// Revisa la postura y devuelve qué decirle a la persona.
Guia evaluarPostura(
  List<Landmark>? landmarks,
  RegionCuerpo region,
  CajaVideo caja,
) {
  if (landmarks == null || landmarks.isEmpty) {
    return const Guia(
      codigo: CodigoGuia.sinPersona,
      mensaje: 'Ponete frente a la cámara, de cuerpo entero.',
      ok: false,
    );
  }
  final linea = lineaCorporal(landmarks, region, caja);
  if (linea == null) {
    return Guia(
      codigo: CodigoGuia.parcial,
      mensaje: 'Acomodate para que se vean ${_reglas[region]!.parte}.',
      ok: false,
    );
  }
  // Para una prenda de cuerpo entero hace falta ver también la cadera.
  if (region == RegionCuerpo.cuerpoEntero &&
      !(enRango(_lm(landmarks, _caderaIzquierda)) &&
          enRango(_lm(landmarks, _caderaDerecha)))) {
    return const Guia(
      codigo: CodigoGuia.parcial,
      mensaje: 'Alejate un poco: necesito verte de la cabeza a la cadera.',
      ok: false,
    );
  }
  final proporcion = linea.spanPx / math.max(1, caja.escenarioAncho);
  if (proporcion < _minimoEncuadre) {
    return const Guia(
      codigo: CodigoGuia.lejos,
      mensaje: 'Acercate un poco a la cámara.',
      ok: false,
    );
  }
  if (proporcion > _maximoEncuadre) {
    return const Guia(
      codigo: CodigoGuia.cerca,
      mensaje: 'Alejate un poco para verte completo.',
      ok: false,
    );
  }
  if (linea.rotation.abs() > _maximaInclinacion) {
    return const Guia(
      codigo: CodigoGuia.inclinado,
      mensaje: 'Ponete derecho y de frente.',
      ok: false,
    );
  }
  return const Guia(
    codigo: CodigoGuia.ok,
    mensaje: 'Listo: movete y la prenda te sigue.',
    ok: true,
  );
}

/// Tamaño de la imagen de la prenda que se va a pintar.
typedef ImagenPrenda = ({double ancho, double alto});

/// Coloca la prenda sobre el cuerpo.
///
/// La imagen se dibuja centrada en el escenario, así que se calcula cuánto
/// desplazarla para que su línea de anclaje caiga sobre la línea corporal, con
/// la escala que iguala ambos anchos y la misma inclinación.
AjustePrenda? calcularAjuste(
  List<Landmark> landmarks,
  RegionCuerpo region,
  AnclajesPrenda? anclajes,
  ImagenPrenda imagen,
  CajaVideo caja,
) {
  final linea = lineaCorporal(landmarks, region, caja);
  if (linea == null || imagen.ancho <= 0 || imagen.alto <= 0) return null;

  // Sin anclajes se usa el ancho completo de la imagen a media altura: la
  // ubicación sigue siendo automática, apenas menos precisa.
  final par = anclajeDeRegion(anclajes, region);
  final izquierda = par?.izquierda ?? const [0, 0.12];
  final derecha = par?.derecha ?? const [1, 0.12];
  if (izquierda.length < 2 || derecha.length < 2) return null;

  final anchoAnclaje = math.max(0.05, derecha[0] - izquierda[0]);
  final anchoDeseado = (linea.spanPx * _reglas[region]!.holgura) / anchoAnclaje;
  final scale = anchoDeseado / imagen.ancho;

  // Punto medio del anclaje, en píxeles de la imagen ya escalada, medido desde
  // el centro de la imagen (que es donde la ubica el escenario).
  final anclajeX = (izquierda[0] + derecha[0]) / 2;
  final anclajeY = (izquierda[1] + derecha[1]) / 2;
  final dx = (anclajeX - 0.5) * imagen.ancho * scale;
  final dy = (anclajeY - 0.5) * imagen.alto * scale;

  // La imagen se rota alrededor de su centro: el vector al anclaje rota con ella.
  final cosV = math.cos(linea.rotation);
  final sinV = math.sin(linea.rotation);
  final centroX = linea.midX - (dx * cosV - dy * sinV);
  final centroY = linea.midY - (dx * sinV + dy * cosV);

  return AjustePrenda(
    offsetX: centroX - caja.escenarioAncho / 2,
    offsetY: centroY - caja.escenarioAlto / 2,
    rotation: linea.rotation,
    scale: scale,
  );
}

/// Mezcla exponencial entre el ajuste mostrado y el recién calculado, para que
/// la prenda no tiemble con el ruido de la detección.
AjustePrenda suavizarAjuste(AjustePrenda? actual, AjustePrenda objetivo, [double k = 0.35]) {
  if (actual == null) return objetivo;
  double mezcla(double a, double b) => a + (b - a) * k;
  return AjustePrenda(
    offsetX: mezcla(actual.offsetX, objetivo.offsetX),
    offsetY: mezcla(actual.offsetY, objetivo.offsetY),
    rotation: mezcla(actual.rotation, objetivo.rotation),
    scale: mezcla(actual.scale, objetivo.scale),
  );
}

double _hipot(double dx, double dy) => math.sqrt(dx * dx + dy * dy);
