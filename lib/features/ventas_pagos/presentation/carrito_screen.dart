import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../shared/formato.dart';
import '../../../shared/widgets/estado_vista.dart';
import '../application/carrito_controller.dart';
import '../application/pedidos_controller.dart';
import '../domain/commerce_models.dart';
import '../infrastructure/pending_payment_store.dart';
import 'stripe_checkout_launcher.dart';

/// Carrito y checkout (`/carrito`).
///
/// Es `cart-page.component.ts` en una sola columna. La web separa el carrito
/// del paso de entrega con un botón; acá todo se ve de corrido porque en un
/// teléfono el scroll cuesta menos que un paso extra, y el botón de confirmar
/// queda fijo abajo con el total a la vista.
class CarritoScreen extends ConsumerStatefulWidget {
  const CarritoScreen({super.key});

  @override
  ConsumerState<CarritoScreen> createState() => _CarritoScreenState();
}

class _CarritoScreenState extends ConsumerState<CarritoScreen> {
  final _cupon = TextEditingController();

  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(carritoProvider.notifier).cargar());
  }

  @override
  void dispose() {
    _cupon.dispose();
    super.dispose();
  }

  Future<void> _comprar() async {
    final resultado = await ref.read(carritoProvider.notifier).comprar();
    if (!mounted || resultado == null) return;
    unawaited(ref.read(pedidosProvider.notifier).cargar());

    if (resultado.errorPago != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'El pedido fue creado, pero no pudimos iniciar Stripe: ${resultado.errorPago}',
          ),
        ),
      );
      context.go('/mi-cuenta/pedidos/${resultado.pedido.id}');
      return;
    }

    // Stripe corre fuera de la app: se abre en el navegador del sistema y el
    // pedido queda creado igual, así que si la persona no vuelve, el pedido
    // sigue en «Mis pedidos» esperando el pago.
    final url = resultado.urlPago;
    if (url != null && url.isNotEmpty) {
      await ref.read(pendingPaymentStoreProvider).save(resultado.pedido.id);
      final abierto = await abrirStripeCheckout(url);
      if (!abierto) {
        if (mounted) {
          await mostrarEnlaceStripe(context, url);
          if (!mounted) return;
          context.go('/mi-cuenta/pedidos/${resultado.pedido.id}');
        }
        return;
      }
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          url == null || url.isEmpty
              ? 'Pedido ${resultado.pedido.number} creado.'
              : 'Completá el pago; al volver verificaremos el pedido automáticamente.',
        ),
      ),
    );
    context.go('/mi-cuenta/pedidos/${resultado.pedido.id}');
  }

  @override
  Widget build(BuildContext context) {
    final estado = ref.watch(carritoProvider);
    final control = ref.read(carritoProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mi carrito'),
        actions: [
          IconButton(
            onPressed: estado.cargando || estado.ocupado
                ? null
                : control.cargar,
            icon: const Icon(Icons.refresh),
            tooltip: 'Actualizar carrito',
          ),
          if (!estado.vacio)
            IconButton(
              onPressed: estado.ocupado
                  ? null
                  : () => _confirmarVaciado(control),
              icon: const Icon(Icons.delete_sweep_outlined),
              tooltip: 'Vaciar carrito',
            ),
        ],
      ),
      body: SafeArea(child: _cuerpo(estado, control)),
      bottomNavigationBar: estado.vacio
          ? null
          : _BarraTotal(estado: estado, onComprar: _comprar),
    );
  }

  Widget _cuerpo(EstadoCarrito estado, CarritoController control) {
    if (estado.cargando && estado.carrito == null) {
      return const VistaCargando(mensaje: 'Abriendo tu carrito…');
    }
    if (estado.carrito == null) {
      return VistaError(
        mensaje: estado.error ?? 'No pudimos abrir tu carrito.',
        onReintentar: control.cargar,
      );
    }
    if (estado.vacio) {
      final pedido = estado.ultimoPedido;
      return VistaVacia(
        icono: pedido == null
            ? Icons.shopping_bag_outlined
            : Icons.receipt_long_outlined,
        titulo: pedido == null
            ? 'Tu carrito está vacío'
            : 'Pedido ${pedido.number} creado',
        mensaje: pedido == null
            ? 'Elegí una prenda del catálogo y volvé cuando quieras.'
            : 'Las prendas fueron apartadas para este pedido. Abrilo para pagar '
                  'con tarjeta o revisar su estado.',
        accionIcono: pedido == null
            ? Icons.storefront_outlined
            : Icons.credit_card_outlined,
        accionTexto: pedido == null ? 'Ver el catálogo' : 'Ver pedido y pagar',
        onAccion: () => pedido == null
            ? context.go('/')
            : context.go('/mi-cuenta/pedidos/${pedido.id}'),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        for (final item in estado.items)
          _LineaCarrito(
            item: item,
            ocupado: estado.ocupado,
            onCantidad: (cantidad) => control.cambiarCantidad(item, cantidad),
            onQuitar: () => control.quitar(item),
          ),
        const SizedBox(height: 8),
        // Dos avisos distintos a propósito: «probá otra sucursal» solo sirve
        // si queda alguna por probar. Cuando ya se probaron todas, repetirlo
        // manda a la persona a dar vueltas sin salida.
        if (estado.haySobregiro)
          estado.ningunaSucursalCubre
              ? const BloqueAyuda(
                  titulo: 'Ninguna sucursal tiene todo',
                  detalle:
                      'Revisamos todas las sucursales y en ninguna alcanzan las '
                      'unidades que pediste. Bajá la cantidad o quitá la prenda '
                      'que falta para poder confirmar.',
                )
              : const BloqueAyuda(
                  titulo: 'Sin stock suficiente',
                  detalle:
                      'Alguna prenda pide más unidades de las que hay en la '
                      'sucursal elegida. Bajá la cantidad o probá con otra '
                      'sucursal.',
                ),
        const Divider(height: 32),
        _Sucursales(estado: estado, onElegir: control.elegirSucursal),
        const Divider(height: 32),
        _Cupon(
          controlador: _cupon,
          estado: estado,
          onEscribir: control.escribirCupon,
          onAplicar: control.aplicarCupon,
        ),
        const Divider(height: 32),
        _Entrega(estado: estado, control: control),
        const Divider(height: 32),
        _MetodoPago(estado: estado, onElegir: control.elegirMetodoPago),
        if (estado.error != null) ...[
          const SizedBox(height: 16),
          Text(
            estado.error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
      ],
    );
  }

  Future<void> _confirmarVaciado(CarritoController control) async {
    // Vaciar borra todo de una y no se puede deshacer: se pregunta.
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('¿Vaciar el carrito?'),
        content: const Text(
          'Se quitan todas las prendas. No se puede deshacer.',
        ),
        actions: [
          TextButton(
            onPressed: () => context.pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => context.pop(true),
            child: const Text('Vaciar'),
          ),
        ],
      ),
    );
    if (confirmado == true) await control.vaciar();
  }
}

/// Una prenda del carrito: foto, datos, cantidad y quitar.
class _LineaCarrito extends StatelessWidget {
  const _LineaCarrito({
    required this.item,
    required this.ocupado,
    required this.onCantidad,
    required this.onQuitar,
  });

  final ItemCarrito item;
  final bool ocupado;
  final ValueChanged<int> onCantidad;
  final VoidCallback onQuitar;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final excedido = item.quantity > item.available;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(
              width: 76,
              height: 96,
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
                Text(item.name, style: tema.textTheme.titleSmall),
                Text(
                  [
                    item.size,
                    item.color,
                  ].where((t) => t.isNotEmpty).join(' · '),
                  style: tema.textTheme.bodySmall,
                ),
                Text(
                  Formato.moneda(item.unitPrice),
                  style: tema.textTheme.bodySmall,
                ),
                if (excedido)
                  Text(
                    'Solo quedan ${item.available}',
                    style: tema.textTheme.bodySmall?.copyWith(
                      color: tema.colorScheme.error,
                    ),
                  ),
                const SizedBox(height: 6),
                // En teléfonos angostos el control de cantidad y «Quitar»
                // superaban el ancho disponible. `Wrap` conserva los botones
                // juntos cuando caben y baja «Quitar» a otra línea cuando no.
                Wrap(
                  spacing: 4,
                  runSpacing: 2,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    IconButton.outlined(
                      onPressed: ocupado
                          ? null
                          : () => onCantidad(item.quantity - 1),
                      icon: const Icon(Icons.remove, size: 18),
                      tooltip: 'Quitar una',
                      visualDensity: VisualDensity.compact,
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Text(
                        '${item.quantity}',
                        style: tema.textTheme.titleMedium,
                      ),
                    ),
                    IconButton.outlined(
                      // El tope es el stock de la sucursal: ofrecer más es
                      // prometer algo que el pedido después rechaza.
                      onPressed: ocupado || item.quantity >= item.available
                          ? null
                          : () => onCantidad(item.quantity + 1),
                      icon: const Icon(Icons.add, size: 18),
                      tooltip: 'Agregar una',
                      visualDensity: VisualDensity.compact,
                    ),
                    TextButton(
                      onPressed: ocupado ? null : onQuitar,
                      child: const Text('Quitar'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(left: 8, top: 2),
            child: Text(
              Formato.moneda(item.lineTotal),
              style: tema.textTheme.titleSmall,
            ),
          ),
        ],
      ),
    );
  }
}

class _Sucursales extends StatelessWidget {
  const _Sucursales({required this.estado, required this.onElegir});

  final EstadoCarrito estado;
  final ValueChanged<String> onElegir;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Sucursal', style: tema.textTheme.titleSmall),
        const SizedBox(height: 4),
        Text(
          'De acá salen tus prendas. El stock disponible se calcula contra esta sucursal.',
          style: tema.textTheme.bodySmall,
        ),
        const SizedBox(height: 10),
        if (estado.sucursales.isEmpty)
          Text('No hay sucursales publicadas.', style: tema.textTheme.bodySmall)
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final sucursal in estado.sucursales)
                ChoiceChip(
                  label: Text(sucursal.nombre),
                  selected: estado.sucursalId == sucursal.id,
                  onSelected: estado.ocupado
                      ? null
                      : (_) => onElegir(sucursal.id),
                ),
            ],
          ),
      ],
    );
  }
}

class _Cupon extends StatelessWidget {
  const _Cupon({
    required this.controlador,
    required this.estado,
    required this.onEscribir,
    required this.onAplicar,
  });

  final TextEditingController controlador;
  final EstadoCarrito estado;
  final ValueChanged<String> onEscribir;
  final VoidCallback onAplicar;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Cupón', style: tema.textTheme.titleSmall),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: controlador,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(
                  hintText: 'Código de descuento',
                ),
                onChanged: onEscribir,
                onSubmitted: (_) => onAplicar(),
              ),
            ),
            const SizedBox(width: 10),
            FilledButton.tonal(
              onPressed: estado.ocupado ? null : onAplicar,
              child: const Text('Aplicar'),
            ),
          ],
        ),
        if (estado.mensajeCupon != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              estado.mensajeCupon!,
              style: TextStyle(color: tema.colorScheme.primary),
            ),
          ),
        if (estado.errorCupon != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              estado.errorCupon!,
              style: TextStyle(color: tema.colorScheme.error),
            ),
          ),
      ],
    );
  }
}

/// Dirección de entrega: una guardada o una escrita a mano.
class _Entrega extends StatelessWidget {
  const _Entrega({required this.estado, required this.control});

  final EstadoCarrito estado;
  final CarritoController control;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final entrega = estado.entrega;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Entrega', style: tema.textTheme.titleSmall),
        const SizedBox(height: 10),
        if (estado.guardadas.isNotEmpty) ...[
          RadioGroup<String>(
            groupValue: estado.direccionGuardadaId,
            onChanged: (id) => control.elegirGuardada(id ?? ''),
            child: Column(
              children: [
                for (final guardada in estado.guardadas)
                  RadioListTile<String>(
                    value: guardada.id,
                    contentPadding: EdgeInsets.zero,
                    title: Text(guardada.label),
                    subtitle: Text(
                      '${guardada.addressLine} · ${guardada.city}',
                    ),
                  ),
                const RadioListTile<String>(
                  value: '',
                  contentPadding: EdgeInsets.zero,
                  title: Text('Usar otra dirección'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],
        // Los campos se muestran siempre: con una guardada elegida vienen
        // llenos y se pueden corregir sin perder la selección.
        _Campo(
          etiqueta: 'Quién recibe',
          valor: entrega.destinatario,
          onCambio: (v) =>
              control.escribirEntrega(entrega.copyWith(destinatario: v)),
        ),
        _Campo(
          etiqueta: 'Teléfono',
          valor: entrega.telefono,
          teclado: TextInputType.phone,
          onCambio: (v) =>
              control.escribirEntrega(entrega.copyWith(telefono: v)),
        ),
        _Campo(
          etiqueta: 'Dirección',
          valor: entrega.linea,
          onCambio: (v) => control.escribirEntrega(entrega.copyWith(linea: v)),
        ),
        _Campo(
          etiqueta: 'Ciudad',
          valor: entrega.ciudad,
          onCambio: (v) => control.escribirEntrega(entrega.copyWith(ciudad: v)),
        ),
        _Campo(
          etiqueta: 'Código postal (opcional)',
          valor: entrega.codigoPostal,
          onCambio: (v) =>
              control.escribirEntrega(entrega.copyWith(codigoPostal: v)),
        ),
        if (estado.direccionGuardadaId.isEmpty)
          CheckboxListTile(
            value: estado.guardarEnPerfil,
            onChanged: (v) => control.alternarGuardarEnPerfil(v ?? false),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: const Text('Guardar esta dirección en mi perfil'),
          ),
      ],
    );
  }
}

/// Campo de texto que refleja el estado del controlador sin perder el cursor.
class _Campo extends StatefulWidget {
  const _Campo({
    required this.etiqueta,
    required this.valor,
    required this.onCambio,
    this.teclado,
  });

  final String etiqueta;
  final String valor;
  final ValueChanged<String> onCambio;
  final TextInputType? teclado;

  @override
  State<_Campo> createState() => _CampoState();
}

class _CampoState extends State<_Campo> {
  late final TextEditingController _texto = TextEditingController(
    text: widget.valor,
  );

  @override
  void didUpdateWidget(_Campo anterior) {
    super.didUpdateWidget(anterior);
    // Solo se pisa el texto cuando el cambio vino de afuera (elegir una
    // dirección guardada). Hacerlo siempre mandaría el cursor al inicio en
    // cada tecla.
    if (widget.valor != _texto.text && widget.valor != anterior.valor) {
      _texto.value = TextEditingValue(
        text: widget.valor,
        selection: TextSelection.collapsed(offset: widget.valor.length),
      );
    }
  }

  @override
  void dispose() {
    _texto.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: _texto,
        keyboardType: widget.teclado,
        decoration: InputDecoration(labelText: widget.etiqueta),
        onChanged: widget.onCambio,
      ),
    );
  }
}

class _MetodoPago extends StatelessWidget {
  const _MetodoPago({required this.estado, required this.onElegir});

  final EstadoCarrito estado;
  final ValueChanged<String> onElegir;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Cómo querés pagar', style: tema.textTheme.titleSmall),
        RadioGroup<String>(
          groupValue: estado.metodoPago,
          onChanged: (v) => onElegir(v ?? 'manual'),
          child: const Column(
            children: [
              RadioListTile<String>(
                value: 'manual',
                contentPadding: EdgeInsets.zero,
                title: Text('Coordinar efectivo o transferencia'),
              ),
              RadioListTile<String>(
                value: 'stripe',
                contentPadding: EdgeInsets.zero,
                title: Text('Tarjeta · Stripe'),
                subtitle: Text('Se abre en el navegador y volvés a la app.'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Al confirmar se crea el pedido y se reservan las prendas. El pago se '
          'confirma por separado.',
          style: tema.textTheme.bodySmall,
        ),
      ],
    );
  }
}

/// Total y botón de confirmar, siempre a la vista.
class _BarraTotal extends StatelessWidget {
  const _BarraTotal({required this.estado, required this.onComprar});

  final EstadoCarrito estado;
  final VoidCallback onComprar;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final carrito = estado.carrito;
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
        decoration: BoxDecoration(
          color: tema.colorScheme.surface,
          border: Border(top: BorderSide(color: tema.colorScheme.outline)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (carrito != null && carrito.discountTotal > 0) ...[
              _Fila(
                etiqueta: 'Subtotal',
                valor: Formato.moneda(carrito.subtotal),
              ),
              _Fila(
                etiqueta: 'Descuentos',
                valor: '− ${Formato.moneda(carrito.discountTotal)}',
              ),
              const SizedBox(height: 4),
            ],
            Row(
              children: [
                Text('Total', style: tema.textTheme.titleMedium),
                const Spacer(),
                Text(
                  Formato.moneda(carrito?.total ?? 0),
                  style: tema.textTheme.titleLarge,
                ),
              ],
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: estado.sePuedeComprar ? onComprar : null,
                child: estado.ocupado
                    ? Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            estado.metodoPago == 'stripe'
                                ? 'Conectando con Stripe…'
                                : 'Creando pedido…',
                          ),
                        ],
                      )
                    : const Text('Confirmar pedido'),
              ),
            ),
            if (!estado.sePuedeComprar &&
                !estado.ocupado &&
                !estado.entrega.completo)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  'Completá los datos de entrega para confirmar.',
                  style: tema.textTheme.bodySmall,
                ),
              ),
          ],
        ),
      ),
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
