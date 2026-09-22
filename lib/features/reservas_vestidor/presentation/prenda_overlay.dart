// Capa transparente que dibuja la prenda sobre la cámara en vivo.
//
// Recibe la pose enderezada (coordenadas verticales normalizadas) y el [CajaVideo]
// que describe el encuadre: proyecta cada punto a píxeles de pantalla con el
// mismo recorte por cover y reflejo de la cámara frontal que el resto del
// probador, y le pide al renderer que dibuje la forma sobre el Canvas.
import 'package:flutter/material.dart';

import '../domain/garment_renderer.dart';
import '../domain/pose_projection.dart';

class PrendaOverlayPainter extends CustomPainter {
  const PrendaOverlayPainter({
    required this.cuerpo,
    required this.opciones,
    required this.caja,
    super.repaint,
  });

  /// Última pose enderezada; vacía = no hay nada que dibujar.
  final List<Landmark> cuerpo;

  final OpcionesDibujo opciones;

  /// El encuadre del video: dimensiones verticales del fotograma y si la
  /// cámara está espejada (frontal). El escenario se completa en cada paint
  /// con el tamaño real del lienzo.
  final CajaVideo caja;

  @override
  void paint(Canvas canvas, Size size) {
    if (cuerpo.isEmpty) return;
    final caja = CajaVideo(
      videoAncho: this.caja.videoAncho,
      videoAlto: this.caja.videoAlto,
      escenarioAncho: size.width,
      escenarioAlto: size.height,
      reflejada: this.caja.reflejada,
    );
    final puntos = <Punto>[];
    for (final punto in cuerpo) {
      final proyectado = videoAPantalla(punto.x, punto.y, caja);
      puntos.add(Punto(proyectado.px, proyectado.py));
    }
    dibujarPrenda(canvas, puntos, opciones);
  }

  @override
  bool shouldRepaint(covariant PrendaOverlayPainter oldDelegate) =>
      !_mismaPose(oldDelegate.cuerpo, cuerpo) ||
      oldDelegate.opciones.forma != opciones.forma ||
      oldDelegate.opciones.color != opciones.color ||
      oldDelegate.caja.videoAncho != caja.videoAncho ||
      oldDelegate.caja.videoAlto != caja.videoAlto ||
      oldDelegate.caja.reflejada != caja.reflejada;

  /// Comparación por valores: cada frame llega una lista nueva con la misma
  /// postura y ahí no tiene sentido repintar.
  static bool _mismaPose(List<Landmark> a, List<Landmark> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      final pa = a[i];
      final pb = b[i];
      if (pa.x != pb.x || pa.y != pb.y || pa.visibility != pb.visibility) {
        return false;
      }
    }
    return true;
  }
}
