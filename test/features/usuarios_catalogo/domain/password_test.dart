import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_marketplace_moda/features/usuarios_catalogo/domain/password.dart';

void main() {
  group('passwordError', () {
    test('acepta una contraseña que cumple todas las reglas', () {
      expect(passwordError('Abcdef1!xyz2'), isNull);
    });

    test('rechaza menos de 12 caracteres', () {
      expect(passwordError('Ab1!xy'), 'Usá entre 12 y 128 caracteres.');
    });

    test('rechaza más de 128 caracteres', () {
      final larga = 'Abcdef1!x' * 20; // 160 caracteres.
      expect(passwordError(larga), 'Usá entre 12 y 128 caracteres.');
    });

    test('exige mayúscula, minúscula, número y símbolo', () {
      expect(passwordError('abcdefghijkl'), contains('mayúscula'));
      expect(passwordError('ABCDEFGHIJKL'), contains('minúscula'));
      expect(passwordError('ABCDefghijkl'), contains('número'));
      expect(passwordError('ABCDefgh12jx'), contains('símbolo'));
    });

    test('rechaza la contraseña que incluye el nombre del correo', () {
      expect(passwordError('juan.ABC123!xy', email: 'juan@correo.com'),
          'La contraseña no debe contener el nombre de tu correo.');
    });

    test('ignora el arroba y el dominio al revisar el correo', () {
      // El local es `otra`; `delfin.ABC123!xy` no lo contiene.
      expect(passwordError('delfin.ABC123!x', email: 'otra@correo.com'), isNull);
    });
  });
}
