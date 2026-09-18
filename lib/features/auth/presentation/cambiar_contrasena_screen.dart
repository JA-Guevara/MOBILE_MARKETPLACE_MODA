import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_exception.dart';
import '../../../shared/widgets/contrasena_field.dart';
import '../application/session_controller.dart';
import '../domain/password.dart';

/// Cambiar contraseña estando adentro (RF01). Modo `change` de la web.
///
/// Al terminar el backend cierra las sesiones, así que el controlador limpia la
/// sesión y se vuelve al login con un aviso.
class CambiarContrasenaScreen extends ConsumerStatefulWidget {
  const CambiarContrasenaScreen({super.key});

  @override
  ConsumerState<CambiarContrasenaScreen> createState() =>
      _CambiarContrasenaScreenState();
}

class _CambiarContrasenaScreenState extends ConsumerState<CambiarContrasenaScreen> {
  final _formulario = GlobalKey<FormState>();
  final _actual = TextEditingController();
  final _nueva = TextEditingController();
  final _confirmacion = TextEditingController();
  bool _ocupado = false;
  String? _error;
  String? _mensaje;

  @override
  void dispose() {
    _actual.dispose();
    _nueva.dispose();
    _confirmacion.dispose();
    super.dispose();
  }

  Future<void> _cambiar() async {
    if (_ocupado) return;
    setState(() {
      _error = null;
      _mensaje = null;
    });
    if (!_formulario.currentState!.validate()) return;
    final email = ref.read(sessionProvider).usuario?.email ?? '';
    final problema = passwordError(_nueva.text, email: email);
    if (problema != null) {
      setState(() => _error = problema);
      return;
    }
    if (_nueva.text != _confirmacion.text) {
      setState(() => _error = 'Las contraseñas no coinciden.');
      return;
    }
    setState(() => _ocupado = true);
    try {
      final mensaje = await ref
          .read(sessionProvider.notifier)
          .cambiarContrasena(_actual.text, _nueva.text);
      if (!mounted) return;
      setState(() => _mensaje = mensaje);
    } on ApiException catch (error) {
      setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Seguridad')),
      body: SafeArea(
        child: Form(
          key: _formulario,
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Text('Cambiar contraseña', style: tema.textTheme.headlineSmall),
              const SizedBox(height: 4),
              const Text('Después de cambiarla vas a tener que iniciar sesión de nuevo.'),
              const SizedBox(height: 24),
              ContrasenaField(
                controller: _actual,
                label: 'Contraseña actual',
                autofillHints: const [AutofillHints.password],
                validator: (valor) =>
                    (valor ?? '').isEmpty ? 'Escribí tu contraseña actual.' : null,
              ),
              const SizedBox(height: 12),
              ContrasenaField(
                controller: _nueva,
                label: 'Nueva contraseña',
                autofillHints: const [AutofillHints.newPassword],
                validator: (valor) =>
                    (valor ?? '').isEmpty ? 'Escribí la nueva contraseña.' : null,
              ),
              const SizedBox(height: 6),
              Text(
                'Entre 12 y 128 caracteres, mayúscula, minúscula, número y símbolo. '
                'No incluyas el nombre de tu correo.',
                style: tema.textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              ContrasenaField(
                controller: _confirmacion,
                label: 'Repetir contraseña',
                autofillHints: const [AutofillHints.newPassword],
                validator: (valor) =>
                    (valor ?? '').isEmpty ? 'Repetí la contraseña.' : null,
                onSubmitted: (_) => _cambiar(),
              ),
              if (_error != null) ...[
                const SizedBox(height: 16),
                Text(_error!, style: TextStyle(color: tema.colorScheme.error)),
              ],
              if (_mensaje != null) ...[
                const SizedBox(height: 16),
                Text(_mensaje!, style: TextStyle(color: tema.colorScheme.primary)),
              ],
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _ocupado || _mensaje != null ? null : _cambiar,
                child: _ocupado
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Cambiar contraseña'),
              ),
              if (_mensaje != null)
                TextButton(
                  onPressed: () => context.go('/iniciar-sesion'),
                  child: const Text('Iniciar sesión'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}