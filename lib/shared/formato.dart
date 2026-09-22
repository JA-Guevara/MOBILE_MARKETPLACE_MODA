import 'package:intl/intl.dart';

/// Formato de montos y fechas en español boliviano, igual que la web
/// (`Intl.NumberFormat('es-BO', …)` con `number:'1.2-2'`).
class Formato {
  const Formato._();

  static final NumberFormat _moneda = NumberFormat.currency(
    locale: 'es-BO',
    symbol: 'Bs ',
    decimalDigits: 2,
  );

  static final DateFormat _fechaHora = DateFormat("dd/MM/yyyy HH:mm", 'es');
  static final DateFormat _fecha = DateFormat('dd/MM/yyyy', 'es');
  static final DateFormat _fechaCorta = DateFormat('dd/MM', 'es');

  /// `1234.5` → `Bs 1.234,50`.
  static String moneda(num valor) => _moneda.format(valor);

  /// Numérico simple con dos decimales, sin símbolo.
  static String numero(double valor) => valor.toStringAsFixed(2);

  /// ISO `2026-09-21T14:30:00…` → `21/09/2026 14:30`.
  static String fechaHora(String iso) {
    final fecha = DateTime.tryParse(iso);
    if (fecha == null) return iso;
    return _fechaHora.format(fecha.toLocal());
  }

  /// ISO → `21/09/2026`.
  static String fecha(String iso) {
    final fecha = DateTime.tryParse(iso);
    if (fecha == null) return iso;
    return _fecha.format(fecha.toLocal());
  }

  /// Quita tildes y pasa a minúsculas para buscar sin tropezarse con el acento.
  static String normalizar(String texto) =>
      texto.toLowerCase().replaceAll(RegExp(r'[áàäâ]'), 'a').replaceAll(RegExp(r'[éèëê]'), 'e').replaceAll(RegExp(r'[íìïî]'), 'i').replaceAll(RegExp(r'[óòöô]'), 'o').replaceAll(RegExp(r'[úùüû]'), 'u').replaceAll('ñ', 'n');
}
