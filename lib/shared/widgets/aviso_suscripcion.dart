import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/theme.dart';
import '../../features/usuarios_catalogo/application/session_controller.dart';

/// Banner de estado de la suscripción (gracia, solo lectura, por vencer)
/// según la maqueta px-movil de FashionStore SaaS.
///
/// En solo lectura las acciones de venta y reserva en línea se deshabilitan con
/// explicación contextual.
class AvisoSuscripcion extends ConsumerWidget {
  const AvisoSuscripcion({
    super.key,
    this.margen = const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
  });

  final EdgeInsetsGeometry margen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sesion = ref.watch(sessionProvider);
    final colores = Theme.of(context).extension<ColoresEstado>();

    if (sesion.soloLectura) {
      return Padding(
        padding: margen,
        child: _Alerta(
          icono: '!',
          titulo: 'Modo solo lectura activado',
          detalle: sesion.mensajeSoloLectura ??
              'Tu suscripción está vencida. No se pueden registrar ventas ni reservas.',
          colorFondo: colores?.fondoPeligro ?? const Color(0xFFFEE2E2),
          colorBorde:
              colores?.peligro.withValues(alpha: 0.4) ?? const Color(0xFFDC2626),
          colorTexto: colores?.peligro ?? const Color(0xFF991B1B),
          colorCirculo: colores?.peligro ?? const Color(0xFFDC2626),
        ),
      );
    }

    if (sesion.enGracia) {
      final fechaGracia = sesion.graceUntil ?? 'pronto';
      return Padding(
        padding: margen,
        child: _Alerta(
          icono: '!',
          titulo: 'Suscripción en gracia',
          detalle: 'Hasta el $fechaGracia. Luego solo lectura.',
          colorFondo: colores?.fondoPeligro ?? const Color(0xFFFEE2E2),
          colorBorde:
              colores?.peligro.withValues(alpha: 0.4) ?? const Color(0xFFDC2626),
          colorTexto: colores?.peligro ?? const Color(0xFF991B1B),
          colorCirculo: colores?.peligro ?? const Color(0xFFDC2626),
        ),
      );
    }

    if (sesion.porVencer) {
      final dias = sesion.usuario?.suscripcion?.diasRestantes ?? 0;
      return Padding(
        padding: margen,
        child: _Alerta(
          icono: '!',
          titulo: 'Suscripción por vencer',
          detalle: 'Quedan $dias días. Luego pasa a gracia.',
          colorFondo: colores?.fondoAdvertencia ?? const Color(0xFFFEF3C7),
          colorBorde:
              colores?.advertencia.withValues(alpha: 0.4) ??
              const Color(0xFFD97706),
          colorTexto: colores?.advertencia ?? const Color(0xFF92400E),
          colorCirculo: colores?.advertencia ?? const Color(0xFFD97706),
        ),
      );
    }

    return const SizedBox.shrink();
  }

  /// Indica si la cuenta tiene permitido operar (vender, reservar en línea).
  static bool puedeOperar(WidgetRef ref) {
    return !ref.watch(sessionProvider).soloLectura;
  }

  /// Retorna la explicación de por qué no puede operar si está en solo lectura.
  static String? motivoBloqueo(
    WidgetRef ref, [
    String accion = 'realizar esta acción',
  ]) {
    final sesion = ref.watch(sessionProvider);
    if (!sesion.soloLectura) return null;
    return 'No es posible $accion: tu empresa está en modo solo lectura por suscripción vencida.';
  }
}

class _Alerta extends StatelessWidget {
  const _Alerta({
    required this.icono,
    required this.titulo,
    required this.detalle,
    required this.colorFondo,
    required this.colorBorde,
    required this.colorTexto,
    required this.colorCirculo,
  });

  final String icono;
  final String titulo;
  final String detalle;
  final Color colorFondo;
  final Color colorBorde;
  final Color colorTexto;
  final Color colorCirculo;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorFondo,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colorBorde),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 18,
              height: 18,
              margin: const EdgeInsets.only(top: 1),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: colorCirculo,
              ),
              alignment: Alignment.center,
              child: Text(
                icono,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 11,
                  height: 1,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    titulo,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: colorTexto,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    detalle,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: colorTexto,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Envuelve un botón o acción interactiva (vender, reservar en línea).
/// Si la suscripción está en solo lectura, deshabilita la acción y muestra
/// la explicación debajo.
class AccionSoloLectura extends ConsumerWidget {
  const AccionSoloLectura({
    super.key,
    required this.onPressed,
    required this.child,
    this.accion = 'vender',
    this.mensajeExplicacion,
  });

  final VoidCallback? onPressed;
  final Widget Function(
    BuildContext context,
    VoidCallback? callback,
    bool bloqueado,
  )
  child;
  final String accion;
  final String? mensajeExplicacion;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sesion = ref.watch(sessionProvider);
    final bloqueado = sesion.soloLectura;

    final VoidCallback? callback = bloqueado ? null : onPressed;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        child(context, callback, bloqueado),
        if (bloqueado) ...[
          const SizedBox(height: 4),
          Text(
            mensajeExplicacion ??
                'Acción deshabilitada ($accion): suscripción en modo solo lectura.',
            style: TextStyle(
              fontSize: 11,
              color: Theme.of(context).colorScheme.error,
              fontStyle: FontStyle.italic,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ],
    );
  }
}
