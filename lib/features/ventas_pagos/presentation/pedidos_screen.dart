import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../shared/formato.dart';
import '../../../shared/widgets/estado_vista.dart';
import '../application/pedidos_controller.dart';
import '../domain/commerce_models.dart';

/// «Mis pedidos» (`/mi-cuenta/pedidos`).
///
/// La web muestra una tabla con todas las columnas; en el teléfono cada pedido
/// es una tarjeta con lo que se mira de verdad —número, fecha, estado y
/// total— y el detalle se abre aparte.
class PedidosScreen extends ConsumerStatefulWidget {
  const PedidosScreen({super.key});

  @override
  ConsumerState<PedidosScreen> createState() => _PedidosScreenState();
}

class _PedidosScreenState extends ConsumerState<PedidosScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(pedidosProvider.notifier).cargar());
  }

  @override
  Widget build(BuildContext context) {
    final estado = ref.watch(pedidosProvider);
    final control = ref.read(pedidosProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: const Text('Mis pedidos')),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: control.cargar,
          child: _cuerpo(estado, control),
        ),
      ),
    );
  }

  Widget _cuerpo(EstadoPedidos estado, PedidosController control) {
    if (estado.cargando && estado.pedidos.isEmpty) {
      return const VistaCargando(mensaje: 'Buscando tus pedidos…');
    }
    if (estado.error != null && estado.pedidos.isEmpty) {
      return VistaError(mensaje: estado.error!, onReintentar: control.cargar);
    }
    if (estado.pedidos.isEmpty) {
      return VistaVacia(
        icono: Icons.receipt_long_outlined,
        titulo: 'Todavía no hiciste ningún pedido',
        mensaje: 'Cuando compres algo, acá vas a poder seguirlo etapa por etapa.',
        accionIcono: Icons.storefront_outlined,
        accionTexto: 'Ver el catálogo',
        onAccion: () => context.go('/'),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: estado.pedidos.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, indice) => _TarjetaPedido(pedido: estado.pedidos[indice]),
    );
  }
}

class _TarjetaPedido extends StatelessWidget {
  const _TarjetaPedido({required this.pedido});

  final Pedido pedido;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return InkWell(
      onTap: () => context.push('/mi-cuenta/pedidos/${pedido.id}'),
      borderRadius: BorderRadius.circular(12),
      child: Container(
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
                Text('Pedido ${pedido.number}', style: tema.textTheme.titleSmall),
                const Spacer(),
                Text(Formato.moneda(pedido.total), style: tema.textTheme.titleSmall),
              ],
            ),
            const SizedBox(height: 4),
            Text(Formato.fechaHora(pedido.createdAt), style: tema.textTheme.bodySmall),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ChipEstado(
                  etiqueta: pedido.etiquetaEstado,
                  exportacion: colorDeEstadoPedido(pedido.status),
                  compacto: true,
                ),
                ChipEstado(
                  etiqueta: pedido.etiquetaPago,
                  exportacion: colorDeEstadoPago(pedido.paymentStatus),
                  compacto: true,
                ),
                if (pedido.hasOpenReturn)
                  const ChipEstado(
                    etiqueta: 'Devolución en curso',
                    exportacion: 'aviso',
                    compacto: true,
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '${pedido.items.length} ${pedido.items.length == 1 ? 'prenda' : 'prendas'} · ${pedido.etiquetaMetodo}',
              style: tema.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

/// Traduce el estado a la escala de color de la web (`ok`, `aviso`, `mal`).
String colorDeEstadoPedido(String estado) => switch (estado) {
      'delivered' || 'paid' => 'ok',
      'cancelled' || 'expired' => 'mal',
      'pending_payment' => 'aviso',
      _ => '',
    };

String colorDeEstadoPago(String estado) => switch (estado) {
      'paid' => 'ok',
      'failed' => 'mal',
      'pending' => 'aviso',
      _ => '',
    };

String colorDeEstadoDevolucion(String estado) => switch (estado) {
      'approved' || 'completed' => 'ok',
      'rejected' => 'mal',
      'requested' => 'aviso',
      _ => '',
    };
