import 'package:flutter/material.dart';

class AlertaPagoDialog extends StatelessWidget {
  const AlertaPagoDialog({
    super.key,
    required this.numeroPedido,
    required this.total,
    required this.metodoPago,
    this.email,
    this.vuelto,
    this.esOffline = false,
    this.onVerDetalle,
  });

  final String numeroPedido;
  final double total;
  final String metodoPago;
  final String? email;
  final double? vuelto;
  final bool esOffline;
  final VoidCallback? onVerDetalle;

  static Future<void> mostrar({
    required BuildContext context,
    required String numeroPedido,
    required double total,
    required String metodoPago,
    String? email,
    double? vuelto,
    bool esOffline = false,
    VoidCallback? onVerDetalle,
  }) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertaPagoDialog(
        numeroPedido: numeroPedido,
        total: total,
        metodoPago: metodoPago,
        email: email,
        vuelto: vuelto,
        esOffline: esOffline,
        onVerDetalle: onVerDetalle,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      elevation: 8,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: const Color(0xFFDCFCE7),
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFF86EFAC), width: 2),
              ),
              child: const Icon(
                Icons.check_circle_rounded,
                color: Color(0xFF16A34A),
                size: 40,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              esOffline ? '¡Venta Registrada!' : '¡Operación Exitosa!',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              esOffline
                  ? 'Comprobante Provisional: #$numeroPedido'
                  : 'Pedido Confirmado: #$numeroPedido',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 18),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: colorScheme.outlineVariant),
              ),
              child: Column(
                children: [
                  Text(
                    'TOTAL COBRADO',
                    style: theme.textTheme.labelSmall?.copyWith(
                      letterSpacing: 1.2,
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Bs ${total.toStringAsFixed(2)}',
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: colorScheme.primary,
                    ),
                  ),
                  if (vuelto != null && vuelto! > 0) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFFDCFCE7),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'Vuelto entregado: Bs ${vuelto!.toStringAsFixed(2)}',
                        style: const TextStyle(
                          color: Color(0xFF166534),
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                const Icon(Icons.payment_rounded, size: 18, color: Colors.grey),
                const SizedBox(width: 8),
                Text('Método: ', style: TextStyle(color: colorScheme.onSurfaceVariant)),
                Text(
                  metodoPago.toUpperCase(),
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            if (email != null && email!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.mark_email_read_rounded, size: 18, color: Color(0xFF16A34A)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Respaldo enviado a $email',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: const Color(0xFF166534),
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () {
                  Navigator.of(context).pop();
                  if (onVerDetalle != null) onVerDetalle!();
                },
                icon: const Icon(Icons.receipt_long_rounded),
                label: const Text('Ver Detalle del Pedido'),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cerrar'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
