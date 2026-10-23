import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_marketplace_moda/app/theme.dart';

/// El tema fijaba `minimumSize: Size.fromHeight(48)`, que es
/// `Size(double.infinity, 48)`: cualquier `FilledButton` dentro de una `Row`
/// (ancho sin límite) pedía ancho infinito y rompía el layout de la pantalla
/// entera. Estas pruebas dejan clavado el caso y el ancho completo que las
/// pantallas de formulario sí necesitan.
void main() {
  Future<void> montar(WidgetTester tester, Widget hijo) => tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.claro,
          home: Scaffold(body: hijo),
        ),
      );

  testWidgets('un FilledButton dentro de una Row no pide ancho infinito',
      (tester) async {
    await montar(
      tester,
      Row(
        children: [
          FilledButton.tonalIcon(
            onPressed: () {},
            icon: const Icon(Icons.edit),
            label: const Text('Editar mis datos'),
          ),
        ],
      ),
    );

    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.byType(FilledButton)).width, lessThan(1000));
  });

  testWidgets('en una lista vertical el botón sigue ocupando todo el ancho',
      (tester) async {
    await montar(
      tester,
      ListView(
        children: [
          FilledButton(onPressed: () {}, child: const Text('Entrar')),
        ],
      ),
    );

    expect(tester.takeException(), isNull);
    final ancho = tester.getSize(find.byType(FilledButton)).width;
    expect(ancho, tester.view.physicalSize.width / tester.view.devicePixelRatio);
  });

  testWidgets('el alto mínimo de 48 se mantiene', (tester) async {
    await montar(
      tester,
      Center(child: FilledButton(onPressed: () {}, child: const Text('Ok'))),
    );

    expect(tester.getSize(find.byType(FilledButton)).height,
        greaterThanOrEqualTo(48));
  });
}
