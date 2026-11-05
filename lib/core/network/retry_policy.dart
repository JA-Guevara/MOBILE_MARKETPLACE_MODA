import 'dart:io';
import 'dart:math';

class RetryPolicy {
  RetryPolicy({DateTime Function()? ahora, double Function()? aleatorio})
      : ahora = ahora ?? DateTime.now,
        aleatorio = aleatorio ?? Random().nextDouble;

  final DateTime Function() ahora;
  final double Function() aleatorio;

  Duration esperaPara(int intento, String? retryAfter) {
    final seconds = int.tryParse(retryAfter?.trim() ?? '');
    if (seconds != null && seconds >= 0) return Duration(seconds: seconds);
    if (retryAfter != null) {
      try {
        final wait = HttpDate.parse(retryAfter).difference(ahora().toUtc());
        return wait.isNegative ? Duration.zero : wait;
      } on HttpException {
        // Sin una cabecera válida, aplicar el backoff local.
      }
    }
    final base = pow(2, intento.clamp(1, 9)).toDouble();
    return Duration(milliseconds: min(300000, (base * 1000 * (1 + aleatorio() * .2)).ceil()));
  }
}
