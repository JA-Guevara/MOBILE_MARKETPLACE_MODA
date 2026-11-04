import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/config/environment.dart';
import '../application/session_controller.dart';

/// Pantalla informativa para cuentas con rol de plataforma (super administrador).
///
/// La administración y configuración global de FashionStore SaaS se realiza
/// desde la consola web. Desde esta pantalla la persona puede abrir la consola
/// web en el navegador del dispositivo o cerrar su sesión.
class CuentaPlataformaScreen extends ConsumerWidget {
  const CuentaPlataformaScreen({super.key});

  Future<void> _abrirConsolaWeb() async {
    final url = Uri.parse('${Environment.webUrl}/admin/plataforma');
    await launchUrl(url, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tema = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Cuenta de plataforma'),
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Card(
                elevation: 0,
                color: tema.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(
                    color: tema.colorScheme.outlineVariant.withValues(alpha: 0.5),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    children: [
                      Icon(
                        Icons.admin_panel_settings_outlined,
                        size: 48,
                        color: tema.colorScheme.primary,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Cuenta de plataforma',
                        style: tema.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'La administración de empresas se hace desde la consola web. '
                        'En la app puedes cerrar sesión o abrir la consola.',
                        style: tema.textTheme.bodyMedium?.copyWith(
                          color: tema.colorScheme.onSurfaceVariant,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _abrirConsolaWeb,
                icon: const Icon(Icons.open_in_browser),
                label: const Text('Abrir consola web'),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => ref.read(sessionProvider.notifier).cerrarSesion(),
                icon: const Icon(Icons.logout),
                label: const Text('Cerrar sesión'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
