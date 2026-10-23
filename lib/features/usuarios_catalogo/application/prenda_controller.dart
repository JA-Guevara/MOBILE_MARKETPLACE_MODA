import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../ventas_pagos/application/carrito_controller.dart';
import '../../ventas_pagos/application/commerce_providers.dart';
import '../../ventas_pagos/infrastructure/commerce_api.dart';
import '../domain/producto.dart';
import '../infrastructure/catalog_api.dart';
import 'session_controller.dart';

/// Lo que la pantalla de una prenda necesita saber para dibujarse.
class EstadoPrenda {
  const EstadoPrenda({
    this.producto,
    this.cargando = true,
    this.error,
    this.talla = '',
    this.color = '',
    this.imagen = 0,
    this.favorito = false,
    this.ocupado = false,
    this.mensaje,
    this.errorAccion,
  });

  final Producto? producto;
  final bool cargando;

  /// Falló la carga de la prenda: no hay nada que mostrar.
  final String? error;

  final String talla;
  final String color;

  /// Índice de la foto que se está viendo.
  final int imagen;

  final bool favorito;

  /// Hay una acción en vuelo (agregar al carrito, marcar favorito).
  final bool ocupado;

  /// Resultado de la última acción, para avisar sin sacar a nadie de la
  /// pantalla. `errorAccion` no borra la prenda; `error` sí la reemplaza.
  final String? mensaje;
  final String? errorAccion;

  /// La variante que corresponde a la talla y el color elegidos. `null`
  /// significa que esa combinación no existe.
  Variante? get variante => producto?.varianteDe(talla, color);

  /// Precio de la variante elegida, o el base mientras no haya una.
  num get precio =>
      variante?.precioFinal(producto?.precioBase ?? 0) ??
      producto?.precioBase ??
      0;

  bool get sePuedeComprar => variante != null && !ocupado;

  EstadoPrenda copyWith({
    Producto? producto,
    bool? cargando,
    String? error,
    String? talla,
    String? color,
    int? imagen,
    bool? favorito,
    bool? ocupado,
    String? mensaje,
    String? errorAccion,
    bool limpiarAvisos = false,
    bool limpiarError = false,
  }) => EstadoPrenda(
    producto: producto ?? this.producto,
    cargando: cargando ?? this.cargando,
    error: limpiarError ? null : (error ?? this.error),
    talla: talla ?? this.talla,
    color: color ?? this.color,
    imagen: imagen ?? this.imagen,
    favorito: favorito ?? this.favorito,
    ocupado: ocupado ?? this.ocupado,
    mensaje: limpiarAvisos ? null : (mensaje ?? this.mensaje),
    errorAccion: limpiarAvisos ? null : (errorAccion ?? this.errorAccion),
  );
}

/// Dueño de la pantalla de una prenda: carga, selección y acciones.
///
/// Equivale a `product-page.component.ts` de la web. Las tres acciones que
/// exigen cuenta (carrito, favorito, reservar) **no** mandan a login desde
/// acá: devuelven `false` y la pantalla decide, que es la que conoce el
/// `context` y a dónde hay que volver después de entrar.
class PrendaController extends StateNotifier<EstadoPrenda> {
  PrendaController({
    required CatalogApi catalogo,
    required CommerceApi comercio,
    required bool Function() haySesion,
    Future<void> Function()? alActualizarCarrito,
  }) : _catalogo = catalogo,
       _comercio = comercio,
       _haySesion = haySesion,
       _alActualizarCarrito = alActualizarCarrito,
       super(const EstadoPrenda());

  final CatalogApi _catalogo;
  final CommerceApi _comercio;
  final bool Function() _haySesion;
  final Future<void> Function()? _alActualizarCarrito;

  Future<void> cargar(String slug) async {
    state = state.copyWith(
      cargando: true,
      limpiarError: true,
      limpiarAvisos: true,
    );
    try {
      final producto = await _catalogo.detalle(slug);
      final primera = producto.variantesDisponibles.isEmpty
          ? null
          : producto.variantesDisponibles.first;
      state = state.copyWith(
        producto: producto,
        cargando: false,
        // Se preselecciona la primera variante disponible: obligar a elegir
        // talla y color antes de ver un precio esconde justo el dato que la
        // persona vino a mirar.
        talla: primera?.talla ?? '',
        color: primera?.color ?? '',
        imagen: 0,
      );
      await _leerFavorito(producto.id);
    } on ApiException catch (error) {
      state = state.copyWith(cargando: false, error: error.message);
    }
  }

  /// El corazón arranca apagado y se enciende si el backend dice que ya estaba.
  /// Sin sesión no se pregunta: sería un 401 seguro en cada prenda abierta.
  Future<void> _leerFavorito(String productoId) async {
    if (!_haySesion()) return;
    try {
      final estado = await _comercio.estadoFavorito(productoId);
      state = state.copyWith(favorito: estado.isFavorite);
    } on ApiException {
      // Un favorito que no se pudo leer no rompe la prenda: queda apagado.
    }
  }

  void elegirTalla(String talla) =>
      state = state.copyWith(talla: talla, limpiarAvisos: true);

  void elegirColor(String color) =>
      state = state.copyWith(color: color, limpiarAvisos: true);

  void verImagen(int indice) {
    final total = state.producto?.imagenes.length ?? 0;
    if (total == 0) return;
    // Da la vuelta en los extremos: en un teléfono se pasa de foto con el
    // pulgar y frenar en la última se siente como que la app se colgó.
    state = state.copyWith(imagen: (indice % total + total) % total);
  }

  /// Agrega una unidad de la variante elegida al carrito.
  ///
  /// Devuelve `false` si hace falta iniciar sesión, para que la pantalla mande
  /// al login con la ruta de vuelta.
  Future<bool> agregarAlCarrito() async {
    final variante = state.variante;
    if (variante == null || state.ocupado) return true;
    if (!_haySesion()) return false;
    state = state.copyWith(ocupado: true, limpiarAvisos: true);
    try {
      await _comercio.agregarUno(variante.id);
      // El carrito vive en una pestaña conservada por StatefulShellRoute. Si
      // ya se abrió antes, su initState no vuelve a correr al regresar.
      try {
        await _alActualizarCarrito?.call();
      } catch (_) {
        // El servidor ya guardó la prenda: una recarga visual fallida no debe
        // convertir la operación confirmada en un falso rechazo.
      }
      state = state.copyWith(
        ocupado: false,
        mensaje: 'Agregamos la prenda a tu carrito.',
      );
    } on ApiException catch (error) {
      state = state.copyWith(ocupado: false, errorAccion: error.message);
    } catch (_) {
      state = state.copyWith(
        ocupado: false,
        errorAccion: 'No pudimos agregar la prenda. Intentá nuevamente.',
      );
    }
    return true;
  }

  /// Marca o desmarca la prenda como favorita. Mismo contrato que el carrito.
  Future<bool> alternarFavorito() async {
    final producto = state.producto;
    if (producto == null || state.ocupado) return true;
    if (!_haySesion()) return false;
    final marcada = state.favorito;
    state = state.copyWith(ocupado: true, limpiarAvisos: true);
    try {
      if (marcada) {
        await _comercio.quitarFavorito(producto.id);
      } else {
        await _comercio.guardarFavorito(producto.id);
      }
      state = state.copyWith(
        ocupado: false,
        favorito: !marcada,
        mensaje: marcada
            ? 'La quitamos de tus favoritos.'
            : 'La guardamos en favoritos y te avisamos si vuelve el stock o baja el precio.',
      );
    } on ApiException catch (error) {
      state = state.copyWith(ocupado: false, errorAccion: error.message);
    }
    return true;
  }
}

/// Una prenda por slug. `autoDispose` porque al salir de la pantalla el estado
/// no sirve más, y `family` porque cada prenda tiene el suyo: sin eso, abrir
/// una segunda prenda mostraría por un instante la talla elegida en la anterior.
final prendaProvider = StateNotifierProvider.autoDispose
    .family<PrendaController, EstadoPrenda, String>((ref, slug) {
      final controlador = PrendaController(
        catalogo: CatalogApi(ref.watch(apiClientProvider)),
        comercio: ref.watch(commerceApiProvider),
        haySesion: () => ref.read(sessionProvider).autenticado,
        alActualizarCarrito: () => ref.read(carritoProvider.notifier).cargar(),
      );
      controlador.cargar(slug);
      return controlador;
    });
