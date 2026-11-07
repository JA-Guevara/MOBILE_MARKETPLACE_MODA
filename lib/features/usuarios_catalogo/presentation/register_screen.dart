import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_exception.dart';
import '../../../shared/widgets/contrasena_field.dart';
import '../application/session_controller.dart';
import '../domain/password.dart';

/// Crear cuenta (RF01). Es el modo `register` de `auth-page.component.ts`.
///
/// El backend no abre sesión al registrarse: pide verificar el correo, así que
/// la pantalla termina con el mensaje del servidor y una vuelta al login.
class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _formulario = GlobalKey<FormState>();
  final _nombre = TextEditingController();
  final _apellido = TextEditingController();
  final _telefono = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirmacion = TextEditingController();
  bool _ocupado = false;
  String? _error;
  String? _mensaje;
  String? _empresa;

  @override
  void initState() {
    super.initState();
    _empresa = ref.read(tiendaPublicaSeleccionadaProvider)?.slug;
  }

  @override
  void dispose() {
    _nombre.dispose();
    _apellido.dispose();
    _telefono.dispose();
    _email.dispose();
    _password.dispose();
    _confirmacion.dispose();
    super.dispose();
  }

  Future<void> _registrar() async {
    if (_ocupado) return;
    setState(() {
      _error = null;
      _mensaje = null;
    });
    if (!_formulario.currentState!.validate()) return;
    final problema = passwordError(_password.text, email: _email.text);
    if (problema != null) {
      setState(() => _error = problema);
      return;
    }
    if (_password.text != _confirmacion.text) {
      setState(() => _error = 'Las contraseñas no coinciden.');
      return;
    }
    setState(() => _ocupado = true);
    try {
      final mensaje = await ref
          .read(sessionProvider.notifier)
          .registrarse(
            email: _email.text,
            password: _password.text,
            nombre: _nombre.text.trim(),
            apellido: _apellido.text.trim(),
            telefono: _telefono.text.trim(),
          );
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
    final tiendas = ref.watch(tiendasPublicasProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Crear cuenta')),
      body: SafeArea(
        child: Form(
          key: _formulario,
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Text('Creá tu cuenta', style: tema.textTheme.headlineSmall),
              const SizedBox(height: 4),
              const Text(
                'Completá tus datos para formar parte de FashionStore.',
              ),
              const SizedBox(height: 24),
              DropdownButtonFormField<String>(
                initialValue: _empresa,
                decoration: const InputDecoration(
                  labelText: 'Empresa o tienda',
                ),
                isExpanded: true,
                items: [
                  if (_empresa != null &&
                      !(tiendas.asData?.value ?? const []).any(
                        (t) => t.slug == _empresa,
                      ))
                    DropdownMenuItem(
                      value: _empresa,
                      child: Text(
                        ref.read(tiendaPublicaSeleccionadaProvider)?.nombre ??
                            _empresa!,
                      ),
                    ),
                  for (final tienda in tiendas.asData?.value ?? const [])
                    DropdownMenuItem(
                      value: tienda.slug,
                      child: Text(tienda.nombre),
                    ),
                ],
                onChanged: _ocupado
                    ? null
                    : (value) {
                        setState(() => _empresa = value);
                        final matches = (tiendas.asData?.value ?? const [])
                            .where((t) => t.slug == value);
                        if (matches.isNotEmpty) {
                          ref
                              .read(tiendaPublicaSeleccionadaProvider.notifier)
                              .state = matches
                              .first;
                        }
                      },
                validator: (value) => value == null
                    ? 'Elegí la tienda donde querés registrarte.'
                    : null,
              ),
              if (tiendas.isLoading) const LinearProgressIndicator(),
              if (tiendas.hasError)
                TextButton(
                  onPressed: () => ref.invalidate(tiendasPublicasProvider),
                  child: const Text(
                    'No se pudo cargar las tiendas. Reintentar',
                  ),
                ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _nombre,
                textCapitalization: TextCapitalization.words,
                autofillHints: const [AutofillHints.givenName],
                decoration: const InputDecoration(labelText: 'Nombres'),
                validator: (valor) => (valor ?? '').trim().length >= 2
                    ? null
                    : 'Ingresá tus nombres.',
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _apellido,
                textCapitalization: TextCapitalization.words,
                autofillHints: const [AutofillHints.familyName],
                decoration: const InputDecoration(labelText: 'Apellidos'),
                validator: (valor) => (valor ?? '').trim().length >= 2
                    ? null
                    : 'Ingresá tus apellidos.',
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _telefono,
                keyboardType: TextInputType.phone,
                autofillHints: const [AutofillHints.telephoneNumber],
                decoration: const InputDecoration(
                  labelText: 'Teléfono (opcional)',
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.email],
                decoration: const InputDecoration(
                  labelText: 'Correo electrónico',
                ),
                validator: (valor) => (valor ?? '').contains('@')
                    ? null
                    : 'Ingresá un correo válido.',
              ),
              const SizedBox(height: 12),
              ContrasenaField(
                controller: _password,
                label: 'Nueva contraseña',
                autofillHints: const [AutofillHints.newPassword],
                validator: (valor) =>
                    (valor ?? '').isEmpty ? 'Escribí una contraseña.' : null,
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
                onSubmitted: (_) => _registrar(),
              ),
              if (_error != null) ...[
                const SizedBox(height: 16),
                Text(_error!, style: TextStyle(color: tema.colorScheme.error)),
              ],
              if (_mensaje != null) ...[
                const SizedBox(height: 16),
                Text(
                  _mensaje!,
                  style: TextStyle(color: tema.colorScheme.primary),
                ),
              ],
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _ocupado || _mensaje != null ? null : _registrar,
                child: _ocupado
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Crear cuenta'),
              ),
              TextButton(
                onPressed: () => context.go('/iniciar-sesion'),
                child: const Text('Ya tengo cuenta'),
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
