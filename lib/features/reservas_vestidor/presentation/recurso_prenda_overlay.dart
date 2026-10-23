import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../domain/garment_fit.dart';
import '../domain/pose_projection.dart';
import '../infrastructure/vestidor_api.dart';

/// Muestra el PNG/WebP transparente que preparó el backend sobre la pose.
/// La imagen se posiciona por los anclajes de la prenda (hombros, cintura, …),
/// nunca como un rectángulo fijo sobre la cámara.
class RecursoPrendaOverlay extends StatefulWidget {
  const RecursoPrendaOverlay({
    super.key,
    required this.imagen,
    required this.recurso,
    required this.cuerpo,
    required this.region,
    required this.caja,
  });

  final ui.Image imagen;
  final RecursoVestidor recurso;
  final List<Landmark> cuerpo;
  final RegionCuerpo region;
  final CajaVideo caja;

  @override
  State<RecursoPrendaOverlay> createState() => _RecursoPrendaOverlayState();
}

class _RecursoPrendaOverlayState extends State<RecursoPrendaOverlay> {
  AjustePrenda? _ultimoAjuste;

  @override
  Widget build(BuildContext context) {
    final ajusteNuevo = calcularAjuste(
      widget.cuerpo,
      widget.region,
      widget.recurso.anclajes,
      (ancho: widget.imagen.width.toDouble(), alto: widget.imagen.height.toDouble()),
      widget.caja,
    );
    if (ajusteNuevo == null) {
      _ultimoAjuste = null;
      return const SizedBox.shrink();
    }

    final ajuste = suavizarAjuste(_ultimoAjuste, ajusteNuevo, 0.4);
    _ultimoAjuste = ajuste;

    return Positioned.fill(
      child: IgnorePointer(
        child: Center(
          child: Transform.translate(
            offset: Offset(ajuste.offsetX, ajuste.offsetY),
            child: Transform.rotate(
              angle: ajuste.rotation,
              child: Transform.scale(
                scaleX: widget.caja.reflejada ? -ajuste.scale : ajuste.scale,
                scaleY: ajuste.scale,
                child: SizedBox(
                  width: widget.imagen.width.toDouble(),
                  height: widget.imagen.height.toDouble(),
                  child: RawImage(image: widget.imagen, fit: BoxFit.fill),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
