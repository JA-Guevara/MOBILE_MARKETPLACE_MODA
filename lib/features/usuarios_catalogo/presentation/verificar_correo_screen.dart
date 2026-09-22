import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_exception.dart';
import '../application/session_controller.dart';

/// Verificación de correo. Cubre los modos `verify` y `resend` de la web:
///
/// - Con `token`: confirma el enlace del correo (`POST /auth/verify-email`).
/// - Sin `token`: permite reenviar la verificación (`POST /auth/resend-verification`).
class VerificarCorreoScreen extends ConsumerStatefulWidget {
  const VerificarCorreoScreen({super.key, this.token = '', this.email = ''});

  final String token;
  final String email;

  @override
  ConsumerState<VerificarCorreoScreen> createState() => _VerificarCorreoScreenState();
}

class _VerificarCorreoScreenState extends ConsumerState<VerificarCorreoScreen> {
  final _formulario = GlobalKey<FormState>();
  late final TextEditingController _email = TextEditingController(text: widget.email);
  bool _ocupado = false;
  String? _error;
  String? _mensaje;

  bool get _verificando => widget.token.isNotEmpty;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _accion() async {
    if (_ocupado) return;
    setState(() {
      _error = null;
      _mensaje = null;
    });
    if (!_verificando && !_formulario.currentState!.validate()) return;
    setState(() => _ocupado = true);
    try {
      final mensaje = _verificando
          ? await ref.read(sessionProvider.notifier).verificarCorreo(widget.token)
          : await ref
              .read(sessionProvider.notifier)
              .reenviarVerificacion(_email.text.trim());
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
        title: Text(_verificando ? 'Verificar correo' : 'Reenviar verificación'),
      ),
      body: SafeArea(
        child: Form(
          key: _formulario,
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Text(
                _verificando ? 'Verificá tu correo' : 'Reenviar verificación',
                style: tema.textTheme.headlineSmall,
              ),
              const SizedBox(height: 4),
              Text(_verificando
                  ? 'Confirmá el correo asociado a tu cuenta.'
                  : 'Te enviamos un enlace nuevo para confirmar tu correo.'),
              const SizedBox(height: 24),
              if (!_verificando)
                TextFormField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [AutofillHints.email],
                  decoration: const InputDecoration(labelText: 'Correo electrónico'),
                  validator: (valor) =>
                      (valor ?? '').contains('@') ? null : 'Ingresá un correo válido.',
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
                onPressed: _ocupado || _mensaje != null ? null : _accion,
                child: _ocupado
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(_verificando ? 'Verificar correo' : 'Enviar verificación'),
              ),
              TextButton(
                onPressed: () => context.go('/iniciar-sesion'),
                child: const Text('Ir a iniciar sesión'),
              ),
              if (_verificando)
                TextButton(
                  onPressed: _mensaje == null
                      ? () => context.go('/reenviar-verificacion')
                      : null,
                  child: const Text('¿El enlace venció? Reenviar verificación'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
