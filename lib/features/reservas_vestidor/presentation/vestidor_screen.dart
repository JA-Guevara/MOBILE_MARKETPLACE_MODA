// Probador virtual (RF13): cámara en vivo + detección de pose en el dispositivo.
//
// Equiparable al vestidor de la web, pero nativo: en la web el seguimiento lo
// hace MediaPipe sobre el <video>; acá la cámara entrega fotogramas YUV y
// google_mlkit_pose_detection localiza los 33 puntos corporales (~15 fps, sin
// mandar nada a un servidor: la privacidad corre en el teléfono). Las funciones
// del probador (enderezar la pose, proyectarla a pantalla, dibujar la prenda)
// viven en `lib/features/reservas_vestidor/domain` y son las mismas que se prueban aisladas.
import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

import '../../../core/network/api_exception.dart';
import '../../usuarios_catalogo/application/session_controller.dart';
import '../../usuarios_catalogo/domain/producto.dart';
import '../../usuarios_catalogo/infrastructure/catalog_api.dart';
import '../application/vestidor_controller.dart';
import '../domain/garment_fit.dart';
import '../domain/garment_renderer.dart';
import '../domain/pose_projection.dart';
import 'prenda_overlay.dart';

/// Color de la prenda mientras no se trae del catálogo. Es el accent de la
/// paleta de la marca.
const String _colorPorDefecto = '#74394e';

/// En camara frontal el preview se espeja en el widget y la proyección
/// invierte el eje X con los mismos criterios que la web.
const bool _reflejada = true;

class VestidorScreen extends ConsumerStatefulWidget {
  const VestidorScreen({super.key, required this.slug});

  final String slug;

  @override
  ConsumerState<VestidorScreen> createState() => _VestidorScreenState();
}

class _VestidorScreenState extends ConsumerState<VestidorScreen> {
  CameraController? _camara;
  PoseDetector? _detector;
  int _rotacion = 0;
  bool _procesando = false;
  Producto? _producto;
  String? _errorProducto;

  @override
  void initState() {
    super.initState();
    _iniciar();
  }

  Future<void> _iniciar() async {
    _detector = PoseDetector(
      options: PoseDetectorOptions(
        model: PoseDetectionModel.base,
        mode: PoseDetectionMode.stream,
      ),
    );
    _cargarProducto();
    await _encenderCamara();
  }

  Future<void> _cargarProducto() async {
    try {
      final producto = await CatalogApi(ref.read(apiClientProvider))
          .detalle(widget.slug);
      if (mounted) setState(() => _producto = producto);
    } on ApiException catch (error) {
      if (mounted) setState(() => _errorProducto = error.message);
    }
  }

  Future<void> _encenderCamara() async {
    if (_camara != null) return;
    final controlador = ref.read(vestidorProvider.notifier);
    controlador.empezarPreparacion();
    try {
      final camaras = await availableCameras();
      final frontal = camaras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => camaras.first,
      );
      _rotacion = frontal.sensorOrientation % 360;
      final camara = CameraController(
        frontal,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.yuv420,
      );
      await camara.initialize();
      if (!mounted) {
        await camara.dispose();
        return;
      }
      setState(() => _camara = camara);
      controlador.listaParaUsar();
      await camara.startImageStream(_procesarFotograma);
    } on CameraException catch (error) {
      controlador.fallar('No se pudo abrir la cámara (${error.code}).');
    } catch (_) {
      controlador.fallar('No se pudo abrir la cámara.');
    }
  }

  ImageSize _tamanoDeCamara() {
    final tamanos = _camara?.value.previewSize;
    return ImageSize(
      ancho: (tamanos?.width ?? 0).toDouble(),
      alto: (tamanos?.height ?? 0).toDouble(),
    );
  }

  Future<void> _procesarFotograma(CameraImage imagen) async {
    if (_procesando) return;
    final detector = _detector;
    if (detector == null || _camara == null) return;
    _procesando = true;
    try {
      final poses = await detector.processImage(_entradaDe(imagen));
      final controlador = ref.read(vestidorProvider.notifier);
      if (poses.isEmpty) {
        controlador.sacarPersona();
        return;
      }
      controlador.recibirPose(
        landmarksVerticales(_crearCuerpo(poses.first.landmarks), _rotacion),
      );
    } on PlatformException {
      // Fotograma inválido durante una transición de la cámara: se ignora.
    } catch (_) {
      // Lo mismo, por las dudas de un formato distinto.
    } finally {
      _procesando = false;
    }
  }

  InputImage _entradaDe(CameraImage imagen) {
    final bytes = Uint8List.fromList([
      for (final plano in imagen.planes) ...plano.bytes,
    ]);
    return InputImage.fromBytes(
      bytes: bytes,
      metadata: InputImageMetadata(
        size: Size(imagen.width.toDouble(), imagen.height.toDouble()),
        rotation: _rotacionComoEntrada(_rotacion),
        format: _formatoDe(imagen.format.group),
        bytesPerRow: imagen.planes.first.bytesPerRow,
      ),
    );
  }

  InputImageRotation _rotacionComoEntrada(int grados) {
    switch (grados % 360) {
      case 90:
        return InputImageRotation.rotation90deg;
      case 180:
        return InputImageRotation.rotation180deg;
      case 270:
        return InputImageRotation.rotation270deg;
      default:
        return InputImageRotation.rotation0deg;
    }
  }

  InputImageFormat _formatoDe(ImageFormatGroup grupo) {
    switch (grupo) {
      case ImageFormatGroup.nv21:
        return InputImageFormat.nv21;
      case ImageFormatGroup.yuv420:
        return InputImageFormat.yuv420;
      case ImageFormatGroup.bgra8888:
        return InputImageFormat.bgra8888;
      default:
        return InputImageFormat.nv21;
    }
  }

  /// Pasa el mapa de MLKit (índice → punto) a la lista de 33 que esperan los
  /// módulos del probador. MLKit ordena los landmarks exactamente igual que
  /// MediaPipe, así que `i` es el índice estándar.
  List<Landmark> _crearCuerpo(Map<PoseLandmarkType, PoseLandmark> mapa) {
    final puntos = <Landmark>[];
    for (var i = 0; i < 33; i++) {
      final punto = mapa[PoseLandmarkType.values[i]];
      if (punto != null) puntos.add(Landmark(punto.x, punto.y, punto.likelihood));
    }
    return puntos;
  }

  FormaPrenda get _forma {
    final producto = _producto;
    final descripcion = producto == null
        ? ''
        : '${producto.nombre} ${producto.categoria}';
    return formaDePrenda(descripcion);
  }

  RegionCuerpo _regionDe(FormaPrenda forma) {
    if (forma == FormaPrenda.vestido) return RegionCuerpo.cuerpoEntero;
    if (esInferior(forma)) return RegionCuerpo.inferior;
    return RegionCuerpo.superior;
  }

  @override
  void dispose() {
    final detector = _detector;
    if (detector != null) unawaited(detector.close());
    final camara = _camara;
    if (camara != null) unawaited(camara.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vestidor = ref.watch(vestidorProvider);
    return Scaffold(
      backgroundColor: Colors.black,
      body: LayoutBuilder(
        builder: (context, restricciones) => _CuerpoVestidor(
          vestidor: vestidor,
          camara: _camara,
          tamano: _tamanoDeCamara(),
          opciones: OpcionesDibujo(forma: _forma, color: _colorPorDefecto),
          region: _regionDe(_forma),
          producto: _producto,
          errorProducto: _errorProducto,
          anchoPantalla: restricciones.maxWidth,
          altoPantalla: restricciones.maxHeight,
          onReintentar: _iniciar,
        ),
      ),
    );
  }
}

/// Dimensiones del fotograma vertical de la cámara.
class ImageSize {
  const ImageSize({required this.ancho, required this.alto});

  final double ancho;
  final double alto;

  bool get estaListo => ancho > 0 && alto > 0;
}

class _CuerpoVestidor extends StatelessWidget {
  const _CuerpoVestidor({
    required this.vestidor,
    required this.camara,
    required this.tamano,
    required this.opciones,
    required this.region,
    required this.producto,
    required this.errorProducto,
    required this.anchoPantalla,
    required this.altoPantalla,
    required this.onReintentar,
  });

  final EstadoVestidor vestidor;
  final CameraController? camara;
  final ImageSize tamano;
  final OpcionesDibujo opciones;
  final RegionCuerpo region;
  final Producto? producto;
  final String? errorProducto;
  final double anchoPantalla;
  final double altoPantalla;
  final VoidCallback onReintentar;

  /// El escenario de la cámara cabe centrado, conservando la proporción
  /// (letterbox negro por fuera, igual que `object-fit: contain`).
  ImageSize _escenario() {
    if (!tamano.estaListo || tamano.alto <= 0 || tamano.ancho <= 0) {
      return ImageSize(ancho: anchoPantalla, alto: altoPantalla);
    }
    final proporcion = tamano.ancho / tamano.alto;
    final proporcionPantalla = anchoPantalla / altoPantalla;
    if (proporcion >= proporcionPantalla) {
      return ImageSize(
        ancho: anchoPantalla,
        alto: anchoPantalla / proporcion,
      );
    }
    return ImageSize(
      ancho: altoPantalla * proporcion,
      alto: altoPantalla,
    );
  }

  @override
  Widget build(BuildContext context) {
    final escenario = _escenario();
    if (camara == null) return _Esperando(vestidor: vestidor);

    return Stack(
      fit: StackFit.expand,
      children: [
        // La caja de la cámara: preview espejado y la prenda encima.
        Center(
          child: SizedBox(
            width: escenario.ancho,
            height: escenario.alto,
            child: ClipRect(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Transform.flip(
                    flipX: _reflejada,
                    child: camara!.buildPreview(),
                  ),
                  if (vestidor.hayPose)
                    CustomPaint(
                      painter: _painter(escenario),
                    ),
                ],
              ),
            ),
          ),
        ),
        // Guía con instrucciones y barra inferior.
        SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.of(context).maybePop(),
                      icon: const Icon(Icons.arrow_back, color: Colors.white),
                      tooltip: 'Volver',
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: _Guia(
                        guia: evaluarPostura(
                          vestidor.cuerpo,
                          region,
                          _cajaDe(escenario),
                        ),
                      ),
                    ),
                    const SizedBox(width: 48),
                  ],
                ),
              ),
              const Spacer(),
              if (vestidor.error != null)
                _ErrorCamara(mensaje: vestidor.error!, onReintentar: onReintentar)
              else
                _BarraInferior(
                  producto: producto,
                  errorProducto: errorProducto,
                  hayPose: vestidor.hayPose,
                ),
            ],
          ),
        ),
      ],
    );
  }

  CajaVideo _cajaDe(ImageSize escenario) => CajaVideo(
        videoAncho: tamano.ancho,
        videoAlto: tamano.alto,
        escenarioAncho: escenario.ancho,
        escenarioAlto: escenario.alto,
        reflejada: _reflejada,
      );

  PrendaOverlayPainter _painter(ImageSize escenario) => PrendaOverlayPainter(
        cuerpo: vestidor.cuerpo,
        opciones: opciones,
        caja: _cajaDe(escenario),
      );
}

class _Esperando extends StatelessWidget {
  const _Esperando({required this.vestidor});

  final EstadoVestidor vestidor;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: vestidor.preparando
          ? const Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(color: Colors.white),
                SizedBox(height: 16),
                Text(
                  'Encendiendo la cámara…',
                  style: TextStyle(color: Colors.white70),
                ),
              ],
            )
          : const Text(
              'La cámara no está disponible.',
              style: TextStyle(color: Colors.white70),
            ),
    );
  }
}

class _Guia extends StatelessWidget {
  const _Guia({required this.guia});

  final Guia guia;

  @override
  Widget build(BuildContext context) {
    final color = guia.ok ? Colors.greenAccent : Colors.amberAccent;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: color, width: 1.2),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            guia.ok ? Icons.check_circle_outline : Icons.info_outline,
            color: color,
            size: 18,
          ),
          const SizedBox(width: 8),
          Flexible(child: Text(guia.mensaje, style: TextStyle(color: color))),
        ],
      ),
    );
  }
}

class _BarraInferior extends StatelessWidget {
  const _BarraInferior({
    required this.producto,
    required this.errorProducto,
    required this.hayPose,
  });

  final Producto? producto;
  final String? errorProducto;
  final bool hayPose;

  @override
  Widget build(BuildContext context) {
    final nombre = producto?.nombre ?? '';
    final categoria = producto?.categoria ?? '';
    final leyenda = errorProducto == null
        ? (hayPose
            ? 'Movete y la prenda te sigue.'
            : 'Parate de cuerpo entero frente a la cámara.')
        : 'No se pudo cargar la prenda: $errorProducto';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: const BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            nombre.isEmpty ? 'Probador virtual' : nombre.toUpperCase(),
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (categoria.isNotEmpty)
            Text(categoria, style: const TextStyle(color: Colors.white70)),
          const SizedBox(height: 6),
          Text(leyenda, style: const TextStyle(color: Colors.white70, fontSize: 12)),
        ],
      ),
    );
  }
}

class _ErrorCamara extends StatelessWidget {
  const _ErrorCamara({required this.mensaje, required this.onReintentar});

  final String mensaje;
  final VoidCallback onReintentar;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(color: Colors.black54),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(mensaje, style: const TextStyle(color: Colors.white)),
          const SizedBox(height: 8),
          FilledButton.tonal(onPressed: onReintentar, child: const Text('Reintentar')),
        ],
      ),
    );
  }
}

