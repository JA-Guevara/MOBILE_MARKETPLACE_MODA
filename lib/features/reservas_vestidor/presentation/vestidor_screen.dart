// Probador virtual (RF13): cámara en vivo + detección de pose en el dispositivo.
//
// Equiparable al vestidor de la web, pero nativo: en la web el seguimiento lo
// hace MediaPipe sobre el <video>; acá la cámara entrega fotogramas YUV y
// google_mlkit_pose_detection localiza los 33 puntos corporales (~15 fps, sin
// mandar nada a un servidor: la privacidad corre en el teléfono). Las funciones
// del probador (enderezar la pose, proyectarla a pantalla, dibujar la prenda)
// viven en `lib/features/reservas_vestidor/domain` y son las mismas que se prueban aisladas.
import 'dart:async';
import 'dart:io' show Platform;
import 'dart:ui' as ui;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'package:permission_handler/permission_handler.dart'
    show openAppSettings;

import '../../../core/network/api_exception.dart';
import '../../usuarios_catalogo/application/session_controller.dart';
import '../../usuarios_catalogo/domain/producto.dart';
import '../../usuarios_catalogo/infrastructure/catalog_api.dart';
import '../application/vestidor_controller.dart';
import '../domain/garment_fit.dart';
import '../domain/garment_renderer.dart';
import '../domain/pose_projection.dart';
import '../domain/variante_probador.dart';
import '../infrastructure/vestidor_api.dart';
import 'prenda_overlay.dart';
import 'recurso_prenda_overlay.dart';

class VestidorScreen extends ConsumerStatefulWidget {
  const VestidorScreen({super.key, required this.slug, this.colorId});

  final String slug;
  final String? colorId;

  @override
  ConsumerState<VestidorScreen> createState() => _VestidorScreenState();
}

class _VestidorScreenState extends ConsumerState<VestidorScreen>
    with WidgetsBindingObserver {
  CameraController? _camara;
  PoseDetector? _detector;
  int _rotacion = 0;
  bool _procesando = false;
  bool _abriendoCamara = false;
  bool _enPrimerPlano = true;
  Future<void>? _apagandoCamara;
  int _fallosConsecutivos = 0;
  DateTime? _ultimaPose;
  bool _permisoDenegado = false;
  Producto? _producto;
  Variante? _variante;
  String? _errorProducto;
  RecursoVestidor? _recurso;
  ImageInfo? _imagenRecurso;
  String? _avisoRecurso;
  ImageStream? _flujoImagen;
  ImageStreamListener? _escuchaImagen;
  int _revisionProducto = 0;
  int _revisionRecurso = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // `empezarPreparacion()` actualiza un StateNotifier. Hacerlo durante el
    // primer build viola la regla de Riverpod y detenía el probador antes de
    // abrir la cámara. Se inicia cuando ya terminó de montarse la pantalla.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_iniciar());
    });
  }

  Future<void> _iniciar() async {
    await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    if (!mounted) return;
    _detector = PoseDetector(
      options: PoseDetectorOptions(
        model: PoseDetectionModel.base,
        mode: PoseDetectionMode.stream,
      ),
    );
    unawaited(_cargarProducto());
    await _encenderCamara();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _enPrimerPlano = true;
      unawaited(_encenderCamara());
    } else if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      _enPrimerPlano = false;
      unawaited(_apagarCamara());
    }
  }

  Future<void> _cargarProducto() async {
    final revision = ++_revisionProducto;
    try {
      final producto = await CatalogApi(
        ref.read(apiClientProvider),
      ).detalle(widget.slug);
      if (!mounted || revision != _revisionProducto) return;
      final variante = varianteParaProbador(producto, widget.colorId);
      setState(() {
        _producto = producto;
        _variante = variante;
        _errorProducto = null;
      });
      if (variante == null) {
        _revisionRecurso++;
        _quitarEscuchaImagen();
        setState(() {
          _recurso = null;
          _imagenRecurso = null;
          _avisoRecurso = widget.colorId == null
              ? 'Esta prenda no tiene variantes activas para probar.'
              : 'El color elegido ya no está disponible para el probador.';
        });
        return;
      }
      if (variante.colorId == null || variante.colorId!.isEmpty) {
        _revisionRecurso++;
        _quitarEscuchaImagen();
        setState(() {
          _recurso = null;
          _imagenRecurso = null;
          _avisoRecurso =
              'Esta variante no tiene un color identificable para cargar su imagen.';
        });
        return;
      }
      await _cargarRecurso(producto, variante);
    } on ApiException catch (error) {
      if (mounted && revision == _revisionProducto) {
        setState(() => _errorProducto = error.message);
      }
    } catch (_) {
      if (mounted && revision == _revisionProducto) {
        setState(() => _errorProducto = 'No pudimos cargar la prenda.');
      }
    }
  }

  /// Pide al backend el recorte transparente que corresponde exactamente a la
  /// prenda y al color elegidos. La cámara puede funcionar sin este recurso,
  /// con la silueta de respaldo, pero no se pretende que esa silueta sea la
  /// foto real de la ropa.
  Future<void> _cargarRecurso(Producto producto, Variante variante) async {
    final revision = ++_revisionRecurso;
    _quitarEscuchaImagen();
    if (mounted) {
      setState(() {
        _recurso = null;
        _imagenRecurso = null;
        _avisoRecurso = null;
      });
    }
    try {
      final recurso = await VestidorApi(
        ref.read(apiClientProvider),
      ).iniciar(productoId: producto.id, colorId: variante.colorId!);
      if (!mounted || revision != _revisionRecurso) return;
      if (recurso.assetUrl.isEmpty) {
        throw const ApiException('El recurso de probador está vacío.');
      }
      final flujo = NetworkImage(
        recurso.assetUrl,
      ).resolve(const ImageConfiguration());
      final escucha = ImageStreamListener(
        (info, _) {
          if (mounted && revision == _revisionRecurso) {
            setState(() {
              _recurso = recurso;
              _imagenRecurso = info;
              _avisoRecurso = null;
            });
          }
        },
        onError: (_, __) {
          if (mounted && revision == _revisionRecurso) {
            setState(() {
              _recurso = null;
              _imagenRecurso = null;
              _avisoRecurso =
                  'No pudimos descargar la imagen preparada de esta prenda.';
            });
          }
        },
      );
      _flujoImagen = flujo;
      _escuchaImagen = escucha;
      flujo.addListener(escucha);
    } on ApiException catch (error) {
      if (mounted && revision == _revisionRecurso) {
        setState(() {
          _recurso = null;
          _imagenRecurso = null;
          _avisoRecurso = error.message;
        });
      }
    } catch (_) {
      if (mounted && revision == _revisionRecurso) {
        setState(() {
          _recurso = null;
          _imagenRecurso = null;
          _avisoRecurso = 'No pudimos preparar la imagen de esta prenda.';
        });
      }
    }
  }

  void _quitarEscuchaImagen() {
    final flujo = _flujoImagen;
    final escucha = _escuchaImagen;
    if (flujo != null && escucha != null) flujo.removeListener(escucha);
    _flujoImagen = null;
    _escuchaImagen = null;
  }

  /// Vuelve a intentar desde cero: la primera vez que se niega el permiso,
  /// Android lo vuelve a preguntar si se reintenta; después hay que ir a los
  /// ajustes, y para eso está el botón que muestra la pantalla.
  Future<void> _reintentar() async {
    if (_abriendoCamara) return;
    await _apagarCamara();
    if (!mounted) return;
    _permisoDenegado = false;
    _fallosConsecutivos = 0;
    ref.read(vestidorProvider.notifier).reiniciar();
    unawaited(_cargarProducto());
    await _encenderCamara();
  }

  Future<void> _encenderCamara() async {
    if (!_enPrimerPlano || _camara != null || _abriendoCamara) return;
    _abriendoCamara = true;
    final controlador = ref.read(vestidorProvider.notifier);
    CameraController? camara;
    try {
      final apagando = _apagandoCamara;
      if (apagando != null) await apagando;
      if (!mounted || !_enPrimerPlano) return;
      controlador.empezarPreparacion();
      controlador.sacarPersona();
      final camaras = await availableCameras();
      if (camaras.isEmpty) {
        controlador.fallar('Este dispositivo no tiene cámara disponible.');
        return;
      }
      final frontal = camaras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => camaras.first,
      );
      _rotacion = frontal.sensorOrientation % 360;
      camara = CameraController(
        frontal,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: Platform.isAndroid
            ? ImageFormatGroup.nv21
            : ImageFormatGroup.bgra8888,
      );
      await camara.initialize();
      if (!mounted || !_enPrimerPlano) {
        await camara.dispose();
        return;
      }
      // El escenario y los puntos se calculan en vertical. Fijar la captura
      // evita que el video rote mientras el overlay mantiene su geometría.
      await camara.lockCaptureOrientation(DeviceOrientation.portraitUp);
      if (!mounted || !_enPrimerPlano) {
        await camara.dispose();
        return;
      }
      setState(() => _camara = camara);
      await camara.startImageStream(_procesarFotograma);
      if (!mounted || !_enPrimerPlano) {
        await _apagarCamara();
        return;
      }
      controlador.listaParaUsar();
    } on CameraException catch (error) {
      if (camara != null && _camara == camara) {
        await _apagarCamara();
      } else if (camara != null) {
        await camara.dispose();
      }
      if (!mounted || !_enPrimerPlano) return;
      // El permiso denegado es el caso más común y el único que la persona no
      // puede resolver reintentando: hay que mandarla a los ajustes.
      _permisoDenegado = const {
        'CameraAccessDenied',
        'CameraAccessDeniedWithoutPrompt',
        'CameraAccessRestricted',
      }.contains(error.code);
      controlador.fallar(
        _permisoDenegado
            ? 'FashionStore no tiene permiso para usar la cámara.'
            : 'No se pudo abrir la cámara (${error.code}).',
      );
    } catch (_) {
      if (camara != null && _camara == camara) {
        await _apagarCamara();
      } else if (camara != null) {
        await camara.dispose();
      }
      if (mounted && _enPrimerPlano) {
        controlador.fallar('No se pudo abrir la cámara.');
      }
    } finally {
      _abriendoCamara = false;
    }
  }

  Future<void> _apagarCamara() {
    final enCurso = _apagandoCamara;
    if (enCurso != null) return enCurso;
    final camara = _camara;
    if (camara == null) return Future<void>.value();
    _camara = null;
    _ultimaPose = null;
    if (mounted) {
      setState(() {});
      ref.read(vestidorProvider.notifier).sacarPersona();
    }
    final apagado = () async {
      try {
        if (camara.value.isStreamingImages) await camara.stopImageStream();
      } catch (_) {
        // La cámara puede haberse detenido al pasar a segundo plano.
      } finally {
        try {
          await camara.dispose();
        } catch (_) {
          // Android puede haber liberado la superficie antes del controlador.
        }
      }
    }();
    _apagandoCamara = apagado;
    unawaited(
      apagado.whenComplete(() {
        if (identical(_apagandoCamara, apagado)) _apagandoCamara = null;
      }),
    );
    return apagado;
  }

  ImageSize _tamanoDeCamara() {
    final tamanos = _camara?.value.previewSize;
    if (tamanos == null) return const ImageSize(ancho: 0, alto: 0);
    final girado = _rotacion % 180 != 0;
    return ImageSize(
      ancho: girado ? tamanos.height : tamanos.width,
      alto: girado ? tamanos.width : tamanos.height,
    );
  }

  Future<void> _procesarFotograma(CameraImage imagen) async {
    if (_procesando) return;
    final detector = _detector;
    if (detector == null || _camara == null || !_enPrimerPlano) return;
    _procesando = true;
    try {
      final entrada = _entradaDe(imagen);
      if (entrada == null) {
        _registrarFalloFotograma(
          'Formato ${imagen.format.raw}; ${imagen.planes.length} plano(s).',
        );
        return;
      }
      final poses = await detector.processImage(entrada);
      if (!mounted || !_enPrimerPlano || _camara == null) return;
      _fallosConsecutivos = 0;
      final controlador = ref.read(vestidorProvider.notifier);
      if (poses.isEmpty) {
        if (_ultimaPose != null &&
            DateTime.now().difference(_ultimaPose!).inMilliseconds >
                posePerdidaMs) {
          controlador.sacarPersona();
          _ultimaPose = null;
        }
        return;
      }
      _ultimaPose = DateTime.now();
      controlador.recibirPose(
        _crearCuerpo(poses.first.landmarks, imagen, entrada.metadata!.rotation),
      );
    } on PlatformException catch (error) {
      _registrarFalloFotograma('${error.code}: ${error.message ?? ''}');
    } catch (error) {
      _registrarFalloFotograma('$error');
    } finally {
      _procesando = false;
    }
  }

  void _registrarFalloFotograma(String detalle) {
    if (!mounted || !_enPrimerPlano || _camara == null) return;
    _fallosConsecutivos++;
    if (_fallosConsecutivos == 1) {
      debugPrint('Probador: no se pudo analizar el fotograma. $detalle');
    }
    if (_fallosConsecutivos == 10) {
      ref.read(vestidorProvider.notifier)
        ..sacarPersona()
        ..fallar(
          'La cámara abrió, pero no pudo detectar el cuerpo. Tocá Reintentar.',
        );
      unawaited(_apagarCamara());
    }
  }

  Uint8List _convertirYUV420ANV21(CameraImage image) {
    final width = image.width;
    final height = image.height;
    final yPlane = image.planes[0];
    final uPlane = image.planes[1];
    final vPlane = image.planes[2];

    final yBuffer = yPlane.bytes;
    final uBuffer = uPlane.bytes;
    final vBuffer = vPlane.bytes;

    final numPixels = width * height;
    final nv21 = Uint8List(numPixels + (numPixels ~/ 2));

    var idy = 0;
    for (var r = 0; r < height; r++) {
      final yRowOffset = r * yPlane.bytesPerRow;
      final yPixelStride = yPlane.bytesPerPixel ?? 1;
      for (var c = 0; c < width; c++) {
        nv21[idy++] = yBuffer[yRowOffset + c * yPixelStride];
      }
    }

    final uvHeight = height ~/ 2;
    final uvWidth = width ~/ 2;
    var iduv = numPixels;

    for (var r = 0; r < uvHeight; r++) {
      final uRowOffset = r * uPlane.bytesPerRow;
      final vRowOffset = r * vPlane.bytesPerRow;
      final uPixelStride = uPlane.bytesPerPixel ?? 1;
      final vPixelStride = vPlane.bytesPerPixel ?? 1;

      for (var c = 0; c < uvWidth; c++) {
        nv21[iduv++] = vBuffer[vRowOffset + c * vPixelStride];
        nv21[iduv++] = uBuffer[uRowOffset + c * uPixelStride];
      }
    }

    return nv21;
  }

  InputImage? _entradaDe(CameraImage imagen) {
    final formatoCamara = InputImageFormatValue.fromRawValue(imagen.format.raw);
    final esAndroid = Platform.isAndroid;
    Uint8List bytes;
    int bytesPerRow;
    InputImageFormat formatoFinal;

    if (esAndroid) {
      formatoFinal = InputImageFormat.nv21;
      if (imagen.planes.length == 3) {
        bytes = _convertirYUV420ANV21(imagen);
        bytesPerRow = imagen.width;
      } else if (imagen.planes.length == 1) {
        bytes = imagen.planes.first.bytes;
        bytesPerRow = imagen.planes.first.bytesPerRow;
      } else {
        return null;
      }
    } else if (Platform.isIOS &&
        imagen.planes.length == 1 &&
        formatoCamara == InputImageFormat.bgra8888) {
      formatoFinal = InputImageFormat.bgra8888;
      bytes = imagen.planes.first.bytes;
      bytesPerRow = imagen.planes.first.bytesPerRow;
    } else {
      return null;
    }

    final orientacion =
        _camara?.value.lockedCaptureOrientation ??
        _camara?.value.deviceOrientation ??
        DeviceOrientation.portraitUp;
    const giros = {
      DeviceOrientation.portraitUp: 0,
      DeviceOrientation.landscapeLeft: 90,
      DeviceOrientation.portraitDown: 180,
      DeviceOrientation.landscapeRight: 270,
    };
    final compensacion = giros[orientacion] ?? 0;
    final frontal =
        _camara?.description.lensDirection == CameraLensDirection.front;
    final giro = esAndroid
        ? (frontal
              ? (_rotacion + compensacion) % 360
              : (_rotacion - compensacion + 360) % 360)
        : _rotacion;
    return InputImage.fromBytes(
      bytes: bytes,
      metadata: InputImageMetadata(
        size: Size(imagen.width.toDouble(), imagen.height.toDouble()),
        rotation: _rotacionComoEntrada(giro),
        format: formatoFinal,
        bytesPerRow: bytesPerRow,
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

  /// Pasa el mapa de MLKit (índice → punto) a la lista de 33 que esperan los
  /// módulos del probador. MLKit ordena los landmarks exactamente igual que
  /// MediaPipe, así que `i` es el índice estándar.
  List<Landmark> _crearCuerpo(
    Map<PoseLandmarkType, PoseLandmark> mapa,
    CameraImage imagen,
    InputImageRotation giro,
  ) {
    // ML Kit devuelve píxeles del fotograma ya orientado; el renderer usa
    // coordenadas normalizadas. Mantener los 33 índices aunque falte un punto.
    final girado =
        giro == InputImageRotation.rotation90deg ||
        giro == InputImageRotation.rotation270deg;
    final ancho = (girado ? imagen.height : imagen.width).toDouble();
    final alto = (girado ? imagen.width : imagen.height).toDouble();
    final puntos = <Landmark>[];
    for (var i = 0; i < 33; i++) {
      final punto = mapa[PoseLandmarkType.values[i]];
      puntos.add(
        punto == null
            ? const Landmark(-1, -1, 0)
            : Landmark(punto.x / ancho, punto.y / alto, punto.likelihood),
      );
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
    _revisionProducto++;
    _revisionRecurso++;
    WidgetsBinding.instance.removeObserver(this);
    _enPrimerPlano = false;
    unawaited(SystemChrome.setPreferredOrientations(DeviceOrientation.values));
    final detector = _detector;
    if (detector != null) unawaited(detector.close());
    final camara = _camara;
    _camara = null;
    if (camara != null) {
      unawaited(() async {
        try {
          if (camara.value.isStreamingImages) await camara.stopImageStream();
        } catch (_) {
          // El flujo pudo detenerse durante la navegación.
        } finally {
          try {
            await camara.dispose();
          } catch (_) {
            // La superficie pudo liberarse durante la navegación.
          }
        }
      }());
    }
    _quitarEscuchaImagen();
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
          opciones: OpcionesDibujo(
            forma: _forma,
            color: colorGuiaDeVariante(_variante),
          ),
          reflejada:
              _camara?.description.lensDirection == CameraLensDirection.front,
          region: regionDesdeNombre(_recurso?.region) ?? _regionDe(_forma),
          producto: _producto,
          variante: _variante,
          errorProducto: _errorProducto,
          recurso: _recurso,
          imagenRecurso: _imagenRecurso?.image,
          avisoRecurso: _avisoRecurso,
          anchoPantalla: restricciones.maxWidth,
          altoPantalla: restricciones.maxHeight,
          permisoDenegado: _permisoDenegado,
          onReintentar: _reintentar,
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
    required this.reflejada,
    required this.region,
    required this.producto,
    required this.variante,
    required this.errorProducto,
    required this.recurso,
    required this.imagenRecurso,
    required this.avisoRecurso,
    required this.anchoPantalla,
    required this.altoPantalla,
    required this.permisoDenegado,
    required this.onReintentar,
  });

  final EstadoVestidor vestidor;
  final CameraController? camara;
  final ImageSize tamano;
  final OpcionesDibujo opciones;
  final bool reflejada;
  final RegionCuerpo region;
  final Producto? producto;
  final Variante? variante;
  final String? errorProducto;
  final RecursoVestidor? recurso;
  final ui.Image? imagenRecurso;
  final String? avisoRecurso;
  final double anchoPantalla;
  final double altoPantalla;
  final bool permisoDenegado;
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
      return ImageSize(ancho: anchoPantalla, alto: anchoPantalla / proporcion);
    }
    return ImageSize(ancho: altoPantalla * proporcion, alto: altoPantalla);
  }

  @override
  Widget build(BuildContext context) {
    final escenario = _escenario();
    if (camara == null) {
      return _Esperando(
        vestidor: vestidor,
        permisoDenegado: permisoDenegado,
        onReintentar: onReintentar,
      );
    }

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
                  // CameraPreview aplica la rotación y el espejo frontal del
                  // plugin. Otro flip aquí invertía solo el video y dejaba
                  // la prenda en el lado opuesto del cuerpo.
                  CameraPreview(camara!),
                  if (variante != null &&
                      vestidor.hayPose &&
                      imagenRecurso == null)
                    CustomPaint(painter: _painter(escenario)),
                  if (variante != null &&
                      vestidor.hayPose &&
                      imagenRecurso != null &&
                      recurso != null)
                    RecursoPrendaOverlay(
                      imagen: imagenRecurso!,
                      recurso: recurso!,
                      cuerpo: vestidor.cuerpo,
                      region: region,
                      caja: _cajaDe(escenario),
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
                _ErrorCamara(
                  mensaje: vestidor.error!,
                  onReintentar: onReintentar,
                )
              else
                _BarraInferior(
                  producto: producto,
                  variante: variante,
                  errorProducto: errorProducto,
                  hayPose: vestidor.hayPose,
                  avisoRecurso: avisoRecurso,
                  usaRecursoReal: imagenRecurso != null,
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
    reflejada: reflejada,
  );

  PrendaOverlayPainter _painter(ImageSize escenario) => PrendaOverlayPainter(
    cuerpo: vestidor.cuerpo,
    opciones: opciones,
    caja: _cajaDe(escenario),
  );
}

/// Lo que se ve mientras la cámara no está: o enciende, o falló.
///
/// Antes este widget decía siempre «La cámara no está disponible», porque el
/// mensaje real y el botón de reintentar vivían en la otra rama del `build`
/// —la que solo se dibuja **cuando la cámara sí funcionó**—. Quien se topaba
/// con un permiso denegado quedaba en una pantalla negra sin explicación y sin
/// salida.
class _Esperando extends StatelessWidget {
  const _Esperando({
    required this.vestidor,
    required this.permisoDenegado,
    required this.onReintentar,
  });

  final EstadoVestidor vestidor;
  final bool permisoDenegado;
  final VoidCallback onReintentar;

  @override
  Widget build(BuildContext context) {
    if (vestidor.preparando) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: Colors.white),
            SizedBox(height: 16),
            Text(
              'Encendiendo la cámara…',
              style: TextStyle(color: Colors.white70),
            ),
          ],
        ),
      );
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.videocam_off_outlined,
              size: 44,
              color: Colors.white54,
            ),
            const SizedBox(height: 14),
            Text(
              vestidor.error ?? 'La cámara no está disponible.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white),
            ),
            if (permisoDenegado) ...[
              const SizedBox(height: 8),
              const Text(
                'Activá el permiso de cámara para probarte la prenda.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ],
            const SizedBox(height: 18),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              alignment: WrapAlignment.center,
              children: [
                FilledButton.tonalIcon(
                  onPressed: onReintentar,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Reintentar'),
                ),
                if (permisoDenegado)
                  OutlinedButton.icon(
                    // Una vez negado «para siempre», Android ya no vuelve a
                    // preguntar: el único camino es la pantalla de ajustes.
                    onPressed: openAppSettings,
                    icon: const Icon(
                      Icons.settings_outlined,
                      color: Colors.white,
                    ),
                    label: const Text(
                      'Abrir ajustes',
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                TextButton(
                  onPressed: () => Navigator.of(context).maybePop(),
                  child: const Text(
                    'Volver',
                    style: TextStyle(color: Colors.white70),
                  ),
                ),
              ],
            ),
          ],
        ),
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
          Flexible(
            child: Text(guia.mensaje, style: TextStyle(color: color)),
          ),
        ],
      ),
    );
  }
}

class _BarraInferior extends StatelessWidget {
  const _BarraInferior({
    required this.producto,
    required this.variante,
    required this.errorProducto,
    required this.hayPose,
    required this.avisoRecurso,
    required this.usaRecursoReal,
  });

  final Producto? producto;
  final Variante? variante;
  final String? errorProducto;
  final bool hayPose;
  final String? avisoRecurso;
  final bool usaRecursoReal;

  @override
  Widget build(BuildContext context) {
    final nombre = producto?.nombre ?? '';
    final categoria = producto?.categoria ?? '';
    final leyenda = errorProducto != null
        ? 'No se pudo cargar la prenda: $errorProducto'
        : avisoRecurso != null
        ? variante == null
              ? avisoRecurso!
              : '$avisoRecurso Mostramos una guía de respaldo.'
        : usaRecursoReal
        ? (hayPose
              ? 'La imagen preparada te sigue al moverte.'
              : 'Parate de cuerpo entero frente a la cámara.')
        : 'Preparando la imagen de la prenda…';
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
          if (variante != null && variante!.color.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                children: [
                  if (tieneColorHexValido(variante))
                    Container(
                      width: 16,
                      height: 16,
                      decoration: BoxDecoration(
                        color: hexToColor(colorGuiaDeVariante(variante)),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white70),
                      ),
                    )
                  else
                    const Icon(
                      Icons.palette_outlined,
                      size: 16,
                      color: Colors.white70,
                    ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Color del catálogo: ${variante!.color}',
                      style: const TextStyle(color: Colors.white70),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 6),
          Text(
            leyenda,
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
          if (variante != null &&
              !tieneColorHexValido(variante) &&
              !usaRecursoReal)
            const Text(
              'La silueta gris solo indica forma; falta un color confiable para esta variante.',
              style: TextStyle(color: Colors.white70, fontSize: 12),
            ),
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
          FilledButton.tonal(
            onPressed: onReintentar,
            child: const Text('Reintentar'),
          ),
        ],
      ),
    );
  }
}
