import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/offline/conectividad.dart';
import '../../app/theme.dart';

class IndicadorConexion extends ConsumerWidget {
  const IndicadorConexion({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final conexion = ref.watch(conectividadProvider);
    final online = conexion.asData?.value;
    final colores = Theme.of(context).extension<ColoresEstado>()!;
    final color = online == null
        ? colores.info
        : online
        ? colores.exito
        : colores.peligro;
    return Padding(
      padding: const EdgeInsets.all(8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: color.withValues(alpha: .12),
          borderRadius: BorderRadius.circular(30),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                online == null
                    ? Icons.more_horiz
                    : online
                    ? Icons.circle
                    : Icons.wifi_off,
                size: 12,
                color: color,
              ),
              const SizedBox(width: 6),
              Text(
                online == null
                    ? 'Comprobando'
                    : online
                    ? 'En línea'
                    : 'Sin conexión',
                style: TextStyle(color: color, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
