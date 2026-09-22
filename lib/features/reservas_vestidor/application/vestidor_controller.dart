// Estado del probador virtual (RF13) durante una sesión de la cámara.
//
// Solo lo que la vista necesita para dibujar: la última pose recibida del
// detector (ya enderezada: en coordenadas verticales de pantalla) y el ciclo de
// vida de la cámara (iniciando / lista / con error). La detección de pose no
// vive acá: la hace la pantalla con google_mlkit_pose_detection en el
// dispositivo y le pasa esta pose. Mantenerlo así permite probar este módulo
// sin cámara.
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/pose_projection.dart';

/// Pose nativa del fotograma vertical (sin rotación del sensor aplicada).
typedef CuerpoVertical = List<Landmark>;

class EstadoVestidor {
  const EstadoVestidor({
    this.cuerpo = const <Landmark>[],
    this.preparando = true,
    this.error,
  });

  /// Última pose recibida, en coordenadas verticales `[0..1]` del fotograma
  /// ya parado. Vacía cuando la cámara todavía no detectó a nadie.
  final CuerpoVertical cuerpo;

  /// true mientras se enciende la cámara.
  final bool preparando;

  /// Error de cámara o de producto; null si todo va bien.
  final String? error;

  bool get hayPose => cuerpo.isNotEmpty;

  EstadoVestidor copyWith({
    CuerpoVertical? cuerpo,
    bool? preparando,
    String? error,
    bool limpiarError = false,
  }) =>
      EstadoVestidor(
        cuerpo: cuerpo ?? this.cuerpo,
        preparando: preparando ?? this.preparando,
        error: limpiarError ? null : (error ?? this.error),
      );
}

class VestidorController extends StateNotifier<EstadoVestidor> {
  VestidorController() : super(const EstadoVestidor());

  /// Se empieza a encender la cámara.
  void empezarPreparacion() => state = state.copyWith(
        preparando: true,
        limpiarError: true,
      );

  /// La cámara quedó lista y ya corre la detección de pose.
  void listaParaUsar() => state = state.copyWith(
        preparando: false,
        limpiarError: true,
      );

  /// La cámara (o la carga de la prenda) falló.
  void fallar(String mensaje) => state = state.copyWith(
        preparando: false,
        error: mensaje,
      );

  /// Nueva pose detectada, ya enderezada por la pantalla.
  void recibirPose(CuerpoVertical verticales) => state = state.copyWith(
        cuerpo: verticales,
        preparando: false,
        limpiarError: true,
      );

  /// La persona salió del encuadre: se baja la prenda.
  void sacarPersona() => state = state.copyWith(
        cuerpo: const <Landmark>[],
      );

  /// Para volver a probar después de un error.
  void reiniciar() {
    state = const EstadoVestidor();
    empezarPreparacion();
  }
}

final StateNotifierProvider<VestidorController, EstadoVestidor> vestidorProvider =
    StateNotifierProvider<VestidorController, EstadoVestidor>(
        (ref) => VestidorController());
