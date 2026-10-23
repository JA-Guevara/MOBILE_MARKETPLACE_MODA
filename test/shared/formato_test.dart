import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_marketplace_moda/shared/formato.dart';

/// `Formato` no lo usaba todavía ninguna pantalla, así que sus dos fallos no
/// se veían: las fechas lanzaban `LocaleDataException` porque pedían el locale
/// `'es'` sin que nadie llamara a `initializeDateFormatting`, y el monto salía
/// con el símbolo detrás (`1.234,50 Bs`) cuando la web lo escribe delante.
/// Las pantallas pendientes —carrito, pedidos, devoluciones— van a mostrar
/// montos y fechas en cuanto se construyan; estas pruebas las esperan.
void main() {
  group('moneda', () {
    test('escribe el símbolo delante, como la web', () {
      expect(Formato.moneda(1234.5), 'Bs 1.234,50');
    });

    test('usa punto para los miles y coma para los decimales', () {
      expect(Formato.moneda(0), 'Bs 0,00');
      expect(Formato.moneda(7), 'Bs 7,00');
      expect(Formato.moneda(1000000), 'Bs 1.000.000,00');
    });

    test('redondea a dos decimales', () {
      expect(Formato.moneda(19.999), 'Bs 20,00');
    });
  });

  group('fechas', () {
    test('no explota por falta del locale de fechas', () {
      expect(() => Formato.fecha('2026-09-21T14:30:00Z'), returnsNormally);
      expect(() => Formato.fechaHora('2026-09-21T14:30:00Z'), returnsNormally);
    });

    test('un ISO se muestra en día/mes/año', () {
      // Se compara contra la hora local del equipo: el backend responde en UTC
      // y la app muestra la hora de quien mira.
      final local = DateTime.parse('2026-09-21T14:30:00Z').toLocal();
      final dia = local.day.toString().padLeft(2, '0');
      final mes = local.month.toString().padLeft(2, '0');
      expect(Formato.fecha('2026-09-21T14:30:00Z'), '$dia/$mes/${local.year}');
    });

    test('un texto que no es fecha se devuelve tal cual', () {
      expect(Formato.fecha('sin fecha'), 'sin fecha');
      expect(Formato.fechaHora(''), '');
    });
  });

  group('normalizar', () {
    test('saca tildes y pasa a minúsculas para poder buscar', () {
      expect(Formato.normalizar('Camisa Añejo Ürü'), 'camisa anejo uru');
    });
  });
}
