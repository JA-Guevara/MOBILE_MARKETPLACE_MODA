import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_marketplace_moda/features/operacion_offline/domain/catalogo_local.dart';
import 'package:mobile_marketplace_moda/features/operacion_offline/application/catalogo_offline_controller.dart';
import 'fixtures.dart';

void main() {
  final i = instantanea();
  final datos = DatosLocales(
    productos: i.productos,
    variantes: i.variantes,
    existencias: i.existencias.where((e) => e.sucursalId == 'b1').toList(),
  );
  test('avisa después de 24 horas y acepta reloj previo', () {
    final ahora = DateTime(2026, 10, 23, 15);
    expect(
      estaDesactualizado(ahora.subtract(const Duration(hours: 26)), ahora),
      true,
    );
    expect(
      estaDesactualizado(ahora.subtract(const Duration(hours: 23)), ahora),
      false,
    );
    expect(
      estaDesactualizado(ahora.add(const Duration(hours: 1)), ahora),
      false,
    );
  });
  test('parsea ejemplo, importes decimales y cinco variantes', () {
    expect(i.productos, hasLength(2));
    expect(i.variantes, hasLength(5));
    expect(i.productos.first.precioOferta, 289);
    expect(i.variantes[2].precio, 300);
    expect(i.clientes.first.documentoFinal, '123');
  });
  test('filtros cruzan talla y color en la misma variante activa', () {
    expect(
      filtrar(
        datos,
        const FiltrosOffline(soloOferta: true),
      ).map((v) => v.producto.id),
      ['p1'],
    );
    expect(
      filtrar(datos, const FiltrosOffline(talla: 'M', color: 'Azul')),
      isEmpty,
    );
    expect(
      filtrar(
        datos,
        const FiltrosOffline(talla: 'L'),
      ).map((v) => v.producto.id),
      ['p1'],
    );
    expect(
      filtrar(
        datos,
        const FiltrosOffline(precioMax: 100),
      ).map((v) => v.producto.id),
      ['p2'],
    );
    expect(
      filtrar(
        datos,
        const FiltrosOffline(texto: 'ALGODÓN'),
      ).map((v) => v.producto.id),
      ['p2'],
    );
  });
  test('suscripción suspendida o vencida bloquea escrituras locales', () {
    expect(puedeOperarOffline(usuarioOffline(estado: 'SUSPENDIDA')), false);
    expect(puedeOperarOffline(usuarioOffline(fin: '2020-01-01')), false);
    expect(puedeOperarOffline(usuarioOffline()), true);
  });
}
