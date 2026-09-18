import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_exception.dart';
import '../application/session_controller.dart';

/// Inicio de sesión contra `/auth/login`.
///
/// Es la primera rebanada vertical completa de la app: pantalla → controlador
/// → API → backend. Sirve de molde para las demás.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key, this.volverA});

  /// A dónde ir después de entrar. Lo manda la ruta protegida que exigió login.
  final String? volverA;

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formulario = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _ocupado = false;
  bool _oculta = true;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _entrar() async {
    if (!_formulario.currentState!.validate() || _ocupado) return;
    setState(() {
      _ocupado = true;
      _error = null;
    });
    try {
      await ref.read(sessionProvider.notifier).iniciarSesion(_email.text, _password.text);
      if (mounted) context.go(widget.volverA ?? '/');
    } on ApiException catch (error) {
      setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Iniciar sesión')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text('FashionStore', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 4),
            const Text('Entrá para comprar, reservar y usar el probador.'),
            const SizedBox(height: 24),
            Form(
              key: _formulario,
              child: Column(
                children: [
                  TextFormField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.email],
                    decoration: const InputDecoration(labelText: 'Correo electrónico'),
                    validator: (valor) => (valor ?? '').contains('@') ? null : 'Ingresá un correo válido.',
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _password,
                    obscureText: _oculta,
                    autofillHints: const [AutofillHints.password],
                    decoration: InputDecoration(
                      labelText: 'Contraseña',
                      suffixIcon: IconButton(
                        onPressed: () => setState(() => _oculta = !_oculta),
                        icon: Icon(_oculta ? Icons.visibility : Icons.visibility_off),
                        tooltip: _oculta ? 'Mostrar' : 'Ocultar',
                      ),
                    ),
                    validator: (valor) =>
                        (valor ?? '').isEmpty ? 'Escribí tu contraseña.' : null,
                    onFieldSubmitted: (_) => _entrar(),
                  ),
                ],
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 16),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _ocupado ? null : _entrar,
              child: _ocupado
                  ? const SizedBox(
                      height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Entrar'),
            ),
            TextButton(
              onPressed: () => context.go('/recuperar-contrasena'),
              child: const Text('Olvidé mi contraseña'),
            ),
            const Divider(height: 32),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text('¿Todavía no tenés cuenta?'),
                TextButton(
                  onPressed: () => context.go('/registrarse'),
                  child: const Text('Crear cuenta'),
                ),
              ],
            ),
            TextButton(
              onPressed: () => context.go('/reenviar-verificacion'),
              child: const Text('Reenviar verificación de correo'),
            ),
            TextButton(
              onPressed: () => context.go('/'),
              child: const Text('Seguir viendo el catálogo'),
            ),
          ],
        ),
      ),
    );
  }
}
