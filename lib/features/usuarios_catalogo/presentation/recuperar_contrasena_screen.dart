import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_exception.dart';
import '../../../shared/widgets/contrasena_field.dart';
import '../application/session_controller.dart';
import '../domain/password.dart';

/// Recuperar contraseña. Cubre los modos `forgot` y `reset` de la web:
///
/// - Sin `token` en el enlace: se pide el correo y el backend envía el enlace.
/// - Con `token`: el enlace del correo trae el token y se elige la contraseña
///   nueva.
class RecuperarContrasenaScreen extends ConsumerStatefulWidget {
  const RecuperarContrasenaScreen({super.key, this.token = ''});

  final String token;

  @override
  ConsumerState<RecuperarContrasenaScreen> createState() =>
      _RecuperarContrasenaScreenState();
}

class _RecuperarContrasenaScreenState extends ConsumerState<RecuperarContrasenaScreen> {
  final _formulario = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirmacion = TextEditingController();
  bool _ocupado = false;
  String? _error;
  String? _mensaje;

  bool get _restableciendo => widget.token.isNotEmpty;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _confirmacion.dispose();
    super.dispose();
  }

  Future<void> _enviar() async {
    if (_ocupado) return;
    setState(() {
      _error = null;
      _mensaje = null;
    });
    if (!_formulario.currentState!.validate()) return;
    if (_restableciendo) {
      final problema = passwordError(_password.text, email: _email.text);
      if (problema != null) {
        setState(() => _error = problema);
        return;
      }
      if (_password.text != _confirmacion.text) {
        setState(() => _error = 'Las contraseñas no coinciden.');
        return;
      }
    }
    setState(() => _ocupado = true);
    try {
      final mensaje = _restableciendo
          ? await ref
              .read(sessionProvider.notifier)
              .restablecerContrasena(widget.token, _password.text)
          : await ref.read(sessionProvider.notifier).recuperarContrasena(_email.text);
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
      appBar: AppBar(
        title: Text(_restableciendo ? 'Nueva contraseña' : 'Recuperar contraseña'),
      ),
      body: SafeArea(
        child: Form(
          key: _formulario,
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Text(
                _restableciendo ? 'Elegí una nueva contraseña' : 'Recuperá tu contraseña',
                style: tema.textTheme.headlineSmall,
              ),
              const SizedBox(height: 4),
              Text(_restableciendo
                  ? 'Tu enlace es válido. Definí la contraseña que vas a usar desde ahora.'
                  : 'Escribí tu correo y te enviamos un enlace para volver a entrar.'),
              const SizedBox(height: 24),
              if (!_restableciendo)
                TextFormField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [AutofillHints.email],
                  decoration: const InputDecoration(labelText: 'Correo electrónico'),
                  validator: (valor) =>
                      (valor ?? '').contains('@') ? null : 'Ingresá un correo válido.',
                )
              else ...[
                ContrasenaField(
                  controller: _password,
                  label: 'Nueva contraseña',
                  autofillHints: const [AutofillHints.newPassword],
                  validator: (valor) =>
                      (valor ?? '').isEmpty ? 'Escribí una contraseña.' : null,
                ),
                const SizedBox(height: 12),
                ContrasenaField(
                  controller: _confirmacion,
                  label: 'Repetir contraseña',
                  autofillHints: const [AutofillHints.newPassword],
                  validator: (valor) =>
                      (valor ?? '').isEmpty ? 'Repetí la contraseña.' : null,
                  onSubmitted: (_) => _enviar(),
                ),
              ],
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
                onPressed: _ocupado || _mensaje != null ? null : _enviar,
                child: _ocupado
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(_restableciendo ? 'Guardar contraseña' : 'Enviar enlace'),
              ),
              TextButton(
                onPressed: () => context.go('/iniciar-sesion'),
                child: const Text('Volver a iniciar sesión'),
              ),
              TextButton(
                onPressed: () => context.go('/reenviar-verificacion'),
                child: const Text('Reenviar verificación de correo'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
