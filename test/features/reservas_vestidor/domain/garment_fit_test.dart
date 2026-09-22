// Port de `garment-fit.spec.ts` de la web: ubicación automática de la prenda.
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_marketplace_moda/features/reservas_vestidor/domain/garment_fit.dart';
import 'package:mobile_marketplace_moda/features/reservas_vestidor/domain/pose_projection.dart';

/// Escenario cuadrado 1:1 para que los cálculos sean fáciles de seguir.
const box = CajaVideo(
  videoAncho: 600,
  videoAlto: 600,
  escenarioAncho: 600,
  escenarioAlto: 600,
);

/// Cuerpo de pie, centrado y derecho.
List<Landmark> cuerpo([Map<int, Landmark> sobrecarga = const {}]) {
  final puntos = List<Landmark>.generate(
      33, (i) => const Landmark(0.5, 0.5, 0.9));
  puntos[hombroIzquierdo] = const Landmark(0.4, 0.3, 0.9);
  puntos[hombroDerecho] = const Landmark(0.6, 0.3, 0.9);
  puntos[caderaIzquierda] = const Landmark(0.43, 0.6, 0.9);
  puntos[caderaDerecha] = const Landmark(0.57, 0.6, 0.9);
  sobrecarga.forEach((i, lm) => puntos[i] = lm);
  return puntos;
}

const anclajesCamiseta = <String, List<double>>{
  'shoulder_left': [0.1, 0.12],
  'shoulder_right': [0.9, 0.12],
  'hem_left': [0.15, 0.95],
  'hem_right': [0.85, 0.95],
};

void main() {
  group('Ubicación automática de la prenda', () {
    test('elige el anclaje de la región y descarta pares sin ancho', () {
      final par = anclajeDeRegion(anclajesCamiseta, RegionCuerpo.superior);
      expect(par, isNotNull);
      expect(par!.izquierda, [0.1, 0.12]);
      expect(par.derecha, [0.9, 0.12]);
      expect(anclajeDeRegion(anclajesCamiseta, RegionCuerpo.inferior), isNull);
      expect(
        anclajeDeRegion({
          'shoulder_left': [0.5, 0.1],
          'shoulder_right': [0.505, 0.1],
        }, RegionCuerpo.superior),
        isNull,
      );
    });

    test('mide la línea corporal de cada región', () {
      final hombros = lineaCorporal(cuerpo(), RegionCuerpo.superior, box);
      expect(hombros, isNotNull);
      expect(hombros!.spanPx, closeTo(120, 0));
      expect(hombros.midX, closeTo(300, 0));
      expect(hombros.rotation, closeTo(0, 1e-5));

      final cadera = lineaCorporal(cuerpo(), RegionCuerpo.inferior, box)!;
      expect(cadera.spanPx, closeTo(84, 1e-6));
      expect(cadera.midY, greaterThan(hombros.midY));
    });

    test('coloca el anclaje de la prenda sobre la línea del cuerpo', () {
      final ajuste = calcularAjuste(
        cuerpo(),
        RegionCuerpo.superior,
        anclajesCamiseta,
        (ancho: 400, alto: 600),
        box,
      );
      expect(ajuste, isNotNull);

      // El ancho del anclaje (0.8 de la imagen) debe cubrir los hombros con holgura.
      final anchoPrenda = 400 * ajuste!.scale;
      expect(anchoPrenda * 0.8, closeTo(120 * 1.35, 0));

      // Y el punto medio del anclaje cae justo sobre el medio de los hombros.
      final centroX = box.escenarioAncho / 2 + ajuste.offsetX;
      final centroY = box.escenarioAlto / 2 + ajuste.offsetY;
      final anclajeY = (0.12 - 0.5) * 600 * ajuste.scale;
      expect(centroX, closeTo(300, 0));
      expect(centroY + anclajeY, closeTo(180, 0)); // y=0.3 sobre 600 px
    });

    test('acompaña la inclinación de los hombros', () {
      final inclinado = cuerpo({
        hombroIzquierdo: const Landmark(0.4, 0.34, 0.9),
        hombroDerecho: const Landmark(0.6, 0.26, 0.9),
      });
      final ajuste = calcularAjuste(
        inclinado,
        RegionCuerpo.superior,
        anclajesCamiseta,
        (ancho: 400, alto: 600),
        box,
      )!;
      expect(ajuste.rotation, lessThan(0));
      expect(ajuste.rotation.abs(), greaterThan(0.2));
    });

    test('sin anclajes sigue ubicando la prenda, apenas menos precisa', () {
      final ajuste = calcularAjuste(
        cuerpo(),
        RegionCuerpo.superior,
        null,
        (ancho: 400, alto: 600),
        box,
      );
      expect(ajuste, isNotNull);
      expect(ajuste!.scale, greaterThan(0));
    });

    test('no puede ubicar nada si no ve la parte que corresponde', () {
      final sinHombros = cuerpo({
        hombroIzquierdo: const Landmark(0.4, 0.3, 0.1),
        hombroDerecho: const Landmark(0.6, 0.3, 0.1),
      });
      expect(
        calcularAjuste(sinHombros, RegionCuerpo.superior, anclajesCamiseta, (ancho: 400, alto: 600), box),
        isNull,
      );
    });
  });

  group('Indicaciones a la persona', () {
    test('pide ubicarse frente a la cámara cuando no detecta a nadie', () {
      final guia = evaluarPostura(null, RegionCuerpo.superior, box);
      expect(guia.codigo, CodigoGuia.sinPersona);
      expect(guia.ok, isFalse);
    });

    test('nombra la parte del cuerpo que falta ver', () {
      final sinCadera = cuerpo({
        caderaIzquierda: const Landmark(0.43, 0.6, 0.1),
        caderaDerecha: const Landmark(0.57, 0.6, 0.1),
      });
      final guia = evaluarPostura(sinCadera, RegionCuerpo.inferior, box);
      expect(guia.codigo, CodigoGuia.parcial);
      expect(guia.mensaje, contains('cadera'));
    });

    test('pide acercarse o alejarse según el encuadre', () {
      final lejos = cuerpo({
        hombroIzquierdo: const Landmark(0.48, 0.3, 0.9),
        hombroDerecho: const Landmark(0.52, 0.3, 0.9),
      });
      expect(evaluarPostura(lejos, RegionCuerpo.superior, box).codigo, CodigoGuia.lejos);

      final cerca = cuerpo({
        hombroIzquierdo: const Landmark(0.05, 0.3, 0.9),
        hombroDerecho: const Landmark(0.95, 0.3, 0.9),
      });
      expect(evaluarPostura(cerca, RegionCuerpo.superior, box).codigo, CodigoGuia.cerca);
    });

    test('pide enderezarse cuando está muy inclinado', () {
      final torcido = cuerpo({
        hombroIzquierdo: const Landmark(0.4, 0.42, 0.9),
        hombroDerecho: const Landmark(0.6, 0.22, 0.9),
      });
      final guia = evaluarPostura(torcido, RegionCuerpo.superior, box);
      expect(guia.codigo, CodigoGuia.inclinado);
      expect(guia.mensaje, contains('derecho'));
    });

    test('avisa que está todo listo con una postura correcta', () {
      final guia = evaluarPostura(cuerpo(), RegionCuerpo.superior, box);
      expect(guia.codigo, CodigoGuia.ok);
      expect(guia.ok, isTrue);
    });

    test('para cuerpo entero exige ver también la cadera', () {
      final sinCadera = cuerpo({
        caderaIzquierda: const Landmark(0.43, 0.6, 0.1),
        caderaDerecha: const Landmark(0.57, 0.6, 0.1),
      });
      expect(
        evaluarPostura(sinCadera, RegionCuerpo.cuerpoEntero, box).codigo,
        CodigoGuia.parcial,
      );
    });
  });

  group('Suavizado', () {
    test('acerca el ajuste mostrado al nuevo sin saltos', () {
      const actual = AjustePrenda(offsetX: 0, offsetY: 0, rotation: 0, scale: 1);
      const objetivo = AjustePrenda(offsetX: 100, offsetY: -50, rotation: 0.2, scale: 2);
      final suave = suavizarAjuste(actual, objetivo, 0.5);
      expect(suave.offsetX, 50);
      expect(suave.offsetY, -25);
      expect(suave.scale, 1.5);
    });

    test('el primer ajuste se adopta tal cual', () {
      const objetivo = AjustePrenda(offsetX: 10, offsetY: 10, rotation: 0, scale: 1);
      expect(suavizarAjuste(null, objetivo).offsetX, objetivo.offsetX);
    });
  });
}
