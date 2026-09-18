import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_exception.dart';
import '../application/account_controller.dart';
import '../application/session_controller.dart';
import '../domain/address.dart';

/// «Mi cuenta»: perfil, direcciones y accesos del cliente.
///
/// Reúne lo que en la web son `account-layout.component.ts` (menú del espacio
/// personal) y `account-page.component.ts` (datos personales y direcciones),
/// adaptado a la pestaña Cuenta de la barra inferior.
class AccountScreen extends ConsumerStatefulWidget {
  const AccountScreen({super.key});

  @override
  ConsumerState<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends ConsumerState<AccountScreen> {
  final _nombre = TextEditingController();
  final _apellido = TextEditingController();
  final _telefono = TextEditingController();
  bool _editando = false;
  bool _ocupado = false;
  String? _error;
  String? _mensaje;

  @override
  void initState() {
    super.initState();
    Future.microtask(() async {
      try {
        await ref.read(accountControllerProvider.notifier).cargarDirecciones();
      } on ApiException catch (error) {
        if (mounted) setState(() => _error = error.message);
      }
    });
  }

  @override
  void dispose() {
    _nombre.dispose();
    _apellido.dispose();
    _telefono.dispose();
    super.dispose();
  }

  void _alternarEdicion() {
    final usuario = ref.read(sessionProvider).usuario;
    if (!_editando && usuario != null) {
      _nombre.text = usuario.nombre;
      _apellido.text = usuario.apellido;
      _telefono.text = usuario.telefono ?? '';
    }
    setState(() {
      _editando = !_editando;
      _error = null;
      _mensaje = null;
    });
  }

  Future<void> _guardarPerfil() async {
    if (_ocupado) return;
    setState(() {
      _ocupado = true;
      _error = null;
      _mensaje = null;
    });
    try {
      await ref.read(accountControllerProvider.notifier).guardarPerfil(
            nombre: _nombre.text.trim(),
            apellido: _apellido.text.trim(),
            telefono: _telefono.text.trim(),
          );
      await ref.read(sessionProvider.notifier).recargarUsuario();
      if (!mounted) return;
      setState(() {
        _editando = false;
        _mensaje = 'Tus datos fueron actualizados.';
      });
    } on ApiException catch (error) {
      setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  Future<void> _reenviarVerificacion() async {
    if (_ocupado) return;
    setState(() {
      _ocupado = true;
      _error = null;
      _mensaje = null;
    });
    try {
      final mensaje = await ref.read(sessionProvider.notifier).reenviarVerificacion();
      if (mounted) setState(() => _mensaje = mensaje);
    } on ApiException catch (error) {
      setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  Future<void> _marcarPredeterminada(Direccion direccion) async {
    if (_ocupado) return;
    setState(() {
      _ocupado = true;
      _error = null;
      _mensaje = null;
    });
    try {
      await ref.read(accountControllerProvider.notifier).marcarPredeterminada(direccion);
      if (mounted) {
        setState(() => _mensaje = '«${direccion.label}» quedó como dirección predeterminada.');
      }
    } on ApiException catch (error) {
      setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  Future<void> _cerrarSesion() async {
    if (_ocupado) return;
    setState(() => _ocupado = true);
    await ref.read(sessionProvider.notifier).cerrarSesion();
    if (mounted) context.go('/');
  }

  String _iniciales(String nombre, String apellido) {
    final a = nombre.isNotEmpty ? nombre[0] : '';
    final b = apellido.isNotEmpty ? apellido[0] : '';
    final texto = '$a$b'.toUpperCase();
    return texto.isEmpty ? '·' : texto;
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final sesion = ref.watch(sessionProvider);
    final cuenta = ref.watch(accountControllerProvider);
    final usuario = sesion.usuario;

    if (usuario == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Mi cuenta')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 28,
                  child: Text(_iniciales(usuario.nombre, usuario.apellido)),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(usuario.nombreCompleto, style: tema.textTheme.titleMedium),
                      Text(usuario.email, style: tema.textTheme.bodySmall),
                      const SizedBox(height: 4),
                      Text(
                        usuario.verificado
                            ? 'Correo verificado'
                            : 'Correo pendiente de verificación',
                        style: tema.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(usuario.telefono?.isNotEmpty == true
                ? usuario.telefono!
                : 'Sin teléfono registrado'),
            const SizedBox(height: 16),
            Row(
              children: [
                FilledButton.tonalIcon(
                  onPressed: _ocupado ? null : _alternarEdicion,
                  icon: Icon(_editando ? Icons.close : Icons.edit),
                  label: Text(_editando ? 'Cerrar edición' : 'Editar mis datos'),
                ),
                if (!usuario.verificado) ...[
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: _ocupado ? null : _reenviarVerificacion,
                    child: const Text('Reenviar verificación'),
                  ),
                ],
              ],
            ),
            if (_editando) ...[
              const SizedBox(height: 16),
              Text('Datos personales', style: tema.textTheme.titleSmall),
              const SizedBox(height: 4),
              const Text(
                'Mantené tu nombre y teléfono actualizados para coordinar tus pedidos.',
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _nombre,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Nombres'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _apellido,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Apellidos'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _telefono,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: 'Teléfono'),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _ocupado ? null : _guardarPerfil,
                child: const Text('Guardar cambios'),
              ),
            ],
            if (_mensaje != null) ...[
              const SizedBox(height: 12),
              Text(_mensaje!, style: TextStyle(color: tema.colorScheme.primary)),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: TextStyle(color: tema.colorScheme.error)),
            ],
            const Divider(height: 40),
            _Acceso(
              icono: Icons.receipt_long_outlined,
              titulo: 'Mis pedidos',
              detalle: 'Compras y pagos',
              onTap: () => context.go('/mi-cuenta/pedidos'),
            ),
            _Acceso(
              icono: Icons.event_outlined,
              titulo: 'Mis reservas',
              detalle: 'Prueba en sucursal',
              onTap: () => context.go('/mi-cuenta/reservas'),
            ),
            _Acceso(
              icono: Icons.lock_outline,
              titulo: 'Seguridad',
              detalle: 'Cambiar contraseña',
              onTap: () => context.go('/mi-cuenta/seguridad'),
            ),
            const Divider(height: 40),
            Text('Mis direcciones', style: tema.textTheme.titleMedium),
            const SizedBox(height: 4),
            const Text(
              'La predeterminada se completa sola al finalizar una compra, así no la '
              'reescribís cada vez.',
            ),
            const SizedBox(height: 12),
            if (cuenta.cargando)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (cuenta.direcciones.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  'Todavía no guardaste direcciones. Agregá una y se usará automáticamente '
                  'en tus próximos pedidos.',
                ),
              )
            else
              for (final direccion in cuenta.direcciones)
                _TarjetaDireccion(
                  direccion: direccion,
                  ocupado: _ocupado,
                  onPredeterminar: () => _marcarPredeterminada(direccion),
                ),
            const SizedBox(height: 24),
            OutlinedButton.icon(
              onPressed: _ocupado ? null : _cerrarSesion,
              icon: const Icon(Icons.logout),
              label: Text(_ocupado ? 'Cerrando…' : 'Cerrar sesión'),
            ),
          ],
        ),
      ),
    );
  }
}

class _Acceso extends StatelessWidget {
  const _Acceso({
    required this.icono,
    required this.titulo,
    required this.detalle,
    required this.onTap,
  });

  final IconData icono;
  final String titulo;
  final String detalle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icono),
      title: Text(titulo),
      subtitle: Text(detalle),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}

class _TarjetaDireccion extends StatelessWidget {
  const _TarjetaDireccion({
    required this.direccion,
    required this.ocupado,
    required this.onPredeterminar,
  });

  final Direccion direccion;
  final bool ocupado;
  final VoidCallback onPredeterminar;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final ubicacion = [
      direccion.addressLine,
      direccion.city,
      if ((direccion.postalCode ?? '').isNotEmpty) 'CP ${direccion.postalCode}',
    ].join(' · ');
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(direccion.label, style: tema.textTheme.titleSmall),
                ),
                if (direccion.isDefault)
                  Chip(label: const Text('Predeterminada'), visualDensity: VisualDensity.compact),
              ],
            ),
            const SizedBox(height: 4),
            Text('${direccion.recipientName} · ${direccion.phone}'),
            Text(ubicacion, style: tema.textTheme.bodySmall),
            if (!direccion.isDefault) ...[
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: ocupado ? null : onPredeterminar,
                icon: const Icon(Icons.check),
                label: const Text('Usar como predeterminada'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}