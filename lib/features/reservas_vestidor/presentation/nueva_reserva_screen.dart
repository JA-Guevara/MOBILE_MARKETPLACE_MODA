import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../shared/formato.dart';
import '../../../shared/widgets/estado_vista.dart';
import '../application/reservas_controller.dart';
import '../domain/reserva.dart';

/// Agendar una visita al probador (`/reservar`).
///
/// Réplica de `nueva-reserva.component.ts`: la selección de prendas se arma
/// desde el detalle de cada prenda y se confirma acá, eligiendo sucursal y
/// horario. Antes de confirmar se le pregunta al backend si esa sucursal tiene
/// las tallas, para no hacer viajar a nadie en vano.
class NuevaReservaScreen extends ConsumerStatefulWidget {
  const NuevaReservaScreen({super.key});

  @override
  ConsumerState<NuevaReservaScreen> createState() => _NuevaReservaScreenState();
}

class _NuevaReservaScreenState extends ConsumerState<NuevaReservaScreen> {
  late final TextEditingController _notas;

  @override
  void initState() {
    super.initState();
    _notas = TextEditingController(text: ref.read(nuevaReservaProvider).notas);
    Future.microtask(() => ref.read(nuevaReservaProvider.notifier).cargar());
  }

  @override
  void dispose() {
    _notas.dispose();
    super.dispose();
  }

  Future<void> _elegirHorario() async {
    final ahora = DateTime.now();
    final actual = ref.read(nuevaReservaProvider).fecha;
    final dia = await showDatePicker(
      context: context,
      initialDate: actual ?? ahora.add(const Duration(days: 1)),
      // Agendar para ayer no tiene sentido; el backend también lo rechaza.
      firstDate: ahora,
      lastDate: ahora.add(const Duration(days: 90)),
    );
    if (dia == null || !mounted) return;
    final hora = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(actual ?? ahora),
    );
    if (hora == null || !mounted) return;
    final elegida = DateTime(
      dia.year,
      dia.month,
      dia.day,
      hora.hour,
      hora.minute,
    );
    // El servidor exige una fecha futura. Validarlo antes evita que una hora
    // pasada del día actual parezca una reserva que «no se registró».
    if (!elegida.isAfter(ahora)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Elegí un horario posterior a este momento.'),
        ),
      );
      return;
    }
    ref.read(nuevaReservaProvider.notifier).elegirFecha(elegida);
  }

  Future<void> _confirmar() async {
    final reserva = await ref.read(nuevaReservaProvider.notifier).confirmar();
    if (reserva == null || !mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Agendamos tu visita.')));
    context.go('/mi-cuenta/reservas');
  }

  @override
  Widget build(BuildContext context) {
    final estado = ref.watch(nuevaReservaProvider);
    final control = ref.read(nuevaReservaProvider.notifier);
    final tema = Theme.of(context);

    if (estado.cargando) {
      return Scaffold(
        appBar: AppBar(title: const Text('Agendar visita')),
        body: const VistaCargando(mensaje: 'Buscando sucursales…'),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Agendar visita')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          children: [
            Text('Prendas para probarte', style: tema.textTheme.titleSmall),
            const SizedBox(height: 8),
            if (estado.items.isEmpty)
              const BloqueAyuda(
                titulo: 'Tu selección está vacía',
                detalle:
                    'Abrí una prenda del catálogo y tocá «Reservar para '
                    'probarme». Podés juntar hasta 20 prendas distintas.',
              )
            else
              for (final item in estado.items)
                _LineaSeleccion(
                  item: item,
                  falta: estado.faltantes
                      .where((d) => d.variantId == item.variantId)
                      .firstOrNull,
                  onCantidad: (valor) =>
                      control.cambiarCantidad(item.variantId, valor),
                  onQuitar: () => control.quitar(item.variantId),
                ),

            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: estado.ocupado
                  ? null
                  : () => context.push('/elegir-prendas'),
              icon: const Icon(Icons.add),
              label: Text(
                estado.items.isEmpty
                    ? 'Agregar prendas del catálogo'
                    : 'Agregar más prendas',
              ),
            ),

            const Divider(height: 32),
            Text('Sucursal', style: tema.textTheme.titleSmall),
            const SizedBox(height: 8),
            if (estado.sucursales.isEmpty)
              Text(
                'No hay sucursales publicadas.',
                style: tema.textTheme.bodySmall,
              )
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final sucursal in estado.sucursales)
                    ChoiceChip(
                      label: Text(sucursal.nombre),
                      selected: estado.sucursalId == sucursal.id,
                      onSelected: (_) => control.elegirSucursal(sucursal.id),
                    ),
                ],
              ),

            if (estado.hayFaltantes) ...[
              const SizedBox(height: 12),
              BloqueAyuda(
                titulo: 'Esta sucursal no tiene todo',
                detalle: estado.faltantes
                    .map(
                      (d) =>
                          d.motivo ?? 'Una de las prendas no está disponible.',
                    )
                    .join(' '),
              ),
            ],

            const Divider(height: 32),
            Text('Cuándo pasás', style: tema.textTheme.titleSmall),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _elegirHorario,
              icon: const Icon(Icons.event_outlined),
              label: Text(
                estado.fecha == null
                    ? 'Elegir día y hora'
                    : Formato.fechaHora(estado.fecha!.toIso8601String()),
              ),
            ),

            const Divider(height: 32),
            TextField(
              controller: _notas,
              decoration: const InputDecoration(
                labelText: 'Notas (opcional)',
                hintText: '¿Algo que la sucursal deba saber?',
              ),
              maxLines: 3,
              onChanged: control.escribirNotas,
            ),

            if (estado.error != null) ...[
              const SizedBox(height: 16),
              Text(
                estado.error!,
                style: TextStyle(color: tema.colorScheme.error),
              ),
            ],

            const SizedBox(height: 24),
            FilledButton(
              onPressed: estado.sePuedeReservar ? _confirmar : null,
              child: estado.ocupado
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Confirmar visita'),
            ),
            if (!estado.sePuedeReservar && !estado.ocupado)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _porQueNo(estado),
                  style: tema.textTheme.bodySmall,
                  textAlign: TextAlign.center,
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Decir qué falta es más útil que un botón gris sin explicación.
  static String _porQueNo(EstadoNuevaReserva estado) {
    if (estado.items.isEmpty) return 'Agregá al menos una prenda.';
    if (estado.sucursalId.isEmpty) return 'Elegí una sucursal.';
    if (estado.fecha == null) return 'Elegí día y hora.';
    if (estado.comprobandoDisponibilidad) {
      return 'Estamos revisando la disponibilidad de las prendas.';
    }
    if (estado.hayFaltantes) {
      return 'Probá con otra sucursal o quitá lo que falta.';
    }
    return '';
  }
}

class _LineaSeleccion extends StatelessWidget {
  const _LineaSeleccion({
    required this.item,
    required this.falta,
    required this.onCantidad,
    required this.onQuitar,
  });

  final ItemReserva item;
  final DisponibilidadVariante? falta;
  final ValueChanged<int> onCantidad;
  final VoidCallback onQuitar;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.producto.isEmpty ? 'Prenda' : item.producto,
                      style: tema.textTheme.bodyMedium,
                    ),
                    if (item.etiqueta.isNotEmpty)
                      Text(item.etiqueta, style: tema.textTheme.bodySmall),
                  ],
                ),
              ),
              IconButton.outlined(
                onPressed: () => onCantidad(item.cantidad - 1),
                icon: const Icon(Icons.remove, size: 18),
                visualDensity: VisualDensity.compact,
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Text(
                  '${item.cantidad}',
                  style: tema.textTheme.titleMedium,
                ),
              ),
              IconButton.outlined(
                onPressed: item.cantidad >= maxUnidadesPorVariante
                    ? null
                    : () => onCantidad(item.cantidad + 1),
                icon: const Icon(Icons.add, size: 18),
                visualDensity: VisualDensity.compact,
              ),
              IconButton(
                onPressed: onQuitar,
                icon: const Icon(Icons.close),
                tooltip: 'Quitar',
              ),
            ],
          ),
          if (falta?.motivo != null)
            Text(
              falta!.motivo!,
              style: tema.textTheme.bodySmall?.copyWith(
                color: tema.colorScheme.error,
              ),
            ),
        ],
      ),
    );
  }
}
