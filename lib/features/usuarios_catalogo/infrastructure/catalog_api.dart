import '../../../core/network/api_client.dart';
import '../../../shared/models/api_response.dart';
import '../domain/producto.dart';

/// Llamadas al catálogo público. Equivale a `catalog.service.ts` de la web más
/// la parte de recomendaciones de `commerce.service.ts`.
class CatalogApi {
  const CatalogApi(this._api);

  final ApiClient _api;

  Future<Page<Producto>> productos({
    int page = 1,
    int pageSize = 12,
    String? search,
    String? categoryId,
    String? brand,
    String? minPrice,
    String? maxPrice,
    bool destacadas = false,
  }) async {
    final json = await _api.get<Map<String, dynamic>>(
      '/catalog/products',
      query: {
        'page': page,
        'page_size': pageSize,
        if (search != null && search.isNotEmpty) 'search': search,
        if (categoryId != null && categoryId.isNotEmpty) 'category_id': categoryId,
        if (brand != null && brand.isNotEmpty) 'brand': brand,
        if (minPrice != null && minPrice.isNotEmpty) 'min_price': minPrice,
        if (maxPrice != null && maxPrice.isNotEmpty) 'max_price': maxPrice,
        if (destacadas) 'featured': true,
      },
    );
    return Page.from(json, (fila) => Producto.desdeJson(fila));
  }

  Future<List<Referencia>> referencias(String recurso) async {
    final filas = await _api.get<List<dynamic>>('/catalog/$recurso');
    return filas
        .map((fila) => Referencia.desdeJson(fila as Map<String, dynamic>))
        .toList();
  }

  /// Sección opcional: si falla, el catálogo simplemente no la muestra.
  Future<List<Recomendado>> recomendaciones() async {
    final filas = await _api.get<List<dynamic>>('/commerce/recommendations');
    return filas
        .map((fila) => Recomendado.desdeJson(fila as Map<String, dynamic>))
        .toList();
  }
}