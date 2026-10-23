import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_marketplace_moda/features/reservas_vestidor/domain/variante_probador.dart';
import 'package:mobile_marketplace_moda/features/usuarios_catalogo/domain/producto.dart';

const producto = Producto(
  id: 'p',
  nombre: 'Remera',
  slug: 'remera',
  precioBase: 100,
  categoria: 'Superiores',
  variantes: [
    Variante(
      id: 'inactiva',
      talla: 'M',
      color: 'Negro',
      colorId: 'negro',
      hexColor: '#000000',
      activa: false,
    ),
    Variante(id: 'sin-id', talla: 'M', color: 'Sin id'),
    Variante(
      id: 'roja',
      talla: 'M',
      color: 'Rojo',
      colorId: 'rojo',
      hexColor: '#C23',
    ),
    Variante(
      id: 'gris',
      talla: 'L',
      color: 'Gris',
      colorId: 'gris',
      hexColor: '#888888',
    ),
  ],
);

void main() {
  test('usa la variante activa solicitada y no sustituye un color agotado', () {
    expect(varianteParaProbador(producto, 'rojo')?.id, 'roja');
    expect(varianteParaProbador(producto, 'negro'), isNull);
    expect(varianteParaProbador(producto, 'inexistente'), isNull);
  });

  test(
    'sin selección elige un color con id para pedir el recurso correcto',
    () {
      expect(varianteParaProbador(producto, null)?.id, 'roja');
    },
  );

  test('usa el hexadecimal del catálogo, incluso cuando el gris es real', () {
    final roja = varianteParaProbador(producto, 'rojo');
    final gris = varianteParaProbador(producto, 'gris');
    expect(colorGuiaDeVariante(roja), '#C23');
    expect(tieneColorHexValido(gris), isTrue);
    expect(colorGuiaDeVariante(gris), '#888888');
  });

  test('sin hexadecimal válido avisa con una guía neutra', () {
    final sinId = producto.variantesDisponibles.first;
    expect(tieneColorHexValido(sinId), isFalse);
    expect(colorGuiaDeVariante(sinId), '#888888');
  });
}
