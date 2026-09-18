import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../shared/models/api_response.dart';
import '../domain/producto.dart';
import '../infrastructure/catalog_api.dart';
import '../../auth/application/session_controller.dart';

/// Filtros que la persona elige en el catálogo.
class FiltrosCatalogo {
  const FiltrosCatalogo({
    this.busqueda = '',
    this.categoriaId = '',
    this.marca = '',
    this.minPrecio = '',
    this.maxPrecio = '',
    this.soloDestacadas = false,
  });

  final String busqueda;
  final String categoriaId;
  final String marca;
  final String minPrecio;
  final String maxPrecio;
  final bool soloDestacadas;

  FiltrosCatalogo copyWith({
    String? busqueda,
    String? categoriaId,
    String? marca,
    String? minPrecio,
    String? maxPrecio,
    bool? soloDestacadas,
  }) =>
      FiltrosCatalogo(
        busqueda: busqueda ?? this.busqueda,
        categoriaId: categoriaId ?? this.categoriaId,
        marca: marca ?? this.marca,
        minPrecio: minPrecio ?? this.minPrecio,
        maxPrecio: maxPrecio ?? this.maxPrecio,
        soloDestacadas: soloDestacadas ?? this.soloDestacadas,
      );
}

/// Estado del catálogo: lista acumulada, paginación y filtros.
class EstadoCatalogo {
  const EstadoCatalogo({
    this.productos = const [],
    this.categorias = const [],
    this.recomendados = const [],
    this.filtros = const FiltrosCatalogo(),
    this.pagina = 1,
    this.paginas = 1,
    this.total = 0,
    this.cargando = true,
    this.cargandoMas = false,
    this.error,
  });

  final List<Producto> productos;
  final List<Referencia> categorias;
  final List<Recomendado> recomendados;
  final FiltrosCatalogo filtros;
  final int pagina;
  final int paginas;
  final int total;
  final bool cargando;
  final bool cargandoMas;
  final String? error;

  bool get hayMas => pagina < paginas;

  EstadoCatalogo copyWith({
    List<Producto>? productos,
    List<Referencia>? categorias,
    List<Recomendado>? recomendados,
    FiltrosCatalogo? filtros,
    int? pagina,
    int? paginas,
    int? total,
    bool? cargando,
    bool? cargandoMas,
    String? error,
    bool limpiarError = false,
  }) =>
      EstadoCatalogo(
        productos: productos ?? this.productos,
        categorias: categorias ?? this.categorias,
        recomendados: recomendados ?? this.recomendados,
        filtros: filtros ?? this.filtros,
        pagina: pagina ?? this.pagina,
        paginas: paginas ?? this.paginas,
        total: total ?? this.total,
        cargando: cargando ?? this.cargando,
        cargandoMas: cargandoMas ?? this.cargandoMas,
        error: limpiarError ? null : (error ?? this.error),
      );
}

/// Dueño del catálogo (la portada de la app). Carga por páginas a medida que se
/// hace scroll, como pide la guía del móvil.
class CatalogController extends StateNotifier<EstadoCatalogo> {
  CatalogController(this._api) : super(const EstadoCatalogo());

  final CatalogApi _api;
  static const _tamanoPagina = 12;

  Future<void> iniciar() async {
    await Future.wait([cargarReferencias(), cargarRecomendaciones()]);
    await cargarInicial();
  }

  Future<void> cargarReferencias() async {
    try {
      final categorias = await _api.referencias('categories');
      state = state.copyWith(categorias: categorias);
    } on ApiException {
      // Los filtros son opcionales: si fallan, el catálogo igual se ve.
    }
  }

  Future<void> cargarRecomendaciones() async {
    try {
      final recomendados = await _api.recomendaciones();
      state = state.copyWith(recomendados: recomendados);
    } on ApiException {
      // Sección opcional.
    }
  }

  Future<void> cargarInicial() async {
    state = state.copyWith(cargando: true, limpiarError: true);
    try {
      final pagina = await _pedir(1);
      state = state.copyWith(
        productos: pagina.items,
        pagina: pagina.page,
        paginas: pagina.pages,
        total: pagina.total,
        cargando: false,
      );
    } on ApiException catch (error) {
      state = state.copyWith(cargando: false, error: error.message);
    }
  }

  Future<void> cargarMas() async {
    if (state.cargando || state.cargandoMas || !state.hayMas) return;
    state = state.copyWith(cargandoMas: true);
    try {
      final siguiente = await _pedir(state.pagina + 1);
      state = state.copyWith(
        productos: [...state.productos, ...siguiente.items],
        pagina: siguiente.page,
        paginas: siguiente.pages,
        total: siguiente.total,
        cargandoMas: false,
      );
    } on ApiException catch (error) {
      state = state.copyWith(cargandoMas: false, error: error.message);
    }
  }

  Future<void> aplicarFiltros(FiltrosCatalogo filtros) async {
    state = state.copyWith(filtros: filtros);
    await cargarInicial();
  }

  Future<void> reintentar() => cargarInicial();

  Future<Page<Producto>> _pedir(int page) => _api.productos(
        page: page,
        pageSize: _tamanoPagina,
        search: state.filtros.busqueda,
        categoryId: state.filtros.categoriaId,
        brand: state.filtros.marca,
        minPrice: state.filtros.minPrecio,
        maxPrice: state.filtros.maxPrecio,
        destacadas: state.filtros.soloDestacadas,
      );
}

final StateNotifierProvider<CatalogController, EstadoCatalogo> catalogProvider =
    StateNotifierProvider<CatalogController, EstadoCatalogo>(
        (ref) => CatalogController(CatalogApi(ref.watch(apiClientProvider))));