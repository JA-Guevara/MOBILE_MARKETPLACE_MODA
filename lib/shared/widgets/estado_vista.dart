import 'package:flutter/material.dart';

/// Piezas compartidas para que todas las pantallas hablen el mismo idioma:
/// cargando, error con reintentar, vacío, chip de estado y encabezado plegado.
class VistaCargando extends StatelessWidget {
  const VistaCargando({super.key, this.mensaje = 'Cargando…'});

  final String mensaje;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 12),
          Text(mensaje),
        ],
      ),
    );
  }
}

/// Error amigable con botón para reintentar la carga.
class VistaError extends StatelessWidget {
  const VistaError({super.key, required this.mensaje, this.onReintentar});

  final String mensaje;
  final VoidCallback? onReintentar;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off, size: 40, color: tema.colorScheme.outline),
            const SizedBox(height: 12),
            Text(
              mensaje,
              textAlign: TextAlign.center,
              style: tema.textTheme.bodyMedium,
            ),
            if (onReintentar != null) ...[
              const SizedBox(height: 12),
              FilledButton.tonalIcon(
                onPressed: onReintentar,
                icon: const Icon(Icons.refresh),
                label: const Text('Reintentar'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Lista vacía con mensaje y acción opcional.
class VistaVacia extends StatelessWidget {
  const VistaVacia({
    super.key,
    required this.icono,
    required this.titulo,
    this.mensaje,
    this.accionIcono,
    this.accionTexto,
    this.onAccion,
  });

  final IconData icono;
  final String titulo;
  final String? mensaje;
  final IconData? accionIcono;
  final String? accionTexto;
  final VoidCallback? onAccion;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icono, size: 48, color: tema.colorScheme.outline),
            const SizedBox(height: 12),
            Text(titulo, style: tema.textTheme.titleMedium),
            if (mensaje != null) ...[
              const SizedBox(height: 6),
              Text(
                mensaje!,
                textAlign: TextAlign.center,
                style: tema.textTheme.bodySmall,
              ),
            ],
            if (onAccion != null) ...[
              const SizedBox(height: 16),
              FilledButton.tonalIcon(
                onPressed: onAccion,
                icon: Icon(accionIcono ?? Icons.add),
                label: Text(accionTexto ?? 'Comenzar'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Chip de color con la etiqueta de un estado de pedido/reserva/devolución.
/// Usa los mismos colores de resaltado que la web (verde/señal/semáforo).
class ChipEstado extends StatelessWidget {
  const ChipEstado({super.key, required this.etiqueta, required this.exportacion, this.compacto = false});

  final String etiqueta;

  /// Valor en la escala de la web: `ok`, `aviso`, `mal` (y neutro por defecto).
  final String exportacion;

  final bool compacto;

  @override
  Widget build(BuildContext context) {
    final Color color = switch (exportacion) {
      'ok' => const Color(0xFF2E7D32),
      'aviso' => const Color(0xFFEF6C00),
      'mal' => const Color(0xFFC62828),
      _ => Theme.of(context).colorScheme.outline,
    };
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compacto ? 8 : 10,
        vertical: compacto ? 3 : 5,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        etiqueta,
        style: TextStyle(
          color: color,
          fontSize: compacto ? 11 : 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// Enlace de ayuda con texto y el porqué, como los bloques de la web.
class BloqueAyuda extends StatelessWidget {
  const BloqueAyuda({super.key, required this.titulo, required this.detalle});

  final String titulo;
  final String detalle;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: tema.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 18, color: tema.colorScheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: '$titulo: ', style: tema.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
                  TextSpan(text: detalle, style: tema.textTheme.bodySmall),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
