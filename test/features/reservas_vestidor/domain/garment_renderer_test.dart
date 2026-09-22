// Port de `garment-renderer.spec.ts` de la web: dibujo vectorial de la prenda.
//
// La geometría (polígonos, ejes, puntos estimados, tono y vocabulario) se
// prueba en memoria igual que en la web. El dibujo sobre canvas se ejecuta de
// verdad con un [Canvas] respaldado por [ui.PictureRecorder], que en pruebas de
// Flutter funciona sin pantalla.
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_marketplace_moda/features/reservas_vestidor/domain/garment_renderer.dart';

/// Cuerpo de pie en píxeles, con hombros de 100 px de ancho.
const _banda = 0.0;

List<Punto> cuerpo() {
  final pts = List<Punto>.generate(33, (_) => const Punto(_banda, _banda));
  pts[P.hombroIzq] = const Punto(350, 200);
  pts[P.hombroDer] = const Punto(250, 200);
  pts[P.codoIzq] = const Punto(380, 290);
  pts[P.codoDer] = const Punto(220, 290);
  pts[P.munecaIzq] = const Punto(395, 380);
  pts[P.munecaDer] = const Punto(205, 380);
  pts[P.caderaIzq] = const Punto(335, 380);
  pts[P.caderaDer] = const Punto(265, 380);
  pts[P.rodillaIzq] = const Punto(335, 520);
  pts[P.rodillaDer] = const Punto(265, 520);
  pts[P.tobilloIzq] = const Punto(335, 650);
  pts[P.tobilloDer] = const Punto(265, 650);
  return pts;
}

double _minX(List<Punto> pts) => pts.map((p) => p.x).reduce((a, b) => a < b ? a : b);
double _maxX(List<Punto> pts) => pts.map((p) => p.x).reduce((a, b) => a > b ? a : b);
double _maxY(List<Punto> pts) => pts.map((p) => p.y).reduce((a, b) => a > b ? a : b);

void main() {
  group('Elección de la forma de la prenda', () {
    const casos = <String, FormaPrenda>{
      'Camisa de lino': FormaPrenda.camisa,
      'Blusa de seda': FormaPrenda.camisa,
      'Polera básica': FormaPrenda.remera,
      'Musculosa deportiva': FormaPrenda.musculosa,
      'Chaqueta de jean': FormaPrenda.chaqueta,
      'Pantalón chino': FormaPrenda.pantalon,
      'Short de lino': FormaPrenda.short,
      'Falda midi plisada': FormaPrenda.falda,
      'Vestido largo': FormaPrenda.vestido,
    };
    casos.forEach((tipo, esperado) {
      test('«$tipo» se dibuja como $esperado', () {
        expect(formaDePrenda(tipo), esperado);
      });
    });

    test('sin tipo declarado usa la región del cuerpo', () {
      expect(formaDePrenda(null, 'lower_body'), FormaPrenda.pantalon);
      expect(formaDePrenda(null, 'full_body'), FormaPrenda.vestido);
      expect(formaDePrenda(null, 'upper_body'), FormaPrenda.remera);
    });

    test('clasifica superiores e inferiores', () {
      expect(esSuperior(FormaPrenda.camisa), isTrue);
      expect(esInferior(FormaPrenda.pantalon), isTrue);
      expect(esInferior(FormaPrenda.remera), isFalse);
    });
  });

  group('Geometría sobre el cuerpo', () {
    test('toma la escala y los ejes de los hombros y la cadera', () {
      final e = ejes(cuerpo());
      expect(e, isNotNull);
      expect(e!.ancho, closeTo(100, 0));
      expect(e.abajo.y, greaterThan(0.9)); // hacia los pies
      expect(e.centroHombros.x, closeTo(300, 0));
    });

    test('sin hombros no hay nada que vestir', () {
      final sinHombros = List<Punto>.generate(11, (_) => const Punto(0, 0));
      expect(ejes(sinHombros), isNull);
      expect(poligonoTorso(sinHombros, FormaPrenda.remera), isNull);
    });

    test('el torso cubre desde los hombros hasta bajo la cadera', () {
      final pts = cuerpo();
      final torso = poligonoTorso(pts, FormaPrenda.remera);
      expect(torso, isNotNull);
      // Más ancho que la línea de hombros (250..350).
      expect(_minX(torso!), lessThan(250));
      expect(_maxX(torso), greaterThan(350));
      // Y baja por debajo de la cadera (y=380).
      expect(_maxY(torso), greaterThan(380));
    });

    test('el vestido llega bastante más abajo que una remera', () {
      final pts = cuerpo();
      final remera = _maxY(poligonoTorso(pts, FormaPrenda.remera)!);
      final vestido = _maxY(poligonoTorso(pts, FormaPrenda.vestido)!);
      expect(vestido, greaterThan(remera + 80));
    });

    test('el short termina sobre la rodilla y el pantalón en el tobillo', () {
      final pts = cuerpo();
      final short = _maxY(poligonoPierna(pts, FormaPrenda.short, 'izq')!);
      final pantalon = _maxY(poligonoPierna(pts, FormaPrenda.pantalon, 'izq')!);
      expect(short, lessThan(520)); // rodilla
      expect(pantalon, greaterThanOrEqualTo(640)); // tobillo
    });

    test('la falda se acampana por debajo de la cadera', () {
      final pts = cuerpo();
      final falda = poligonoFalda(pts)!;
      final arriba = falda.where((p) => p.y < 420).toList();
      final abajo = falda.where((p) => p.y >= 420).toList();
      double anchoDe(List<Punto> grupo) => _maxX(grupo) - _minX(grupo);
      expect(anchoDe(abajo), greaterThan(anchoDe(arriba)));
    });
  });

  group('Puntos que la cámara no ve', () {
    test('estima cadera, codos y muñecas cuando no son visibles', () {
      final pts = cuerpo();
      bool soloHombros(int i) => i == P.hombroIzq || i == P.hombroDer;
      final completado = estimarOcultos(pts, soloHombros);

      expect(completado[P.caderaIzq].y, greaterThan(pts[P.hombroIzq].y));
      expect(completado[P.codoIzq].y, greaterThan(pts[P.hombroIzq].y));
      expect(completado[P.munecaIzq].y, greaterThan(completado[P.codoIzq].y));
      expect(completado[P.rodillaIzq].y, greaterThan(completado[P.caderaIzq].y));
      expect(poligonoTorso(completado, FormaPrenda.remera), isNotNull);
    });

    test('respeta los puntos que sí se ven', () {
      final pts = cuerpo();
      final completado = estimarOcultos(pts, (_) => true);
      expect(completado[P.caderaIzq].x, pts[P.caderaIzq].x);
      expect(completado[P.caderaIzq].y, pts[P.caderaIzq].y);
    });
  });

  group('Dibujo', () {
    test('dibuja una prenda superior sobre un canvas real', () {
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      final ok = dibujarPrenda(
        canvas,
        cuerpo(),
        const OpcionesDibujo(forma: FormaPrenda.remera, color: '#d62828'),
      );
      recorder.endRecording().dispose();
      expect(ok, isTrue);
    });

    test('con un cuerpo angosto (sin hombros ni cadera) no dibuja nada', () {
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      final ok = dibujarPrenda(
        canvas,
        <Punto>[],
        const OpcionesDibujo(forma: FormaPrenda.remera, color: '#111111'),
      );
      recorder.endRecording().dispose();
      expect(ok, isFalse);
    });
  });

  group('Tono del color', () {
    test('oscurece y aclara un color del catálogo', () {
      expect(tono('#808080', -0.5), 'rgb(64,64,64)');
      expect(tono('#808080', 0.5), 'rgb(192,192,192)');
    });

    test('tolera un color inválido sin romper el dibujo', () {
      expect(tono('no-es-color', -0.2), '#888888');
    });
  });

  group('Vocabulario de prendas', () {
    test('reconoce un hoodie como prenda de manga larga', () {
      // Regresión: «hoodie» no estaba en la lista y caía en el caso por defecto.
      expect(formaDePrenda('Hoodie de algodón'), FormaPrenda.mangaLarga);
      expect(formaDePrenda('Canguro oversize'), FormaPrenda.mangaLarga);
      expect(formaDePrenda('Buzo con capucha'), FormaPrenda.mangaLarga);
      expect(formaDePrenda('Cardigan de lana'), FormaPrenda.mangaLarga);
    });

    test('distingue abrigo de prenda liviana', () {
      expect(formaDePrenda('Campera de cuero'), FormaPrenda.chaqueta);
      expect(formaDePrenda('Trench largo'), FormaPrenda.chaqueta);
      expect(formaDePrenda('Saco de vestir'), FormaPrenda.chaqueta);
      expect(formaDePrenda('Chaleco puffer'), FormaPrenda.musculosa);
    });

    test('sigue reconociendo lo que ya reconocía', () {
      expect(formaDePrenda('Polera básica de algodón'), FormaPrenda.remera);
      expect(formaDePrenda('Camisa de lino'), FormaPrenda.camisa);
      expect(formaDePrenda('Vestido midi'), FormaPrenda.vestido);
      expect(formaDePrenda('Pantalón cargo'), FormaPrenda.pantalon);
      expect(formaDePrenda('Short de jean'), FormaPrenda.short);
      expect(formaDePrenda('Falda plisada'), FormaPrenda.falda);
    });
  });
}
