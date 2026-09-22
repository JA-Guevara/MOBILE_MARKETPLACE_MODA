// Dibujo de la prenda sobre el cuerpo detectado.
//
// Port de `garment-renderer.ts` de la web a Dart. Por qué vectorial y no la
// fotografía: la foto de catálogo viene con fondo, y recortarlo bien depende
// de que el fondo sea liso. Dibujar la prenda a partir de los puntos del
// cuerpo evita el problema por completo —nunca hay fondo que quitar—, funciona
// con cualquier prenda del catálogo sin preparación previa y se adapta al
// movimiento, porque cada vértice se recalcula en cada cuadro.
//
// La geometría vive en funciones puras que devuelven polígonos; el dibujo en
// Flutter es una capa fina encima (una función que recibe un [Canvas]). Así se
// puede verificar la forma sin pantalla.
import 'dart:math' as math;

import 'package:flutter/painting.dart';

/// Un punto del cuerpo ya proyectado a píxeles de pantalla.
class Punto {
  const Punto(this.x, this.y);

  final double x;
  final double y;

  Punto operator +(Punto otro) => Punto(x + otro.x, y + otro.y);
  Punto operator *(double k) => Punto(x * k, y * k);
  Punto operator -(Punto otro) => Punto(x - otro.x, y - otro.y);
}

/// Índices de los 33 puntos de MediaPipe Pose que usamos.
class P {
  static const int nariz = 0;
  static const int hombroIzq = 11;
  static const int hombroDer = 12;
  static const int codoIzq = 13;
  static const int codoDer = 14;
  static const int munecaIzq = 15;
  static const int munecaDer = 16;
  static const int caderaIzq = 23;
  static const int caderaDer = 24;
  static const int rodillaIzq = 25;
  static const int rodillaDer = 26;
  static const int tobilloIzq = 27;
  static const int tobilloDer = 28;
}

/// Formas que sabe dibujar el probador.
enum FormaPrenda { remera, musculosa, mangaLarga, camisa, chaqueta, pantalon, short, falda, vestido }

const Set<FormaPrenda> _superiores = {
  FormaPrenda.remera,
  FormaPrenda.musculosa,
  FormaPrenda.mangaLarga,
  FormaPrenda.camisa,
  FormaPrenda.chaqueta,
};
const Set<FormaPrenda> _inferiores = {
  FormaPrenda.pantalon,
  FormaPrenda.short,
  FormaPrenda.falda,
};

// --- Vectores -------------------------------------------------------------

Punto resta(Punto a, Punto b) => a - b;
Punto suma(Punto a, Punto b) => a + b;
Punto escala(Punto a, double k) => a * k;
Punto medio(Punto a, Punto b) => escala(suma(a, b), 0.5);
double largo(Punto a) => math.sqrt(a.x * a.x + a.y * a.y);
Punto unitario(Punto a) {
  final l = largo(a) == 0 ? 1 : largo(a);
  return Punto(a.x / l, a.y / l);
}

Punto entre(Punto a, Punto b, double t) => suma(a, escala(resta(b, a), t));

/// Traduce el tipo de prenda del catálogo a una forma dibujable.
FormaPrenda formaDePrenda(String? tipo, [String? region]) {
  final t = (tipo ?? '').toLowerCase();
  if (t.contains(RegExp(r'musculosa|tank|bividi|chaleco|crop'))) return FormaPrenda.musculosa;
  if (t.contains(RegExp(r'camisa|blusa|chomba'))) return FormaPrenda.camisa;
  if (t.contains(RegExp(r'chaqueta|campera|abrigo|blazer|bomber|parka|cazadora|trench|saco'))) {
    return FormaPrenda.chaqueta;
  }
  // «hoodie» y «canguro» faltaban y caían en remera: la prenda se dibujaba sin
  // mangas largas aunque el catálogo dijera claramente qué era.
  if (t.contains(RegExp(r'buzo|sweater|sudadera|manga larga|pullover|hoodie|hoody|canguro|polar|cardigan'))) {
    return FormaPrenda.mangaLarga;
  }
  if (t.contains('vestido')) return FormaPrenda.vestido;
  if (t.contains(RegExp(r'short|bermuda'))) return FormaPrenda.short;
  if (t.contains('falda')) return FormaPrenda.falda;
  if (t.contains(RegExp(r'pantal|jean|jogger|legging|chupin|cargo'))) return FormaPrenda.pantalon;
  if (t.contains(RegExp(r'remera|polera|camiseta|polo|top'))) return FormaPrenda.remera;
  // Sin tipo declarado, la región del cuerpo alcanza para elegir algo sensato.
  if (region == 'lower_body') return FormaPrenda.pantalon;
  if (region == 'full_body') return FormaPrenda.vestido;
  return FormaPrenda.remera;
}

bool esSuperior(FormaPrenda forma) => _superiores.contains(forma);
bool esInferior(FormaPrenda forma) => _inferiores.contains(forma);

/// Ejes del torso: escala, dirección de hombros y dirección hacia los pies.
class EjesPrenda {
  const EjesPrenda({
    required this.ancho,
    required this.cruz,
    required this.abajo,
    required this.centroHombros,
    required this.centroCaderas,
  });

  final double ancho;
  final Punto cruz;
  final Punto abajo;
  final Punto centroHombros;
  final Punto centroCaderas;
}

/// Acceso a un punto con verificación de rango: la cámara puede entregar menos
/// de los 33 landmarks esperados.
Punto? _at(List<Punto> pts, int i) => (i >= 0 && i < pts.length) ? pts[i] : null;

/// Completa los puntos que la cámara no ve.
///
/// Es habitual que la persona esté sentada frente al escritorio y la cadera o
/// las piernas queden fuera de cuadro. En vez de no dibujar nada, se estiman a
/// partir de los hombros, que son el único punto realmente obligatorio.
List<Punto> estimarOcultos(List<Punto> pts, bool Function(int i) visible) {
  final salida = List<Punto>.from(pts);
  if (salida.length < 33) return salida;
  final hi = salida[P.hombroIzq];
  final hd = salida[P.hombroDer];
  final distancia = largo(resta(hi, hd));
  final ancho = distancia == 0 ? 1 : distancia;
  final cruz = unitario(resta(hi, hd));
  // Perpendicular a la línea de hombros: hacia los pies.
  final abajo = Punto(-cruz.y, cruz.x);

  if (!visible(P.caderaIzq) || !visible(P.caderaDer)) {
    salida[P.caderaIzq] = suma(suma(hi, escala(abajo, ancho * 1.3)), escala(cruz, -ancho * 0.12));
    salida[P.caderaDer] = suma(suma(hd, escala(abajo, ancho * 1.3)), escala(cruz, ancho * 0.12));
  }
  for (final (hombro, codo, muneca, lado) in const <(int, int, int, int)>[
    (P.hombroIzq, P.codoIzq, P.munecaIzq, 1),
    (P.hombroDer, P.codoDer, P.munecaDer, -1),
  ]) {
    if (!visible(codo)) {
      salida[codo] = suma(suma(salida[hombro], escala(abajo, ancho * 0.7)), escala(cruz, lado * ancho * 0.15));
    }
    if (!visible(muneca)) salida[muneca] = suma(salida[codo], escala(abajo, ancho * 0.7));
  }
  for (final (cadera, rodilla, tobillo) in const <(int, int, int)>[
    (P.caderaIzq, P.rodillaIzq, P.tobilloIzq),
    (P.caderaDer, P.rodillaDer, P.tobilloDer),
  ]) {
    if (!visible(rodilla)) salida[rodilla] = suma(salida[cadera], escala(abajo, ancho * 1.1));
    if (!visible(tobillo)) salida[tobillo] = suma(salida[rodilla], escala(abajo, ancho * 1.1));
  }
  return salida;
}

EjesPrenda? ejes(List<Punto> pts) {
  final hi = _at(pts, P.hombroIzq);
  final hd = _at(pts, P.hombroDer);
  final ci = _at(pts, P.caderaIzq);
  final cd = _at(pts, P.caderaDer);
  if (hi == null || hd == null || ci == null || cd == null) return null;
  final ancho = largo(resta(hi, hd));
  if (ancho < 4) return null;
  return EjesPrenda(
    ancho: ancho,
    cruz: unitario(resta(hi, hd)),
    abajo: unitario(resta(medio(ci, cd), medio(hi, hd))),
    centroHombros: medio(hi, hd),
    centroCaderas: medio(ci, cd),
  );
}

/// Cuerpo de una prenda superior: hombros → cadera, algo más ancho que el torso.
List<Punto>? poligonoTorso(List<Punto> pts, FormaPrenda forma) {
  final e = ejes(pts);
  if (e == null) return null;
  final holgura = e.ancho *
      (forma == FormaPrenda.musculosa
          ? 0.12
          : forma == FormaPrenda.chaqueta
              ? 0.26
              : 0.22);
  // El vestido llega más abajo; el resto termina bajo la cadera.
  final caida = forma == FormaPrenda.vestido ? e.ancho * 1.5 : e.ancho * 0.18;
  final bajo = escala(e.abajo, caida);
  final subir = escala(e.abajo, -e.ancho * 0.06);
  final ensanchaBajo = forma == FormaPrenda.vestido ? 1.7 : 1.15;
  return [
    suma(suma(pts[P.hombroIzq], escala(e.cruz, holgura)), subir),
    suma(suma(pts[P.caderaIzq], escala(e.cruz, holgura * ensanchaBajo)), bajo),
    suma(suma(pts[P.caderaDer], escala(e.cruz, -holgura * ensanchaBajo)), bajo),
    suma(suma(pts[P.hombroDer], escala(e.cruz, -holgura)), subir),
  ];
}

/// Una pierna de una prenda inferior, como polígono.
List<Punto>? poligonoPierna(List<Punto> pts, FormaPrenda forma, String lado) {
  final e = ejes(pts);
  if (e == null) return null;
  final esIzq = lado == 'izq';
  final cadera = esIzq ? _at(pts, P.caderaIzq) : _at(pts, P.caderaDer);
  final rodilla = esIzq ? _at(pts, P.rodillaIzq) : _at(pts, P.rodillaDer);
  final tobillo = esIzq ? _at(pts, P.tobilloIzq) : _at(pts, P.tobilloDer);
  if (cadera == null || rodilla == null) return null;
  final signo = esIzq ? 1 : -1;
  final anchoPierna = e.ancho * 0.19;
  // El short llega arriba de la rodilla; el pantalón, al tobillo.
  final fin = forma == FormaPrenda.short ? entre(cadera, rodilla, 0.62) : (tobillo ?? rodilla);
  final centroCadera = e.centroCaderas;
  final interiorArriba = entre(cadera, centroCadera, 0.72);
  final interiorAbajo = suma(fin, escala(e.cruz, -signo * anchoPierna * 0.55));
  return [
    suma(cadera, escala(e.cruz, signo * anchoPierna * 0.9)),
    suma(fin, escala(e.cruz, signo * anchoPierna * 0.75)),
    interiorAbajo,
    interiorArriba,
  ];
}

/// Falda: trapecio desde la cadera, acampanado.
List<Punto>? poligonoFalda(List<Punto> pts) {
  final e = ejes(pts);
  if (e == null) return null;
  final largoFalda = escala(e.abajo, e.ancho * 1.0);
  final vuelo = e.ancho * 0.62;
  return [
    suma(pts[P.caderaIzq], escala(e.cruz, e.ancho * 0.12)),
    suma(suma(pts[P.caderaIzq], largoFalda), escala(e.cruz, vuelo)),
    suma(suma(pts[P.caderaDer], largoFalda), escala(e.cruz, -vuelo)),
    suma(pts[P.caderaDer], escala(e.cruz, -e.ancho * 0.12)),
  ];
}

/// Aclara u oscurece un color `#rrggbb`. Devuelve el mismo formato del canvas
/// de la web (`rgb(r,g,b)`) para mantener el contrato de `garment-renderer.ts`.
String tono(String hex, double factor) {
  var limpio = (hex.isEmpty ? '#888888' : hex).replaceAll('#', '');
  if (limpio.length == 3) {
    limpio = limpio.replaceAllMapped(RegExp('.'), (m) => '${m.group(0)}${m.group(0)}');
  }
  final valor = int.tryParse(limpio, radix: 16);
  if (valor == null) return '#888888';
  int canal(int v) {
    final base = factor < 0 ? v : 255 - v;
    return (v + base * factor).clamp(0, 255).round();
  }

  return 'rgb(${canal(valor >> 16)},${canal((valor >> 8) & 255)},${canal(valor & 255)})';
}

/// Opciones de dibujo de una prenda sobre el lienzo.
class OpcionesDibujo {
  const OpcionesDibujo({required this.forma, required this.color});

  final FormaPrenda forma;
  final String color;
}

/// Convierte un `#rrggbb` hex a un [Color] de Flutter.
Color hexToColor(String hex) => _colorDeRgb(tono(hex, 0));

/// Dibuja la prenda sobre un [Canvas]. Devuelve false si no hay cuerpo
/// suficiente (sin hombros no hay nada que vestir). El lienzo se asume por
/// fuera: esta función solo traza sobre el contexto dado.
bool dibujarPrenda(Canvas lienzo, List<Punto> pts, OpcionesDibujo opciones) {
  final e = ejes(pts);
  if (e == null) return false;
  _dibujarPrendaConEjes(lienzo, pts, e, opciones);
  return true;
}

void _dibujarPrendaConEjes(Canvas lienzo, List<Punto> pts, EjesPrenda e, OpcionesDibujo opciones) {
  final color = hexToColor(opciones.color);
  final oscuro = tono(opciones.color, -0.28);
  final colorOscuro = _colorDeRgb(oscuro);

  if (esInferior(opciones.forma)) {
    final relleno = Paint()..color = color;
    if (opciones.forma == FormaPrenda.falda) {
      final falda = poligonoFalda(pts);
      if (falda != null) _trazar(lienzo, falda, relleno);
    } else {
      for (final lado in const ['izq', 'der']) {
        final pierna = poligonoPierna(pts, opciones.forma, lado);
        if (pierna != null) _trazar(lienzo, pierna, relleno);
      }
    }
    // Cintura, para que se lea como prenda y no como una mancha.
    final caderaIzq = _at(pts, P.caderaIzq);
    final caderaDer = _at(pts, P.caderaDer);
    if (caderaIzq != null && caderaDer != null) {
      final contorno = Paint()
        ..color = colorOscuro
        ..style = PaintingStyle.stroke
        ..strokeWidth = e.ancho * 0.08;
      lienzo.drawLine(Offset(caderaIzq.x, caderaIzq.y), Offset(caderaDer.x, caderaDer.y), contorno);
    }
    return;
  }

  // Mangas: trazo grueso hombro → codo → muñeca según el largo.
  if (opciones.forma != FormaPrenda.musculosa) {
    final mangaLarga = opciones.forma == FormaPrenda.mangaLarga ||
        opciones.forma == FormaPrenda.chaqueta ||
        opciones.forma == FormaPrenda.camisa;
    final pincel = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = e.ancho * 0.34
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    for (final (hombro, codo, muneca) in const <(int, int, int)>[
      (P.hombroIzq, P.codoIzq, P.munecaIzq),
      (P.hombroDer, P.codoDer, P.munecaDer),
    ]) {
      final h = _at(pts, hombro);
      final c = _at(pts, codo);
      final m = _at(pts, muneca);
      if (h == null || c == null) continue;
      final inicio = suma(h, escala(e.abajo, e.ancho * 0.12));
      final ruta = Path()..moveTo(inicio.x, inicio.y);
      if (mangaLarga && m != null) {
        ruta
          ..lineTo(c.x, c.y)
          ..lineTo(m.x, m.y);
      } else {
        ruta.lineTo(entre(h, c, 0.55).x, entre(h, c, 0.55).y);
      }
      lienzo.drawPath(ruta, pincel);
    }
  }

  final torso = poligonoTorso(pts, opciones.forma);
  if (torso == null) return;
  _trazar(lienzo, torso, Paint()..color = color);

  // Cuello: se recorta del dibujo para que se vea la piel debajo.
  final cuello = suma(e.centroHombros, escala(e.abajo, e.ancho * 0.05));
  final angulo = math.atan2(e.cruz.y, e.cruz.x);
  _elipseRota(
    lienzo,
    cuello,
    e.ancho * 0.18,
    e.ancho * 0.11,
    angulo,
    Paint()..blendMode = BlendMode.dstOut,
  );
  _elipseRota(
    lienzo,
    cuello,
    e.ancho * 0.18,
    e.ancho * 0.11,
    angulo,
    Paint()
      ..color = colorOscuro
      ..style = PaintingStyle.stroke
      ..strokeWidth = e.ancho * 0.03,
  );

  // Detalles que distinguen una camisa o una chaqueta de una remera.
  if (opciones.forma == FormaPrenda.camisa || opciones.forma == FormaPrenda.chaqueta) {
    final desde = suma(e.centroHombros, escala(e.abajo, e.ancho * 0.16));
    final hasta = suma(e.centroCaderas, escala(e.abajo, e.ancho * 0.18));
    final lineaBoton = Paint()
      ..color = colorOscuro
      ..style = PaintingStyle.stroke
      ..strokeWidth = e.ancho * 0.035;
    lienzo.drawLine(Offset(desde.x, desde.y), Offset(hasta.x, hasta.y), lineaBoton);
    if (opciones.forma == FormaPrenda.camisa) {
      final boton = Paint()..color = _colorDeRgb(tono(opciones.color, 0.35));
      for (var i = 1; i <= 4; i++) {
        final b = entre(desde, hasta, i / 5);
        lienzo.drawCircle(Offset(b.x, b.y), e.ancho * 0.022, boton);
      }
    }
  }
}

void _trazar(Canvas lienzo, List<Punto> puntos, Paint pincel) {
  if (puntos.isEmpty) return;
  final ruta = Path()..moveTo(puntos.first.x, puntos.first.y);
  for (final p in puntos.skip(1)) {
    ruta.lineTo(p.x, p.y);
  }
  ruta.close();
  lienzo.drawPath(ruta, pincel);
}

void _elipseRota(Canvas lienzo, Punto centro, double rx, double ry, double angulo, Paint pincel) {
  lienzo.save();
  lienzo.translate(centro.x, centro.y);
  lienzo.rotate(angulo);
  lienzo.drawOval(Rect.fromCenter(center: Offset.zero, width: rx * 2, height: ry * 2), pincel);
  lienzo.restore();
}

Color _colorDeRgb(String rgb) {
  final partes = rgb
      .split(',')
      .map((v) => v.replaceAll(RegExp(r'[^\d]'), ''))
      .where((v) => v.isNotEmpty)
      .toList();
  if (partes.length == 3) {
    return Color.fromARGB(255, _entero(partes[0]), _entero(partes[1]), _entero(partes[2]));
  }
  return const Color(0xFF888888);
}

int _entero(String v) => int.tryParse(v)?.clamp(0, 255) ?? 128;
