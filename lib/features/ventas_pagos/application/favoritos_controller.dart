import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../domain/commerce_models.dart';
import '../infrastructure/commerce_api.dart';
import 'commerce_providers.dart';

class EstadoFavoritos {
  const EstadoFavoritos({
    this.favoritos = const [],
    this.cargando = true,
    this.ocupado = false,
    this.error,
  });

  final List<Favorito> favoritos;
  final bool cargando;
  final bool ocupado;
  final String? error;

  EstadoFavoritos copyWith({
    List<Favorito>? favoritos,
    bool? cargando,
    bool? ocupado,
    String? error,
    bool limpiarError = false,
  }) =>
      EstadoFavoritos(
        favoritos: favoritos ?? this.favoritos,
        cargando: cargando ?? this.cargando,
        ocupado: ocupado ?? this.ocupado,
        error: limpiarError ? null : (error ?? this.error),
      );
}

/// «Mis favoritos» (`favorites-page.component.ts`).
class FavoritosController extends StateNotifier<EstadoFavoritos> {
  FavoritosController(this._comercio) : super(const EstadoFavoritos());

  final CommerceApi _comercio;

  Future<void> cargar() async {
    state = state.copyWith(cargando: true, limpiarError: true);
    try {
      state = state.copyWith(favoritos: await _comercio.favoritos(), cargando: false);
    } on ApiException catch (error) {
      state = state.copyWith(cargando: false, error: error.message);
    }
  }

  Future<void> quitar(Favorito favorito) async {
    if (state.ocupado) return;
    state = state.copyWith(ocupado: true, limpiarError: true);
    try {
      await _comercio.quitarFavorito(favorito.productId);
      // Se saca de la lista en vez de releerla entera: la respuesta del
      // backend ya confirmó el borrado y recargar haría parpadear la pantalla.
      state = state.copyWith(
        favoritos: state.favoritos.where((f) => f.id != favorito.id).toList(),
        ocupado: false,
      );
    } on ApiException catch (error) {
      state = state.copyWith(ocupado: false, error: error.message);
    }
  }

  /// Cambia los avisos de stock y de precio de un favorito.
  Future<void> cambiarAvisos(
    Favorito favorito, {
    bool? stock,
    bool? precio,
  }) async {
    if (state.ocupado) return;
    state = state.copyWith(ocupado: true, limpiarError: true);
    try {
      await _comercio.guardarFavorito(
        favorito.productId,
        stockAlert: stock ?? favorito.stockAlert,
        priceAlert: precio ?? favorito.priceAlert,
      );
      await cargar();
      state = state.copyWith(ocupado: false);
    } on ApiException catch (error) {
      state = state.copyWith(ocupado: false, error: error.message);
    }
  }
}

final StateNotifierProvider<FavoritosController, EstadoFavoritos> favoritosProvider =
    StateNotifierProvider<FavoritosController, EstadoFavoritos>(
        (ref) => FavoritosController(ref.watch(commerceApiProvider)));
