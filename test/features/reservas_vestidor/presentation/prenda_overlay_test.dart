// La capa de la prenda dibuja sobre un Canvas real lo que la geometría ya
// verificó: ninguna persona (cuerpo vacío) no traza nada, y con un cuerpo
// válido el lienzo termina con píxeles pintados.
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_marketplace_moda/features/reservas_vestidor/presentation/prenda_overlay.dart';
import 'package:mobile_marketplace_moda/features/reservas_vestidor/domain/garment_renderer.dart';
import 'package:mobile_marketplace_moda/features/reservas_vestidor/domain/pose_projection.dart';

const _tamano = Size(360, 640);

List<Landmark> _cuerpo() {
  final pts = List<Landmark>.generate(33, (_) => const Landmark(0.5, 0.5, 0.8));
  pts[hombroIzquierdo] = const Landmark(0.42, 0.28, 0.99);
  pts[hombroDerecho] = const Landmark(0.58, 0.28, 0.99);
  pts[caderaIzquierda] = const Landmark(0.42, 0.62, 0.95);
  pts[caderaDerecha] = const Landmark(0.58, 0.62, 0.95);
  return pts;
}

const caja = CajaVideo(
  videoAncho: 1080,
  videoAlto: 1920,
  escenarioAncho: 360,
  escenarioAlto: 640,
  reflejada: true,
);

const opciones = OpcionesDibujo(forma: FormaPrenda.remera, color: '#74394e');

void main() {
  test('con el cuerpo vacío no pinta nada', () {
    final painter = PrendaOverlayPainter(
      cuerpo: const [],
      opciones: opciones,
      caja: caja,
    );
    final recorder = ui.PictureRecorder();
    painter.paint(Canvas(recorder), _tamano);
    final picture = recorder.endRecording();
    picture.dispose();
  });

  test('con una persona pinta la prenda', () async {
    final painter = PrendaOverlayPainter(
      cuerpo: _cuerpo(),
      opciones: opciones,
      caja: caja,
    );
    final recorder = ui.PictureRecorder();
    painter.paint(Canvas(recorder), _tamano);
    final picture = recorder.endRecording();
    final imagen = await picture.toImage(
      _tamano.width.toInt(),
      _tamano.height.toInt(),
    );
    picture.dispose();
    final datos = await imagen.toByteData(format: ui.ImageByteFormat.rawRgba);

    expect(datos, isNotNull);
    final pixeles = datos!.buffer.asUint8List();
    var conAlpha = 0;
    for (var i = 3; i < pixeles.length; i += 4) {
      if (pixeles[i] > 0) conAlpha++;
    }
    expect(
      conAlpha,
      greaterThan(500),
    ); // hay una prenda dibujada, no un lienzo vacío
    imagen.dispose();
  });

  test(
    'sin hombros confiables no dibuja una prenda fuera del cuerpo',
    () async {
      final cuerpo = _cuerpo()..[hombroIzquierdo] = const Landmark(-1, -1, 0);
      final recorder = ui.PictureRecorder();
      PrendaOverlayPainter(
        cuerpo: cuerpo,
        opciones: opciones,
        caja: caja,
      ).paint(Canvas(recorder), _tamano);
      final picture = recorder.endRecording();
      final imagen = await picture.toImage(
        _tamano.width.toInt(),
        _tamano.height.toInt(),
      );
      final pixeles = (await imagen.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!.buffer.asUint8List();
      expect(
        [
          for (var i = 3; i < pixeles.length; i += 4) pixeles[i],
        ].every((alpha) => alpha == 0),
        isTrue,
      );
      imagen.dispose();
      picture.dispose();
    },
  );

  test('estima caderas fuera del encuadre y conserva la silueta', () async {
    final cuerpo = _cuerpo()
      ..[caderaIzquierda] = const Landmark(-1, -1, 0)
      ..[caderaDerecha] = const Landmark(-1, -1, 0);
    final recorder = ui.PictureRecorder();
    PrendaOverlayPainter(
      cuerpo: cuerpo,
      opciones: opciones,
      caja: caja,
    ).paint(Canvas(recorder), _tamano);
    final picture = recorder.endRecording();
    final imagen = await picture.toImage(
      _tamano.width.toInt(),
      _tamano.height.toInt(),
    );
    final pixeles = (await imagen.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    ))!.buffer.asUint8List();
    expect(
      [
        for (var i = 3; i < pixeles.length; i += 4) pixeles[i],
      ].where((alpha) => alpha > 0).length,
      greaterThan(500),
    );
    imagen.dispose();
    picture.dispose();
  });

  test('debe repintar cuando cambia la pose', () {
    final painter = PrendaOverlayPainter(
      cuerpo: _cuerpo(),
      opciones: opciones,
      caja: caja,
    );
    final otroCuerpo = _cuerpo()
      ..[hombroIzquierdo] = const Landmark(0.4, 0.28, 0.99);
    final otro = PrendaOverlayPainter(
      cuerpo: otroCuerpo,
      opciones: opciones,
      caja: caja,
    );
    expect(painter.shouldRepaint(otro), isTrue);
    final igual = PrendaOverlayPainter(
      cuerpo: _cuerpo(),
      opciones: opciones,
      caja: caja,
    );
    expect(painter.shouldRepaint(igual), isFalse);
  });
}
