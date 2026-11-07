import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../domain/reserva.dart';
import '../infrastructure/reservas_api.dart';
import '../../../core/network/api_exception.dart';

class CompraReserva extends ConsumerWidget {
  const CompraReserva({
    super.key,
    required this.reserva,
    required this.onActualizar,
  });
  final Reserva reserva;
  final Future<void> Function() onActualizar;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (reserva.pedidoId != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Pedido ${reserva.pedidoNumero ?? ''} · ${reserva.estadoPago == 'paid' ? 'Pagado' : 'Pendiente de pago'}',
          ),
          TextButton(
            onPressed: () =>
                context.push('/mi-cuenta/pedidos/${reserva.pedidoId}'),
            child: const Text('Ver pedido y pago'),
          ),
        ],
      );
    }
    if (!['pending', 'confirmed', 'ready', 'attended'].contains(reserva.estado)) {
      return const SizedBox.shrink();
    }
    return OutlinedButton(
      onPressed: () async {
        final quantities = {
          for (final item in reserva.items) item.variantId: item.cantidad,
        };
        var method = 'manual';
        var busy = false;
        String? error;
        final result = await showDialog<Map<String, dynamic>>(
          context: context,
          barrierDismissible: false,
          builder: (dialogContext) => StatefulBuilder(
            builder: (context, setDialogState) => AlertDialog(
              title: const Text('Comprar prendas reservadas'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Elegí las prendas que te llevás. Revisarás el total vigente antes de pagar. Las demás se liberan.',
                    ),
                    for (final item in reserva.items)
                      DropdownButtonFormField<int>(
                        initialValue: quantities[item.variantId],
                        isExpanded: true,
                        decoration: InputDecoration(
                          labelText:
                              '${item.producto} · ${item.talla} · ${item.color}',
                        ),
                        items: [
                          for (var q = 0; q <= item.cantidad; q++)
                            DropdownMenuItem(
                              value: q,
                              child: Text('$q unidades'),
                            ),
                        ],
                        onChanged: busy
                            ? null
                            : (value) => setDialogState(
                                () => quantities[item.variantId] = value ?? 0,
                              ),
                      ),
                    DropdownButtonFormField<String>(
                      initialValue: method,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Forma de pago',
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'manual',
                          child: Text('Coordinar con la tienda'),
                        ),
                        DropdownMenuItem(
                          value: 'stripe',
                          child: Text('Tarjeta · Stripe'),
                        ),
                      ],
                      onChanged: busy
                          ? null
                          : (value) => setDialogState(
                              () => method = value ?? 'manual',
                            ),
                    ),
                    if (error != null)
                      Text(
                        error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: busy
                      ? null
                      : () => Navigator.of(dialogContext).pop(),
                  child: const Text('Volver'),
                ),
                FilledButton(
                  onPressed: busy
                      ? null
                      : () async {
                          if (!quantities.values.any((q) => q > 0)) {
                            setDialogState(
                              () => error = 'Elegí al menos una prenda.',
                            );
                            return;
                          }
                          setDialogState(() {
                            busy = true;
                            error = null;
                          });
                          try {
                            final result = await ref
                                .read(reservasApiProvider)
                                .aPedido(reserva.id, method, quantities);
                            if (dialogContext.mounted) {
                              Navigator.of(dialogContext).pop(result);
                            }
                          } on ApiException catch (e) {
                            if (dialogContext.mounted) {
                              setDialogState(() {
                                busy = false;
                                error = e.message;
                              });
                            }
                          } catch (_) {
                            if (dialogContext.mounted) {
                              setDialogState(() {
                                busy = false;
                                error =
                                    'No se pudo crear el pedido. Revisá tu conexión e intentá nuevamente.';
                              });
                            }
                          }
                        },
                  child: Text(
                    busy ? 'Creando…' : 'Crear pedido y revisar total',
                  ),
                ),
              ],
            ),
          ),
        );
        if (result != null) {
          await onActualizar();
          if (context.mounted) {
            context.push('/mi-cuenta/pedidos/${result['id']}');
          }
        }
      },
      child: const Text('Comprar prendas de esta reserva'),
    );
  }
}
