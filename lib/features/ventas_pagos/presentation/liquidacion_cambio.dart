import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/api_exception.dart';
import '../../../shared/formato.dart';
import '../application/commerce_providers.dart';
import '../domain/commerce_models.dart';
import 'stripe_checkout_launcher.dart';

class LiquidacionCambio extends ConsumerStatefulWidget {
  const LiquidacionCambio({
    super.key,
    required this.cambio,
    required this.onActualizar,
  });
  final Devolucion cambio;
  final Future<void> Function() onActualizar;
  @override
  ConsumerState<LiquidacionCambio> createState() => _LiquidacionCambioState();
}

class _LiquidacionCambioState extends ConsumerState<LiquidacionCambio> {
  bool busy = false;
  String? message;
  Future<void> action(bool pay) async {
    if (busy) return;
    setState(() {
      busy = true;
      message = null;
    });
    try {
      final api = ref.read(commerceApiProvider);
      if (pay) {
        final url = await api.pagarDiferencia(widget.cambio.id);
        if (url != null) {
          final opened = await abrirStripeCheckout(url);
          if (!opened && mounted) await mostrarEnlaceStripe(context, url);
        }
      } else {
        final result = await api.verificarDiferencia(widget.cambio.id);
        if (mounted) {
          setState(
            () => message = result.settlementStatus == 'paid'
                ? 'Pago confirmado. La sucursal puede entregar el reemplazo.'
                : 'El proveedor todavía no confirmó el pago.',
          );
        }
      }
      await widget.onActualizar();
    } on ApiException catch (e) {
      if (mounted) setState(() => message = e.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => message =
              'No pudimos consultar el pago. Intentá nuevamente con conexión.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.cambio;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Cambio · Diferencia ${Formato.moneda(c.differenceAmount)} · ${c.etiquetaLiquidacion}',
          ),
          if (c.status == 'approved' &&
              c.differenceAmount > 0 &&
              c.settlementStatus != 'paid')
            Wrap(
              spacing: 8,
              children: [
                FilledButton(
                  onPressed: busy ? null : () => action(true),
                  child: const Text('Pagar diferencia con tarjeta'),
                ),
                TextButton(
                  onPressed: busy ? null : () => action(false),
                  child: const Text('Ya pagué · verificar'),
                ),
              ],
            ),
          if (c.status == 'approved' &&
              c.differenceAmount > 0 &&
              c.settlementStatus != 'paid')
            const Text(
              'También podés pagar en efectivo al entregar la prenda en la sucursal.',
            ),
          if (message != null) Text(message!),
        ],
      ),
    );
  }
}
