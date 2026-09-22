// El estado del vestidor solo guarda lo que la vista necesita: la última pose
// enderezada y el ciclo de vida de la cámara. Solito no toca la cámara ni MLKit.
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_marketplace_moda/features/reservas_vestidor/application/vestidor_controller.dart';
import 'package:mobile_marketplace_moda/features/reservas_vestidor/domain/pose_projection.dart';

Landmark punto(int i) => Landmark(0.1 + i * 0.01, 0.4, 0.9);

void main() {
  group('VestidorController', () {
    test('arranca preparando la cámara, sin pose ni error', () {
      final c = VestidorController();
      expect(c.state.preparando, isTrue);
      expect(c.state.hayPose, isFalse);
      expect(c.state.error, isNull);
    });

    test('la cámara pasa de «preparando» a lista', () {
      final c = VestidorController();
      c.listaParaUsar();
      expect(c.state.preparando, isFalse);
      expect(c.state.error, isNull);
    });

    test('recibirPose guarda el cuerpo y limpia errores y ya no prepara', () {
      final c = VestidorController()
        ..fallar('vaya uno a saber');
      final pose = List.generate(33, punto);
      c.recibirPose(pose);
      expect(c.state.hayPose, isTrue);
      expect(c.state.cuerpo, same(pose));
      expect(c.state.preparando, isFalse);
      expect(c.state.error, isNull);
    });

    test('sacarPersona baja la prenda', () {
      final c = VestidorController()
        ..recibirPose(List.generate(33, punto));
      c.sacarPersona();
      expect(c.state.hayPose, isFalse);
    });

    test('fallar guarda el mensaje y reiniciar vuelve a preparar', () {
      final c = VestidorController()..fallar('sin permiso de cámara');
      expect(c.state.error, 'sin permiso de cámara');
      expect(c.state.preparando, isFalse);
      c.reiniciar();
      expect(c.state.error, isNull);
      expect(c.state.preparando, isTrue);
    });

    test('no reemplaza un error existente salvo que se indique', () {
      final c = VestidorController()
        ..fallar('primero');
      c.recibirPose(const [Landmark(0.1, 0.2)]);
      expect(c.state.error, isNull); // recibirPose limpia el error a propósito
    });
  });
}
