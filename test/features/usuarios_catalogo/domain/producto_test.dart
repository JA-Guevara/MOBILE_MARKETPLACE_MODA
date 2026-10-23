import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_marketplace_moda/features/usuarios_catalogo/domain/producto.dart';

/// Recorte real de `/catalog/products`, con los tipos tal como los manda el
/// backend: los precios viajan como **texto** (`"200.00"`) y las variantes
/// traen la talla y el color anidados.
Map<String, dynamic> _json({
  List<Map<String, dynamic>>? variantes,
  List<Map<String, dynamic>>? imagenes,
}) =>
    {
      'id': 'p1',
      'name': 'Polera POLO',
      'slug': 'polera-polo',
      'description': 'Poleras Polo',
      'brand': 'POLO',
      'gender': 'mujer',
      'base_price': '200.00',
      'is_featured': true,
      'category': {'id': 'c1', 'name': 'Poleras'},
      'season': {'id': 's1', 'name': 'verano'},
      'collection': {'id': 'k1', 'name': 'Casual'},
      'images': imagenes ??
          [
            {'url': 'https://x/segunda.jpg', 'is_primary': false},
            {'url': 'https://x/principal.jpg', 'is_primary': true},
          ],
      'variants': variantes ??
          [
            {
              'id': 'v1',
              'sku': 'SKU-1',
              'price_override': '123.00',
              'is_active': true,
              'size': {'id': 't1', 'code': 'XS', 'name': 'Extra pequeño'},
              'color': {'id': 'k1', 'name': 'Azul marino', 'hex_code': '#1E2A44'},
            },
            {
              'id': 'v2',
              'sku': 'SKU-2',
              'price_override': null,
              'is_active': true,
              'size': {'id': 't2', 'code': 'M', 'name': 'Mediano'},
              'color': {'id': 'k1', 'name': 'Azul marino', 'hex_code': '#1E2A44'},
            },
          ],
    };

void main() {
  group('Producto', () {
    test('lee los datos que la pantalla de detalle necesita', () {
      final producto = Producto.desdeJson(_json());

      expect(producto.nombre, 'Polera POLO');
      expect(producto.precioBase, 200);
      expect(producto.descripcion, 'Poleras Polo');
      expect(producto.genero, 'mujer');
      expect(producto.temporada, 'verano');
      expect(producto.coleccion, 'Casual');
      expect(producto.categoria, 'Poleras');
    });

    test('pone la imagen principal primero, aunque llegue segunda', () {
      final producto = Producto.desdeJson(_json());

      expect(producto.imagenes, [
        'https://x/principal.jpg',
        'https://x/segunda.jpg',
      ]);
      // La tarjeta del catálogo y el carrusel tienen que coincidir en cuál es
      // «la foto» de la prenda.
      expect(producto.imagenUrl, producto.imagenes.first);
    });

    test('descarta las imágenes sin url', () {
      final producto = Producto.desdeJson(_json(imagenes: [
        {'url': '', 'is_primary': true},
        {'is_primary': false},
        {'url': 'https://x/unica.jpg'},
      ]));

      expect(producto.imagenes, ['https://x/unica.jpg']);
    });

    test('sin imágenes no inventa una', () {
      final producto = Producto.desdeJson(_json(imagenes: []));

      expect(producto.imagenes, isEmpty);
      expect(producto.imagenUrl, isNull);
    });
  });

  group('Variante', () {
    test('lee talla, color, sku y el precio propio', () {
      final producto = Producto.desdeJson(_json());
      final primera = producto.variantes.first;

      expect(primera.id, 'v1');
      expect(primera.talla, 'Extra pequeño');
      expect(primera.codigoTalla, 'XS');
      expect(primera.color, 'Azul marino');
      expect(primera.hexColor, '#1E2A44');
      expect(primera.sku, 'SKU-1');
      expect(primera.precio, 123);
    });

    test('sin price_override vale el precio base de la prenda', () {
      final producto = Producto.desdeJson(_json());
      final segunda = producto.variantes[1];

      expect(segunda.precio, isNull);
      expect(segunda.precioFinal(producto.precioBase), 200);
    });

    test('con price_override manda el precio de la variante', () {
      final producto = Producto.desdeJson(_json());

      expect(producto.variantes.first.precioFinal(producto.precioBase), 123);
    });
  });

  group('selección de talla y color', () {
    test('lista tallas y colores sin repetir', () {
      final producto = Producto.desdeJson(_json());

      expect(producto.tallas, ['Extra pequeño', 'Mediano']);
      // Las dos variantes son del mismo color: tiene que aparecer una sola vez.
      expect(producto.colores, ['Azul marino']);
    });

    test('encuentra la variante de una combinación', () {
      final producto = Producto.desdeJson(_json());

      expect(producto.varianteDe('Mediano', 'Azul marino')?.id, 'v2');
    });

    test('una combinación que no existe devuelve null, no la primera', () {
      final producto = Producto.desdeJson(_json());

      expect(producto.varianteDe('Mediano', 'Rojo'), isNull);
    });

    test('las variantes dadas de baja no se pueden elegir', () {
      final producto = Producto.desdeJson(_json(variantes: [
        {
          'id': 'v9',
          'is_active': false,
          'size': {'code': 'L', 'name': 'Grande'},
          'color': {'name': 'Negro'},
        },
      ]));

      expect(producto.variantesDisponibles, isEmpty);
      expect(producto.tallas, isEmpty);
      expect(producto.varianteDe('Grande', 'Negro'), isNull);
    });
  });
}
