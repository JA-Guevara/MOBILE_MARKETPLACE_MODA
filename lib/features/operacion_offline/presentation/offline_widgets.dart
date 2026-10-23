import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../app/theme.dart';
import '../application/catalogo_offline_controller.dart';

String fechaLocal(DateTime? fecha) => fecha == null
    ? 'Nunca'
    : DateFormat('dd/MM/yyyy HH:mm').format(fecha.toLocal());
String montoLocal(double precio) =>
    'Bs ${precio.toStringAsFixed(precio.truncateToDouble() == precio ? 0 : 2)}';

class PanelOffline extends StatelessWidget {
  const PanelOffline({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: 12),
    elevation: 1,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
      side: BorderSide(
        color: Theme.of(context).colorScheme.outline.withValues(alpha: .6),
      ),
    ),
    child: Padding(padding: const EdgeInsets.all(16), child: child),
  );
}

class AvisoOffline extends StatelessWidget {
  const AvisoOffline(
    this.texto, {
    super.key,
    this.peligro = false,
    this.info = false,
  });
  final String texto;
  final bool peligro, info;
  @override
  Widget build(BuildContext context) {
    final colores =
        Theme.of(context).extension<ColoresEstado>() ?? ColoresEstado.claro;
    final color = peligro
        ? colores.peligro
        : info
        ? colores.info
        : colores.advertencia;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .1),
        border: Border.all(color: color.withValues(alpha: .4)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            info ? Icons.info_outline : Icons.warning_amber_rounded,
            color: color,
            size: 18,
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(texto)),
        ],
      ),
    );
  }
}

class ImagenPrendaOffline extends ConsumerWidget {
  const ImagenPrendaOffline(this.url, {super.key});
  final String? url;
  @override
  Widget build(BuildContext context, WidgetRef ref) => ClipRRect(
    borderRadius: BorderRadius.circular(9),
    child: SizedBox(
      width: 68,
      height: 82,
      child: ColoredBox(
        color: Theme.of(context).colorScheme.primary.withValues(alpha: .08),
        child: url == null || url!.isEmpty
            ? const Icon(Icons.checkroom)
            : FutureBuilder<File?>(
                future: ref.watch(imagenesOfflineProvider).leer(url!),
                builder: (context, s) => s.data == null
                    ? const Icon(Icons.checkroom)
                    : Image.file(
                        s.data!,
                        fit: BoxFit.cover,
                        errorBuilder: (c, e, st) => const Icon(Icons.checkroom),
                      ),
              ),
      ),
    ),
  );
}

class EstadoVacioOffline extends StatelessWidget {
  const EstadoVacioOffline({super.key, required this.accion});
  final VoidCallback accion;
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.phonelink_off, size: 48),
          const SizedBox(height: 20),
          Text(
            'Aún no hay datos sin conexión',
            style: Theme.of(context).textTheme.titleLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          const Text(
            'Conéctate al menos una vez para descargar el catálogo de tu empresa.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: accion,
            child: const Text('Preparar modo sin conexión'),
          ),
        ],
      ),
    ),
  );
}
