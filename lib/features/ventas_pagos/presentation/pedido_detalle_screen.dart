import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../shared/formato.dart';
import '../../../core/network/api_exception.dart';
import '../../../shared/widgets/estado_vista.dart';
import '../application/pedidos_controller.dart';
import '../domain/commerce_models.dart';
import '../infrastructure/commerce_api.dart';
import '../infrastructure/pending_payment_store.dart';
import 'pedidos_screen.dart'
    show colorDeEstadoPedido, colorDeEstadoPago, colorDeEstadoDevolucion;
import 'stripe_checkout_launcher.dart';

/// Detalle de un pedido (`/mi-cuenta/pedidos/:id`).
///
/// Reúne `order-tracker` y `order-returns` de la web en una sola pantalla:
/// seguimiento etapa por etapa, prendas, entrega, y la solicitud de devolución
/// cuando el pedido ya está entregado.
class PedidoDetalleScreen extends ConsumerWidget {
  const PedidoDetalleScreen({super.key, required this.id});

  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final estado = ref.watch(pedidoProvider(id));
    final control = ref.read(pedidoProvider(id).notifier);
    final pedido = estado.pedido;

    if (estado.cargando && pedido == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Pedido')),
        body: const VistaCargando(mensaje: 'Abriendo el pedido…'),
      );
    }
    if (pedido == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Pedido')),
        body: VistaError(
          mensaje: estado.error ?? 'No encontramos este pedido.',
          onReintentar: () => control.cargar(id),
        ),
      );
    }

    final tema = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text('Pedido ${pedido.number}')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ChipEstado(
                  etiqueta: pedido.etiquetaEstado,
                  exportacion: colorDeEstadoPedido(pedido.status),
                ),
                ChipEstado(
                  etiqueta: pedido.etiquetaPago,
                  exportacion: colorDeEstadoPago(pedido.paymentStatus),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              Formato.fechaHora(pedido.createdAt),
              style: tema.textTheme.bodySmall,
            ),

            if (estado.mensaje != null) ...[
              const SizedBox(height: 12),
              Text(
                estado.mensaje!,
                style: TextStyle(color: tema.colorScheme.primary),
              ),
            ],
            if (estado.errorAccion != null) ...[
              const SizedBox(height: 12),
              Text(
                estado.errorAccion!,
                style: TextStyle(color: tema.colorScheme.error),
              ),
            ],

            const Divider(height: 32),
            Text('Seguimiento', style: tema.textTheme.titleSmall),
            const SizedBox(height: 10),
            _Seguimiento(pedido: pedido),

            const Divider(height: 32),
            Text('Prendas', style: tema.textTheme.titleSmall),
            const SizedBox(height: 10),
            for (final item in pedido.items) _LineaPedido(item: item),

            const Divider(height: 32),
            _Resumen(pedido: pedido),

            const Divider(height: 32),
            Text('Entrega', style: tema.textTheme.titleSmall),
            const SizedBox(height: 6),
            _Entrega(pedido: pedido),

            const Divider(height: 32),
            _Devoluciones(estado: estado, control: control),

            const SizedBox(height: 24),
            _AccionesPedido(estado: estado, control: control),
          ],
        ),
      ),
    );
  }
}

/// Las etapas del pedido, con las cumplidas marcadas.
class _Seguimiento extends StatelessWidget {
  const _Seguimiento({required this.pedido});

  final Pedido pedido;

  /// El camino normal de un pedido. Un pedido cancelado se sale de esta línea,
  /// así que en ese caso se muestra solo lo que realmente pasó.
  static const _etapas = [
    'pending_payment',
    'paid',
    'processing',
    'shipped',
    'delivered',
  ];

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final cumplidas = {for (final paso in pedido.tracking) paso.status};
    final cancelado =
        pedido.status == 'cancelled' || pedido.status == 'expired';
    final etapas = cancelado
        ? pedido.tracking.map((t) => t.status).toList()
        : _etapas;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final etapa in etapas)
          _Etapa(
            etiqueta: etiquetaPedido(etapa),
            nota: pedido.tracking
                .where((t) => t.status == etapa)
                .map((t) => t.note)
                .where((n) => n.isNotEmpty)
                .join(' · '),
            fecha: pedido.tracking
                .where((t) => t.status == etapa)
                .map((t) => t.date)
                .firstOrNull,
            cumplida: cumplidas.contains(etapa),
            actual: pedido.status == etapa,
          ),
        if (cancelado)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              pedido.etiquetaEstado,
              style: TextStyle(color: tema.colorScheme.error),
            ),
          ),
        if (pedido.trackingNumber != null &&
            pedido.trackingNumber!.isNotEmpty) ...[
          const SizedBox(height: 10),
          BloqueAyuda(
            titulo: pedido.carrier?.isNotEmpty == true
                ? pedido.carrier!
                : 'Envío',
            detalle: 'Número de seguimiento ${pedido.trackingNumber}',
          ),
        ],
      ],
    );
  }
}

class _Etapa extends StatelessWidget {
  const _Etapa({
    required this.etiqueta,
    required this.nota,
    required this.fecha,
    required this.cumplida,
    required this.actual,
  });

  final String etiqueta;
  final String nota;
  final String? fecha;
  final bool cumplida;
  final bool actual;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final color = cumplida
        ? tema.colorScheme.primary
        : tema.colorScheme.outline;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            cumplida ? Icons.check_circle : Icons.radio_button_unchecked,
            size: 20,
            color: color,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  etiqueta,
                  style: actual
                      ? tema.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        )
                      : tema.textTheme.bodyMedium?.copyWith(color: color),
                ),
                if (fecha != null && fecha!.isNotEmpty)
                  Text(
                    Formato.fechaHora(fecha!),
                    style: tema.textTheme.bodySmall,
                  ),
                if (nota.isNotEmpty)
                  Text(nota, style: tema.textTheme.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LineaPedido extends StatelessWidget {
  const _LineaPedido({required this.item});

  final ItemPedido item;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              width: 56,
              height: 70,
              child: item.imageUrl == null
                  ? Container(color: tema.colorScheme.surfaceContainerHighest)
                  : CachedNetworkImage(
                      imageUrl: item.imageUrl!,
                      fit: BoxFit.cover,
                      errorWidget: (_, __, ___) => Container(
                        color: tema.colorScheme.surfaceContainerHighest,
                      ),
                    ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.name, style: tema.textTheme.bodyMedium),
                Text(
                  [
                    item.size,
                    item.color,
                  ].where((t) => t.isNotEmpty).join(' · '),
                  style: tema.textTheme.bodySmall,
                ),
                Text(
                  '${item.quantity} × ${Formato.moneda(item.unitPrice)}',
                  style: tema.textTheme.bodySmall,
                ),
              ],
            ),
          ),
          Text(
            Formato.moneda(item.lineTotal),
            style: tema.textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }
}

class _Resumen extends StatelessWidget {
  const _Resumen({required this.pedido});

  final Pedido pedido;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return Column(
      children: [
        if (pedido.subtotal != null)
          _Fila(etiqueta: 'Subtotal', valor: Formato.moneda(pedido.subtotal!)),
        for (final descuento in pedido.discounts)
          _Fila(
            etiqueta: descuento.name,
            valor: '− ${Formato.moneda(descuento.amount)}',
          ),
        const SizedBox(height: 4),
        Row(
          children: [
            Text('Total', style: tema.textTheme.titleMedium),
            const Spacer(),
            Text(
              Formato.moneda(pedido.total),
              style: tema.textTheme.titleMedium,
            ),
          ],
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Text(pedido.etiquetaMetodo, style: tema.textTheme.bodySmall),
            const Spacer(),
            if (pedido.paymentReference?.isNotEmpty == true)
              Text(
                'Ref. ${pedido.paymentReference}',
                style: tema.textTheme.bodySmall,
              ),
          ],
        ),
      ],
    );
  }
}

class _Entrega extends StatelessWidget {
  const _Entrega({required this.pedido});

  final Pedido pedido;

  @override
  Widget build(BuildContext context) {
    final direccion = pedido.address;
    final lineas = [
      direccion.recipient,
      direccion.phone,
      direccion.line1,
      [
        direccion.city,
        direccion.country,
      ].where((t) => t?.isNotEmpty == true).join(', '),
    ].where((t) => t != null && t.isNotEmpty).cast<String>().toList();

    if (lineas.isEmpty) {
      return Text(
        'Sin datos de entrega.',
        style: Theme.of(context).textTheme.bodySmall,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [for (final linea in lineas) Text(linea)],
    );
  }
}

/// Devoluciones: las ya solicitadas y el formulario para pedir una nueva.
class _Devoluciones extends StatelessWidget {
  const _Devoluciones({required this.estado, required this.control});

  final EstadoPedido estado;
  final PedidoController control;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final disponibilidad = estado.devoluciones;
    final pedido = estado.pedido!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Cambios y devoluciones', style: tema.textTheme.titleSmall),
        const SizedBox(height: 8),

        if (disponibilidad != null &&
            disponibilidad.devoluciones.isNotEmpty) ...[
          for (final devolucion in disponibilidad.devoluciones)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  ChipEstado(
                    etiqueta: etiquetaDevolucion(devolucion.status),
                    exportacion: colorDeEstadoDevolucion(devolucion.status),
                    compacto: true,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      devolucion.resolutionNote?.isNotEmpty == true
                          ? devolucion.resolutionNote!
                          : devolucion.kind == 'exchange'
                          ? 'Cambio por ${devolucion.replacementSummary ?? 'otra prenda'} · ${devolucion.reason}'
                          : devolucion.reason,
                      style: tema.textTheme.bodySmall,
                    ),
                  ),
                  if (devolucion.kind != 'exchange')
                    Text(
                      Formato.moneda(devolucion.refundAmount),
                      style: tema.textTheme.bodySmall,
                    ),
                ],
              ),
            ),
          const SizedBox(height: 6),
        ],

        if (!estado.sePuedeDevolver)
          Text(
            disponibilidad?.motivo ??
                'Vas a poder pedir una devolución cuando el pedido esté entregado.',
            style: tema.textTheme.bodySmall,
          )
        else ...[
          OutlinedButton(
            onPressed: estado.ocupado
                ? null
                : () => showModalBottomSheet<void>(
                    context: context,
                    isScrollControlled: true,
                    builder: (context) =>
                        _FormularioCambio(estado: estado, control: control),
                  ),
            child: const Text('Solicitar cambio de prenda o talla'),
          ),
          Text(
            'Elegí cuántas unidades querés devolver y contanos por qué.',
            style: tema.textTheme.bodySmall,
          ),
          const SizedBox(height: 10),
          for (final item in pedido.items)
            if (estado.disponiblesDe(item.variantId) > 0)
              _SelectorUnidades(
                item: item,
                elegidas: estado.seleccion[item.variantId] ?? 0,
                tope: estado.disponiblesDe(item.variantId),
                onCambio: (valor) =>
                    control.marcarUnidades(item.variantId, valor),
              ),
          const SizedBox(height: 10),
          TextField(
            decoration: const InputDecoration(
              labelText: 'Motivo',
              hintText: 'Contanos qué pasó con la prenda',
            ),
            maxLines: 3,
            onChanged: control.escribirRazon,
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: estado.sePuedeSolicitarDevolucion
                  ? control.solicitarDevolucion
                  : null,
              child: Text(
                estado.unidadesElegidas == 0
                    ? 'Elegí al menos una prenda'
                    : 'Solicitar devolución de ${estado.unidadesElegidas} '
                          '${estado.unidadesElegidas == 1 ? 'unidad' : 'unidades'}',
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _FormularioCambio extends StatefulWidget {
  const _FormularioCambio({required this.estado, required this.control});
  final EstadoPedido estado;
  final PedidoController control;

  @override
  State<_FormularioCambio> createState() => _FormularioCambioState();
}

class _FormularioCambioState extends State<_FormularioCambio> {
  String requestId = CommerceApi.nuevaClaveSolicitud();
  String? original;
  String? replacement;
  List<OpcionCambio> options = const [];
  int quantity = 1;
  String reason = '';
  String? error;
  bool busy = false;

  int get maxQuantity {
    if (original == null || replacement == null) return 0;
    final available =
        options
            .where((row) => row.variantId == replacement)
            .map((row) => row.available)
            .firstOrNull ??
        0;
    return available < widget.estado.disponiblesDe(original!)
        ? available
        : widget.estado.disponiblesDe(original!);
  }

  Future<void> selectOriginal(String? id) async {
    setState(() {
      requestId = CommerceApi.nuevaClaveSolicitud();
      original = id;
      replacement = null;
      options = const [];
      error = null;
      busy = id != null;
    });
    if (id == null) return;
    try {
      final result = await widget.control.opcionesCambio(id);
      if (mounted && original == id) {
        setState(() => options = result);
      }
    } on ApiException catch (exception) {
      if (mounted) setState(() => error = exception.message);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> submit() async {
    if (original == null ||
        replacement == null ||
        reason.trim().length < 5 ||
        quantity < 1 ||
        quantity > maxQuantity) {
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    final ok = await widget.control.solicitarCambio(
      variantId: original!,
      replacementVariantId: replacement!,
      quantity: quantity,
      reason: reason,
      clientRequestId: requestId,
    );
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop();
    } else {
      setState(() {
        busy = false;
        error =
            'No se pudo registrar el cambio. Revisá la disponibilidad e intentá nuevamente.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = widget.estado.pedido!.items
        .where((item) => widget.estado.disponiblesDe(item.variantId) > 0)
        .toList();
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          20,
          20,
          MediaQuery.viewInsetsOf(context).bottom + 24,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Cambiar una prenda',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              const Text(
                'La nueva prenda se aparta ahora. La original vuelve al stock cuando la recibamos.',
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: original,
                decoration: const InputDecoration(
                  labelText: 'Prenda del pedido',
                ),
                items: [
                  for (final item in items)
                    DropdownMenuItem(
                      value: item.variantId,
                      child: Text(
                        '${item.name} · ${item.size} · ${item.color}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: busy ? null : selectOriginal,
              ),
              if (original != null) ...[
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  key: ValueKey(original),
                  initialValue: replacement,
                  decoration: const InputDecoration(
                    labelText: 'Nueva prenda o talla',
                  ),
                  items: [
                    for (final option in options)
                      DropdownMenuItem(
                        value: option.variantId,
                        child: Text(
                          '${option.productName} · ${option.size} · ${option.color} (${option.available})',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: busy
                      ? null
                      : (value) => setState(() {
                          replacement = value;
                          requestId = CommerceApi.nuevaClaveSolicitud();
                        }),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  initialValue: '1',
                  decoration: const InputDecoration(labelText: 'Cantidad'),
                  keyboardType: TextInputType.number,
                  onChanged: (value) => setState(() {
                    quantity = int.tryParse(value) ?? 0;
                    requestId = CommerceApi.nuevaClaveSolicitud();
                  }),
                ),
                const SizedBox(height: 12),
                TextField(
                  decoration: const InputDecoration(labelText: 'Motivo'),
                  maxLines: 2,
                  onChanged: (value) => setState(() {
                    reason = value;
                    requestId = CommerceApi.nuevaClaveSolicitud();
                  }),
                ),
              ],
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(
                    error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed:
                      busy ||
                          original == null ||
                          replacement == null ||
                          reason.trim().length < 5 ||
                          quantity < 1 ||
                          quantity > maxQuantity
                      ? null
                      : submit,
                  child: const Text('Solicitar cambio'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SelectorUnidades extends StatelessWidget {
  const _SelectorUnidades({
    required this.item,
    required this.elegidas,
    required this.tope,
    required this.onCambio,
  });

  final ItemPedido item;
  final int elegidas;
  final int tope;
  final ValueChanged<int> onCambio;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.name, style: tema.textTheme.bodyMedium),
                Text('Hasta $tope', style: tema.textTheme.bodySmall),
              ],
            ),
          ),
          IconButton.outlined(
            onPressed: elegidas == 0 ? null : () => onCambio(elegidas - 1),
            icon: const Icon(Icons.remove, size: 18),
            visualDensity: VisualDensity.compact,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Text('$elegidas', style: tema.textTheme.titleMedium),
          ),
          IconButton.outlined(
            onPressed: elegidas >= tope ? null : () => onCambio(elegidas + 1),
            icon: const Icon(Icons.add, size: 18),
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }
}

/// Reanudar el pago y cancelar, cuando el estado del pedido lo permite.
class _AccionesPedido extends ConsumerWidget {
  const _AccionesPedido({required this.estado, required this.control});

  final EstadoPedido estado;
  final PedidoController control;

  Future<void> _reanudar(BuildContext context, WidgetRef ref) async {
    final url = await control.reanudarPago();
    if (url == null || !context.mounted) return;
    final pedidoId = estado.pedido?.id;
    if (pedidoId != null) {
      await ref.read(pendingPaymentStoreProvider).save(pedidoId);
    }
    final abierto = await abrirStripeCheckout(url);
    if (!abierto && context.mounted) {
      await mostrarEnlaceStripe(context, url);
    }
  }

  Future<void> _cancelar(BuildContext context) async {
    final razon = await showDialog<String>(
      context: context,
      builder: (context) => const _DialogoCancelar(),
    );
    if (razon != null && razon.isNotEmpty) await control.cancelar(razon);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final puedeActualizarPago =
        estado.pedido?.paymentMethod == 'stripe' &&
        estado.pedido?.paymentStatus != 'paid' &&
        estado.pedido?.status == 'pending_payment';
    if (!estado.sePuedeReanudarPago &&
        !estado.sePuedeCancelar &&
        !puedeActualizarPago) {
      return const SizedBox.shrink();
    }
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        if (estado.sePuedeReanudarPago)
          FilledButton.tonalIcon(
            onPressed: estado.ocupado ? null : () => _reanudar(context, ref),
            icon: const Icon(Icons.credit_card),
            label: const Text('Pagar con tarjeta'),
          ),
        if (puedeActualizarPago)
          OutlinedButton.icon(
            onPressed: estado.ocupado ? null : control.reconciliarPago,
            icon: const Icon(Icons.refresh),
            label: const Text('Actualizar pago'),
          ),
        if (estado.sePuedeCancelar)
          OutlinedButton.icon(
            onPressed: estado.ocupado ? null : () => _cancelar(context),
            icon: const Icon(Icons.close),
            label: const Text('Cancelar pedido'),
          ),
      ],
    );
  }
}

/// Cancelar pide un motivo: el backend lo exige y además queda en la bitácora.
class _DialogoCancelar extends StatefulWidget {
  const _DialogoCancelar();

  @override
  State<_DialogoCancelar> createState() => _DialogoCancelarState();
}

class _DialogoCancelarState extends State<_DialogoCancelar> {
  final _razon = TextEditingController();

  @override
  void dispose() {
    _razon.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('¿Cancelar el pedido?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Se liberan las prendas reservadas. No se puede deshacer.',
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _razon,
            decoration: const InputDecoration(labelText: 'Motivo'),
            onChanged: (_) => setState(() {}),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => context.pop(), child: const Text('Volver')),
        FilledButton(
          onPressed: _razon.text.trim().isEmpty
              ? null
              : () => context.pop(_razon.text.trim()),
          child: const Text('Cancelar pedido'),
        ),
      ],
    );
  }
}

class _Fila extends StatelessWidget {
  const _Fila({required this.etiqueta, required this.valor});

  final String etiqueta;
  final String valor;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return Row(
      children: [
        Text(etiqueta, style: tema.textTheme.bodySmall),
        const Spacer(),
        Text(valor, style: tema.textTheme.bodySmall),
      ],
    );
  }
}
