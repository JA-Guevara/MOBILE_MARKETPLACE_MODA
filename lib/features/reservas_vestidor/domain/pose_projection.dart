// Proyección de la postura (MediaPipe Pose) al escenario del vestidor.
//
// Port de `pose-projection.ts` de la web a Dart: funciones PURAS, sin cámara
// ni MediaPipe, para poder probarlas aisladas. El seguimiento mueve la prenda
// y ajusta escala e inclinación a los hombros; no promete talla, tela ni
// comportamiento 3D.
import 'dart:math' as math;

/// Un punto del cuerpo que devuelve MediaPipe, en coordenadas normalizadas
/// [0..1] dentro del fotograma.
class Landmark {
  const Landmark(this.x, this.y, [this.visibility]);

  final double x;
  final double y;
  final double? visibility;
}

/// Dimensiones del fotograma y del escenario donde se pinta la prenda, y si la
/// cámara está reflejada (frontal).
class CajaVideo {
  const CajaVideo({
    required this.videoAncho,
    required this.videoAlto,
    required this.escenarioAncho,
    required this.escenarioAlto,
    this.reflejada = false,
  });

  final double videoAncho;
  final double videoAlto;
  final double escenarioAncho;
  final double escenarioAlto;
  final bool reflejada;
}

/// Postura del torso ya sobre el escenario: cuánto se corrió del centro, la
/// inclinación de los hombros y su ancho en píxeles (para escalar la prenda).
class TorsoPose {
  const TorsoPose({
    required this.offsetX,
    required this.offsetY,
    required this.rotation,
    required this.hombrosPx,
  });

  final double offsetX;
  final double offsetY;

  /// Inclinación de los hombros en el espacio de pantalla (radianes).
  final double rotation;
  final double hombrosPx;
}

/// Índices de los landmarks de MediaPipe Pose que usamos.
const int hombroIzquierdo = 11;
const int hombroDerecho = 12;
const int caderaIzquierda = 23;
const int caderaDerecha = 24;

/// Período sin detección válida tras el cual se considera a la persona fuera
/// del encuadre (en milisegundos).
const int posePerdidaMs = 1200;

/// Un landmark es utilizable si está dentro del rango [0..1] y, cuando MLKit
/// informa confianza, tiene visibilidad aceptable.
bool enRango(Landmark? p) =>
    p != null &&
    p.x >= 0 &&
    p.x <= 1 &&
    p.y >= 0 &&
    p.y <= 1 &&
    (p.visibility ?? 1) >= 0.5;

/// Extrae la primera pose del resultado de la detección.
///
/// MLKit y el puente con la web entregan el resultado en un [Map] con la clave
/// `poses` (o `landmarks`, como `result.landmarks` de PoseLandmarker): una lista
/// de poses, cada una una lista de landmarks con coordenadas normalizadas del
/// fotograma. Devuelve null para cualquier otra forma del resultado.
List<Landmark>? extraerPoseResultado(dynamic resultado) {
  if (resultado is! Map) return null;
  final poses = resultado['poses'] ?? resultado['landmarks'];
  if (poses is! List || poses.isEmpty) return null;
  final primera = poses.first;
  if (primera is List<Landmark> && primera.isNotEmpty) return primera;
  if (primera is List) {
    final puntos = <Landmark>[];
    for (final p in primera) {
      if (p is Landmark) {
        puntos.add(p);
      } else if (p is Map && p['x'] is num && p['y'] is num) {
        puntos.add(Landmark(
          (p['x'] as num).toDouble(),
          (p['y'] as num).toDouble(),
          p['visibility'] is num ? (p['visibility'] as num).toDouble() : 1,
        ));
      }
    }
    return puntos.isEmpty ? null : puntos;
  }
  if (primera is Map) return _mapiar(primera);
  return null;
}

List<Landmark>? _mapiar(Map primera) {
  final puntos = <Landmark>[];
  for (var i = 0; i < 33; i++) {
    final p = primera['$i'];
    if (p is Map && p['x'] is num && p['y'] is num) {
      puntos.add(Landmark(
        (p['x'] as num).toDouble(),
        (p['y'] as num).toDouble(),
        p['visibility'] is num ? (p['visibility'] as num).toDouble() : 1,
      ));
    }
  }
  return puntos.isEmpty ? null : puntos;
}

/// Acceso a un landmark con verificación de rango: la cámara puede entregar
/// menos de los 33 puntos esperados.
Landmark? _lm(List<Landmark> landmarks, int i) =>
    (i >= 0 && i < landmarks.length) ? landmarks[i] : null;

/// Convierte una pose de MLKit (o cualquier detector) al fotograma ya "parado".
///
/// MLKit entrega los landmarks normalizados `[0..1]` en el encuadre NATIVO del
/// sensor (apaisado en los teléfonos con orientación 90° o 270°), sin aplicarle
/// la rotación que se le pasa al `InputImage` (esa rotación solo le dice cómo
/// decodificar el buffer). Para dibujar sobre la cámara en pantalla vertical
/// hay que girar las coordenadas acá. `rotacionGrados` es el
/// `sensorOrientation` de la cámara (0 en dispositivos donde el buffer ya viene
/// vertical, como iOS).
List<Landmark> landmarksVerticales(List<Landmark> landmarks, int rotacionGrados) {
  if (landmarks.isEmpty || rotacionGrados % 360 == 0) return landmarks;
  switch (rotacionGrados % 360) {
    case 90: // 90° horario: el ancho del buffer pasa a ser la altura.
      return [for (final p in landmarks) Landmark(1 - p.y, p.x, p.visibility)];
    case 180:
      return [for (final p in landmarks) Landmark(1 - p.x, 1 - p.y, p.visibility)];
    case 270: // 90° antihorario.
      return [for (final p in landmarks) Landmark(p.y, 1 - p.x, p.visibility)];
    default:
      return landmarks;
  }
}

/// Centro del torso: punto medio de los hombros, bajado ~18% hacia el centro de
/// las caderas para ubicar la prenda sobre el pecho. Null si falta visibilidad.
Landmark? centroTorso(List<Landmark> landmarks) {
  final ls = _lm(landmarks, hombroIzquierdo);
  final rs = _lm(landmarks, hombroDerecho);
  final lh = _lm(landmarks, caderaIzquierda);
  final rh = _lm(landmarks, caderaDerecha);
  if (ls == null || rs == null || lh == null || rh == null) return null;
  if (!enRango(ls) || !enRango(rs) || !enRango(lh) || !enRango(rh)) return null;
  final sx = (ls.x + rs.x) / 2;
  final sy = (ls.y + rs.y) / 2;
  final hy = (lh.y + rh.y) / 2;
  return Landmark(sx, sy + (hy - sy) * 0.18);
}

/// Cómo crece el video para llenar el escenario recortando los bordes
/// (object-fit: cover) y dónde queda centrado.
({double scale, double offsetX, double offsetY}) cubiertaActiva(
  double videoAncho,
  double videoAlto,
  double escenarioAncho,
  double escenarioAlto,
) {
  final scale = math.max(escenarioAncho / videoAncho, escenarioAlto / videoAlto);
  return (
    scale: scale,
    offsetX: (escenarioAncho - videoAncho * scale) / 2,
    offsetY: (escenarioAlto - videoAlto * scale) / 2,
  );
}

/// Convierte una coordenada normalizada del video a píxeles de pantalla,
/// teniendo en cuenta el recorte por cover, el centrado y el reflejo de la
/// cámara frontal.
({double px, double py}) videoAPantalla(double nx, double ny, CajaVideo caja) {
  final cubierta = cubiertaActiva(
    caja.videoAncho,
    caja.videoAlto,
    caja.escenarioAncho,
    caja.escenarioAlto,
  );
  final x = caja.reflejada ? 1 - nx : nx;
  return (
    px: cubierta.offsetX + x * caja.videoAncho * cubierta.scale,
    py: cubierta.offsetY + ny * caja.videoAlto * cubierta.scale,
  );
}

/// Postura del torso ya proyectada al escenario. No puede calcularse sin ambos
/// hombros.
TorsoPose? posturaDeHombros(List<Landmark> landmarks, CajaVideo caja) {
  final ls = _lm(landmarks, hombroIzquierdo);
  final rs = _lm(landmarks, hombroDerecho);
  if (ls == null || rs == null) return null;
  if (!enRango(ls) || !enRango(rs)) return null;
  final li = videoAPantalla(ls.x, ls.y, caja);
  final rd = videoAPantalla(rs.x, rs.y, caja);
  final hombrosPx = math.sqrt((rd.px - li.px) * (rd.px - li.px) + (rd.py - li.py) * (rd.py - li.py));
  if (hombrosPx < 1) return null;
  var cy = (li.py + rd.py) / 2;
  final lh = _lm(landmarks, caderaIzquierda);
  final rh = _lm(landmarks, caderaDerecha);
  if (lh != null && rh != null && enRango(lh) && enRango(rh)) {
    final lhd = videoAPantalla(lh.x, lh.y, caja);
    final rhd = videoAPantalla(rh.x, rh.y, caja);
    cy += (((lhd.py + rhd.py) / 2) - cy) * 0.18;
  }
  final cx = (li.px + rd.px) / 2;
  return TorsoPose(
    offsetX: cx - caja.escenarioAncho / 2,
    offsetY: cy - caja.escenarioAlto / 2,
    rotation: math.atan2(rd.py - li.py, rd.px - li.px),
    hombrosPx: hombrosPx,
  );
}

/// Escala relativa para que la prenda acompañe el ancho de hombros medido.
double escalaDesdeHombros(double hombrosPx, double referenciaPx) =>
    referenciaPx > 0 ? hombrosPx / referenciaPx : 1;

/// (Compatibilidad con proyecciones simples) convierte el torso normalizado al
/// desplazamiento respecto del centro del escenario sin tener en cuenta cover.
({double offsetX, double offsetY}) desplazamientoDePose(
  Landmark torso,
  bool reflejada,
  double escenarioAncho,
  double escenarioAlto,
) {
  final nx = reflejada ? 1 - torso.x : torso.x;
  return (
    offsetX: escenarioAncho * (nx - 0.5),
    offsetY: escenarioAlto * (torso.y - 0.5),
  );
}

/// Suavizado exponencial entre el valor actual y el objetivo (evita "saltos").
({double x, double y}) suavizar(
  ({double x, double y}) actual,
  ({double x, double y}) objetivo,
  double k,
) =>
    (
      x: actual.x + (objetivo.x - actual.x) * k,
      y: actual.y + (objetivo.y - actual.y) * k,
    );
