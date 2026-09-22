// Port de `pose-projection.spec.ts` de la web: seguimiento corporal del
// vestidor. Mismas poses y esperanzas, en Dart.
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_marketplace_moda/features/reservas_vestidor/domain/pose_projection.dart';

const _hombrosY = 0.3;
const _caderasY = 0.6;

List<Landmark> posed(double x) {
  final l = List<Landmark>.generate(33, (i) => const Landmark(0.5, 0.5, 0.9));
  l[hombroIzquierdo] = Landmark(x - 0.1, _hombrosY, 0.99);
  l[hombroDerecho] = Landmark(x + 0.1, _hombrosY, 0.99);
  l[caderaIzquierda] = Landmark(x - 0.12, _caderasY, 0.95);
  l[caderaDerecha] = Landmark(x + 0.12, _caderasY, 0.95);
  return l;
}

const caja = CajaVideo(
  videoAncho: 640,
  videoAlto: 480,
  escenarioAncho: 320,
  escenarioAlto: 360,
);

void main() {
  group('pose-projection (seguimiento corporal del vestidor)', () {
    group('extracción del resultado', () {
      test('lee la pose desde `landmarks`/`poses`', () {
        final pose = posed(0.5);
        final out = extraerPoseResultado({'landmarks': [pose]});
        expect(out, isNotNull);
        expect(out![hombroIzquierdo].x, pose[hombroIzquierdo].x);
        final porPoses = extraerPoseResultado({'poses': [pose]});
        expect(porPoses![hombroDerecho].x, pose[hombroDerecho].x);
      });

      test('devuelve null en formas ajenas', () {
        expect(extraerPoseResultado(null), isNull);
        expect(extraerPoseResultado({}), isNull);
        expect(extraerPoseResultado({'landmarks': <Object>[]}), isNull);
        expect(extraerPoseResultado({'landmarks': <Object>[]}), isNull);
        expect(extraerPoseResultado({'poseLandmarks': [posed(0.5)]}), isNull);
        expect(extraerPoseResultado({'landmarks': <Object>[]}), isNull);
      });
    });

    test('ubica el centro del torso entre los hombros, hacia el pecho', () {
      final torso = centroTorso(posed(0.5));
      expect(torso, isNotNull);
      expect(torso!.x, closeTo(0.5, 1e-5));
      expect(torso.y, closeTo(_hombrosY + (_caderasY - _hombrosY) * 0.18, 1e-5));
    });

    test('no da objetivo si no hay visibilidad suficiente', () {
      final l = posed(0.5);
      l[hombroIzquierdo] = const Landmark(-1, -1);
      expect(centroTorso(l), isNull);
      expect(centroTorso(<Landmark>[]), isNull);
      final bajo = posed(0.5);
      bajo[caderaDerecha] = const Landmark(0.5, 0.6, 0.1);
      expect(centroTorso(bajo), isNull);
      expect(enRango(const Landmark(0.9, 0.9, 0.4)), isFalse);
      expect(enRango(const Landmark(0.9, 0.9)), isTrue);
    });

    test('convierte el torso a desplazamiento en píxeles del escenario', () {
      final torso = centroTorso(posed(0.5))!;
      final out = desplazamientoDePose(torso, false, 300, 400);
      expect(out.offsetX, closeTo(0, 1e-5));
      expect(out.offsetY, closeTo(400 * (torso.y - 0.5), 1e-5));
    });

    test('invierte el eje X con la cámara frontal (espejada)', () {
      final torso = const Landmark(0.75, 0.5);
      final frente = desplazamientoDePose(torso, true, 300, 400);
      final atras = desplazamientoDePose(torso, false, 300, 400);
      expect(frente.offsetX, closeTo(-atras.offsetX, 1e-5));
    });

    test('suaviza la posición hacia el objetivo sin sobrepasarse', () {
      final next = suavizar((x: 0, y: 0), (x: 100, y: 40), 0.5);
      expect(next.x, 50);
      expect(next.y, 20);
    });

    group('object-fit: cover y mapeo contenedor', () {
      test('calcula el recorte y el centrado del video', () {
        final m2 = cubiertaActiva(640, 480, 320, 240);
        expect(m2.scale, closeTo(0.5, 1e-5));
        expect(m2.offsetX, closeTo(0, 1e-5));
        expect(m2.offsetY, closeTo(0, 1e-5));
        // Contenedor más alto (4:3 → cubrir vertical): se recorta el ancho.
        final alto = cubiertaActiva(640, 480, 320, 360);
        expect(alto.scale, closeTo(0.75, 1e-5));
        expect(alto.offsetX, closeTo(-80, 1e-5));
        expect(alto.offsetY, closeTo(0, 1e-5));
        // Contenedor más ancho: se recorta alto y se centra verticalmente.
        final ancho = cubiertaActiva(640, 480, 480, 320);
        expect(ancho.scale, closeTo(0.75, 1e-5));
        expect(ancho.offsetY, closeTo(-20, 1e-5));
      });

      test('mapea coordenadas normalizadas respetando cover y centrado', () {
        final p = videoAPantalla(0.5, 0.5, caja);
        expect(p.px, closeTo(160, 1e-5));
        expect(p.py, closeTo(180, 1e-5));
        // El borde derecho queda recortado por cover: cae fuera del contenedor.
        final borde = videoAPantalla(1, 1, caja);
        expect(borde.px, closeTo(400, 1e-5));
        expect(borde.py, closeTo(360, 1e-5));
        // El borde visible del contenedor corresponde a nx = (320 + 80) / 480.
        final visible = videoAPantalla(400 / 480, 0, caja);
        expect(visible.px, closeTo(320, 1e-5));
      });

      test('refleja la cámara frontal antes de mapear', () {
        final frente = videoAPantalla(
          0.75,
          0.5,
          const CajaVideo(
            videoAncho: 640,
            videoAlto: 480,
            escenarioAncho: 320,
            escenarioAlto: 360,
            reflejada: true,
          ),
        );
        final atras = videoAPantalla(0.25, 0.5, caja);
        expect(frente.px, closeTo(atras.px, 1e-5));
        expect(frente.py, closeTo(atras.py, 1e-5));
      });
    });

    group('postura de hombros proyectada', () {
      test('calcula posición, ancho de hombros e inclinación en pantalla', () {
        final pose = posed(0.5);
        pose[hombroDerecho] = const Landmark(0.6, 0.32, 0.99); // más bajo
        final out = posturaDeHombros(pose, caja);
        // Box 640x480 en contenedor 320x360 → cover scale 0.75, offsetX -80.
        final dxPx = 0.2 * 640 * 0.75;
        final dyPx = 0.02 * 480 * 0.75;
        expect(out, isNotNull);
        expect(out!.offsetX, closeTo(0, 1e-5)); // centrado
        expect(out.hombrosPx, closeTo(math.sqrt(dxPx * dxPx + dyPx * dyPx), 1e-5));
        expect(out.rotation, closeTo(math.atan2(dyPx, dxPx), 1e-5));
        // La prenda sigue el pecho: hombro medio (0.31) bajado 18%.
        final pechoY = 0.31 + (0.6 - 0.31) * 0.18;
        expect(out.offsetY, closeTo(pechoY * caja.escenarioAlto - caja.escenarioAlto / 2, 1e-5));
      });

      test('requiere ambos hombros visibles', () {
        final pose = posed(0.5);
        pose[hombroDerecho] = const Landmark(-1, -1);
        expect(posturaDeHombros(pose, caja), isNull);
      });

      test('conserva la posición al reflejar', () {
        final a = posturaDeHombros(posed(0.65), caja);
        final b = posturaDeHombros(
          posed(0.35),
          const CajaVideo(
            videoAncho: 640,
            videoAlto: 480,
            escenarioAncho: 320,
            escenarioAlto: 360,
            reflejada: true,
          ),
        );
        expect(a!.offsetX, closeTo(b!.offsetX, 1e-3));
      });
    });

    test('escala la prenda según el ancho de hombros de una referencia', () {
      expect(escalaDesdeHombros(100, 200), 0.5);
      expect(escalaDesdeHombros(100, 0), 1);
    });

    group('rotación del fotograma nativo de la cámara', () {
      test('sin rotación devuelve la misma pose', () {
        final original = posed(0.5);
        expect(landmarksVerticales(original, 0), same(original));
      });

      test('90° horario pasa el eje Y del buffer al eje X vertical', () {
        final upright = landmarksVerticales(const [Landmark(0.2, 0.3)], 90);
        expect(upright.first.x, closeTo(0.7, 1e-9));
        expect(upright.first.y, closeTo(0.2, 1e-9));
      });

      test('270° horario (90° antihorario) invierte el espejo', () {
        final upright = landmarksVerticales(const [Landmark(0.2, 0.3)], 270);
        expect(upright.first.x, closeTo(0.3, 1e-9));
        expect(upright.first.y, closeTo(0.8, 1e-9));
      });

      test('180° da vuelta ambos ejes', () {
        final upright = landmarksVerticales(const [Landmark(0.2, 0.3)], 180);
        expect(upright.first.x, closeTo(0.8, 1e-9));
        expect(upright.first.y, closeTo(0.7, 1e-9));
      });

      test('conserva la visibilidad de cada punto', () {
        final upright = landmarksVerticales(const [Landmark(0.2, 0.3, 0.85)], 90);
        expect(upright.first.visibility, closeTo(0.85, 1e-9));
      });

      // En el buffer apaisado del sensor la persona aparece "acostada": los
      // hombros quedan como una línea VERTICAL (misma x, distinta y). Al girar
      // el fotograma la persona vuelve a pararse: hombros horizontales y centro
      // del torso sobre el eje de simetría, con ambos sensores (90°/270°).
      List<Landmark> personaPaisaje() {
        final l = List.generate(33, (_) => const Landmark(0.5, 0.5, 0.9));
        l[hombroIzquierdo] = const Landmark(0.5, 0.62, 0.99);
        l[hombroDerecho] = const Landmark(0.5, 0.38, 0.99);
        l[caderaIzquierda] = const Landmark(0.62, 0.72, 0.95);
        l[caderaDerecha] = const Landmark(0.62, 0.28, 0.95);
        return l;
      }

      test('con sensor 90° el torso queda parado y centrado', () {
        final upright = landmarksVerticales(personaPaisaje(), 90);
        expect(upright[hombroIzquierdo].x, isNot(closeTo(upright[hombroDerecho].x, 0.005)));
        expect(centroTorso(upright)!.x, closeTo(0.5, 1e-5));
        expect(posturaDeHombros(upright, caja), isNotNull);
      });

      test('con sensor 270° el torso queda parado y centrado', () {
        final upright = landmarksVerticales(personaPaisaje(), 270);
        expect(upright[hombroIzquierdo].x, isNot(closeTo(upright[hombroDerecho].x, 0.005)));
        expect(centroTorso(upright)!.x, closeTo(0.5, 1e-5));
        expect(posturaDeHombros(upright, caja), isNotNull);
      });
    });
  });
}
