import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../shared/widgets/estado_vista.dart';
import '../application/direcciones_controller.dart';
import '../domain/address.dart';

/// «Mis direcciones» (`/mi-cuenta/direcciones`): alta, edición y borrado.
class DireccionesScreen extends ConsumerStatefulWidget {
  const DireccionesScreen({super.key});

  @override
  ConsumerState<DireccionesScreen> createState() => _DireccionesScreenState();
}

class _DireccionesScreenState extends ConsumerState<DireccionesScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(direccionesProvider.notifier).cargar());
  }

  Future<void> _abrirFormulario([Direccion? direccion]) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => Padding(
        // Deja el formulario por encima del teclado.
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: _FormularioDireccion(direccion: direccion),
      ),
    );
  }

  Future<void> _confirmarBorrado(Direccion direccion) async {
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('¿Borrar la dirección?'),
        content: Text('Se quita «${direccion.label}» de tu perfil. '
            'No se puede deshacer.'),
        actions: [
          TextButton(
            onPressed: () => context.pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => context.pop(true),
            child: const Text('Borrar'),
          ),
        ],
      ),
    );
    if (confirmado == true) {
      await ref.read(direccionesProvider.notifier).eliminar(direccion);
    }
  }

  @override
  Widget build(BuildContext context) {
    final estado = ref.watch(direccionesProvider);
    final control = ref.read(direccionesProvider.notifier);
    final tema = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Mis direcciones')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: estado.ocupado ? null : () => _abrirFormulario(),
        icon: const Icon(Icons.add),
        label: const Text('Agregar'),
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: control.cargar,
          child: Builder(builder: (context) {
            if (estado.cargando && estado.direcciones.isEmpty) {
              return const VistaCargando(mensaje: 'Buscando tus direcciones…');
            }
            if (estado.error != null && estado.direcciones.isEmpty) {
              return VistaError(mensaje: estado.error!, onReintentar: control.cargar);
            }
            if (estado.direcciones.isEmpty) {
              return VistaVacia(
                icono: Icons.location_on_outlined,
                titulo: 'Todavía no guardaste direcciones',
                mensaje: 'Guardá una y se completa sola en tus próximas compras.',
                accionTexto: 'Agregar dirección',
                onAccion: () => _abrirFormulario(),
              );
            }
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
              children: [
                if (estado.mensaje != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(estado.mensaje!,
                        style: TextStyle(color: tema.colorScheme.primary)),
                  ),
                if (estado.error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(estado.error!,
                        style: TextStyle(color: tema.colorScheme.error)),
                  ),
                for (final direccion in estado.direcciones)
                  _TarjetaDireccion(
                    direccion: direccion,
                    ocupado: estado.ocupado,
                    onEditar: () => _abrirFormulario(direccion),
                    onBorrar: () => _confirmarBorrado(direccion),
                    onPredeterminar: () => control.marcarPredeterminada(direccion),
                  ),
              ],
            );
          }),
        ),
      ),
    );
  }
}

class _TarjetaDireccion extends StatelessWidget {
  const _TarjetaDireccion({
    required this.direccion,
    required this.ocupado,
    required this.onEditar,
    required this.onBorrar,
    required this.onPredeterminar,
  });

  final Direccion direccion;
  final bool ocupado;
  final VoidCallback onEditar;
  final VoidCallback onBorrar;
  final VoidCallback onPredeterminar;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        border: Border.all(color: tema.colorScheme.outline),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(direccion.label, style: tema.textTheme.titleSmall),
              const SizedBox(width: 8),
              if (direccion.isDefault)
                const ChipEstado(
                  etiqueta: 'Predeterminada',
                  exportacion: 'ok',
                  compacto: true,
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(direccion.recipientName),
          Text(direccion.phone, style: tema.textTheme.bodySmall),
          Text(direccion.addressLine, style: tema.textTheme.bodySmall),
          Text(
            [direccion.city, direccion.country]
                .where((t) => t != null && t.isNotEmpty)
                .join(', '),
            style: tema.textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 4,
            children: [
              if (!direccion.isDefault)
                TextButton(
                  onPressed: ocupado ? null : onPredeterminar,
                  child: const Text('Usar por defecto'),
                ),
              TextButton(
                onPressed: ocupado ? null : onEditar,
                child: const Text('Editar'),
              ),
              TextButton(
                onPressed: ocupado ? null : onBorrar,
                child: Text('Borrar',
                    style: TextStyle(color: tema.colorScheme.error)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Alta y edición. El mismo formulario para las dos: cambia el título y si se
/// manda `id`, nada más.
class _FormularioDireccion extends ConsumerStatefulWidget {
  const _FormularioDireccion({this.direccion});

  final Direccion? direccion;

  @override
  ConsumerState<_FormularioDireccion> createState() => _FormularioDireccionState();
}

class _FormularioDireccionState extends ConsumerState<_FormularioDireccion> {
  final _formulario = GlobalKey<FormState>();
  late final _etiqueta = TextEditingController(text: widget.direccion?.label ?? 'Casa');
  late final _destinatario =
      TextEditingController(text: widget.direccion?.recipientName ?? '');
  late final _telefono = TextEditingController(text: widget.direccion?.phone ?? '');
  late final _linea = TextEditingController(text: widget.direccion?.addressLine ?? '');
  late final _ciudad = TextEditingController(text: widget.direccion?.city ?? '');
  late final _postal =
      TextEditingController(text: widget.direccion?.postalCode ?? '');
  late final _pais = TextEditingController(text: widget.direccion?.country ?? 'BO');
  late bool _predeterminada = widget.direccion?.isDefault ?? false;

  @override
  void dispose() {
    for (final c in [
      _etiqueta,
      _destinatario,
      _telefono,
      _linea,
      _ciudad,
      _postal,
      _pais,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _guardar() async {
    if (!_formulario.currentState!.validate()) return;
    final guardado = await ref.read(direccionesProvider.notifier).guardar(
          id: widget.direccion?.id,
          etiqueta: _etiqueta.text.trim(),
          destinatario: _destinatario.text.trim(),
          telefono: _telefono.text.trim(),
          linea: _linea.text.trim(),
          ciudad: _ciudad.text.trim(),
          codigoPostal: _postal.text.trim(),
          pais: _pais.text.trim(),
          predeterminada: _predeterminada,
        );
    if (guardado && mounted) context.pop();
  }

  String? _obligatorio(String? valor) =>
      (valor ?? '').trim().isEmpty ? 'Completá este dato.' : null;

  @override
  Widget build(BuildContext context) {
    final ocupado = ref.watch(direccionesProvider).ocupado;
    final tema = Theme.of(context);
    return Form(
      key: _formulario,
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            widget.direccion == null ? 'Nueva dirección' : 'Editar dirección',
            style: tema.textTheme.titleMedium,
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _etiqueta,
            decoration: const InputDecoration(
              labelText: 'Nombre',
              helperText: 'Casa, trabajo, casa de mamá…',
            ),
            validator: _obligatorio,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _destinatario,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Quién recibe'),
            validator: _obligatorio,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _telefono,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(labelText: 'Teléfono'),
            validator: _obligatorio,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _linea,
            decoration: const InputDecoration(labelText: 'Dirección'),
            validator: _obligatorio,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _ciudad,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Ciudad'),
            validator: _obligatorio,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _postal,
            decoration: const InputDecoration(labelText: 'Código postal (opcional)'),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _pais,
            decoration: const InputDecoration(labelText: 'País'),
          ),
          CheckboxListTile(
            value: _predeterminada,
            onChanged: (valor) => setState(() => _predeterminada = valor ?? false),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: const Text('Usar por defecto al comprar'),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: ocupado ? null : _guardar,
            child: ocupado
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Guardar'),
          ),
          TextButton(
            onPressed: ocupado ? null : () => context.pop(),
            child: const Text('Cancelar'),
          ),
        ],
      ),
    );
  }
}
