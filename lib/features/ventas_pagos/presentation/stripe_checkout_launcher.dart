import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

/// Stripe se abre en el navegador del sistema, fuera de la app.
Future<bool> abrirStripeCheckout(String url) async {
  final destino = Uri.tryParse(url);
  if (destino == null ||
      destino.scheme != 'https' ||
      destino.host != 'checkout.stripe.com') {
    return false;
  }
  try {
    return await launchUrl(destino, mode: LaunchMode.externalApplication);
  } catch (_) {
    return false;
  }
}

/// Si el dispositivo no tiene un navegador resoluble, la persona conserva el
/// enlace de Checkout y puede pegarlo en su navegador sin crear otro pedido.
Future<void> mostrarEnlaceStripe(
  BuildContext context,
  String url,
) => showDialog<void>(
  context: context,
  builder: (dialogo) => AlertDialog(
    title: const Text('No pudimos abrir Stripe'),
    content: const Text(
      'Copiá el enlace y abrilo en Chrome u otro navegador para completar el pago.',
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(dialogo).pop(),
        child: const Text('Volver'),
      ),
      FilledButton.icon(
        onPressed: () async {
          await Clipboard.setData(ClipboardData(text: url));
          if (dialogo.mounted) Navigator.of(dialogo).pop();
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Enlace de Stripe copiado.')),
            );
          }
        },
        icon: const Icon(Icons.copy_outlined),
        label: const Text('Copiar enlace'),
      ),
    ],
  ),
);
