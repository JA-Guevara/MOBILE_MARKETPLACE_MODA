import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../domain/commerce_models.dart';
import '../infrastructure/commerce_api.dart';
import 'commerce_providers.dart';

/// Lista de pedidos del cliente.
class EstadoPedidos {
  const EstadoPedidos({
    this.pedidos = const [],
    this.cargando = true,
    this.error,
  });

  final List<Pedido> pedidos;
  final bool cargando;
  final String? error;

  EstadoPedidos copyWith({
    List<Pedido>? pedidos,
    bool? cargando,
    String? error,
    bool limpiarError = false,
  }) => EstadoPedidos(
    pedidos: pedidos ?? this.pedidos,
    cargando: cargando ?? this.cargando,
    error: limpiarError ? null : (error ?? this.error),
  );
}

/// «Mis pedidos» (`orders-page.component.ts` en su modo cliente).
class PedidosController extends StateNotifier<EstadoPedidos> {
  PedidosController(this._comercio) : super(const EstadoPedidos());

  final CommerceApi _comercio;

  Future<void> cargar() async {
    state = state.copyWith(cargando: true, limpiarError: true);
    try {
      state = state.copyWith(
        pedidos: await _comercio.pedidos(),
        cargando: false,
      );
    } on ApiException catch (error) {
      state = state.copyWith(cargando: false, error: error.message);
    }
  }
}

final StateNotifierProvider<PedidosController, EstadoPedidos> pedidosProvider =
    StateNotifierProvider<PedidosController, EstadoPedidos>(
      (ref) => PedidosController(ref.watch(commerceApiProvider)),
    );

// --- Detalle de un pedido ------------------------------------------------

/// Un pedido abierto: seguimiento, devoluciones y las acciones del cliente.
class EstadoPedido {
  const EstadoPedido({
    this.pedido,
    this.devoluciones,
    this.seleccion = const {},
    this.razon = '',
    this.cargando = true,
    this.ocupado = false,
    this.error,
    this.errorAccion,
    this.mensaje,
  });

  final Pedido? pedido;

  /// Qué se puede devolver y qué se devolvió ya. `null` mientras no se leyó.
  final DisponibilidadDevolucion? devoluciones;

  /// Unidades marcadas para devolver, por `variant_id`.
  final Map<String, int> seleccion;

  final String razon;
  final bool cargando;
  final bool ocupado;
  final String? error;
  final String? errorAccion;
  final String? mensaje;

  /// El backend solo acepta cancelar mientras el pedido no se despachó.
  bool get sePuedeCancelar =>
      pedido != null &&
      const ['pending_payment', 'paid', 'processing'].contains(pedido!.status);

  /// Stripe deja el pedido creado y sin pagar si la persona abandona el
  /// checkout; reabrirlo es la forma de terminar sin rehacer el pedido.
  bool get sePuedeReanudarPago =>
      pedido != null &&
      pedido!.paymentMethod == 'stripe' &&
      pedido!.paymentStatus != 'paid' &&
      pedido!.status == 'pending_payment';

  bool get sePuedeDevolver => devoluciones?.puedeSolicitar ?? false;

  int get unidadesElegidas =>
      seleccion.values.fold(0, (total, unidades) => total + unidades);

  bool get sePuedeSolicitarDevolucion =>
      sePuedeDevolver &&
      unidadesElegidas > 0 &&
      razon.trim().length >= 5 &&
      !ocupado;

  /// Cuántas unidades de esa variante quedan disponibles para devolver.
  int disponiblesDe(String variantId) => devoluciones?.unidades[variantId] ?? 0;

  EstadoPedido copyWith({
    Pedido? pedido,
    DisponibilidadDevolucion? devoluciones,
    Map<String, int>? seleccion,
    String? razon,
    bool? cargando,
    bool? ocupado,
    String? error,
    String? errorAccion,
    String? mensaje,
    bool limpiarError = false,
    bool limpiarAvisos = false,
  }) => EstadoPedido(
    pedido: pedido ?? this.pedido,
    devoluciones: devoluciones ?? this.devoluciones,
    seleccion: seleccion ?? this.seleccion,
    razon: razon ?? this.razon,
    cargando: cargando ?? this.cargando,
    ocupado: ocupado ?? this.ocupado,
    error: limpiarError ? null : (error ?? this.error),
    errorAccion: limpiarAvisos ? null : (errorAccion ?? this.errorAccion),
    mensaje: limpiarAvisos ? null : (mensaje ?? this.mensaje),
  );
}

/// Detalle de un pedido: seguimiento, cancelación, pago y devoluciones.
///
/// Junta lo que en la web son tres componentes (`order-tracker`,
/// `order-returns` y el detalle de `orders-page`), porque en un teléfono
/// abrir un pedido y tener que navegar otra vez para ver su seguimiento es
/// un paso de más.
class PedidoController extends StateNotifier<EstadoPedido> {
  PedidoController(this._comercio) : super(const EstadoPedido());

  final CommerceApi _comercio;
  String? _returnRequestId;

  Future<void> cargar(String id) async {
    state = state.copyWith(cargando: true, limpiarError: true);
    try {
      final pedido = await _comercio.pedidoDetalle(id);
      state = state.copyWith(pedido: pedido, cargando: false);
      await _leerDevoluciones(id);
    } on ApiException catch (error) {
      state = state.copyWith(cargando: false, error: error.message);
    }
  }

  /// Un pedido que todavía no se entregó no tiene devoluciones posibles y el
  /// backend responde con `can_request: false`; no es un error que mostrar.
  Future<void> _leerDevoluciones(String id) async {
    try {
      state = state.copyWith(
        devoluciones: await _comercio.disponibilidadDevolucion(id),
      );
    } on ApiException {
      // La pantalla simplemente no ofrece devolver.
    }
  }

  void marcarUnidades(String variantId, int unidades) {
    _returnRequestId = null;
    final tope = state.disponiblesDe(variantId);
    final valor = unidades.clamp(0, tope);
    final seleccion = Map<String, int>.from(state.seleccion);
    if (valor == 0) {
      seleccion.remove(variantId);
    } else {
      seleccion[variantId] = valor;
    }
    state = state.copyWith(seleccion: seleccion, limpiarAvisos: true);
  }

  void escribirRazon(String razon) {
    _returnRequestId = null;
    state = state.copyWith(razon: razon, limpiarAvisos: true);
  }

  Future<void> cancelar(String razon) async {
    final pedido = state.pedido;
    if (pedido == null || state.ocupado) return;
    state = state.copyWith(ocupado: true, limpiarAvisos: true);
    try {
      await _comercio.cancelarPedido(pedido.id, razon: razon);
      await cargar(pedido.id);
      state = state.copyWith(ocupado: false, mensaje: 'Cancelamos tu pedido.');
    } on ApiException catch (error) {
      state = state.copyWith(ocupado: false, errorAccion: error.message);
    }
  }

  /// Vuelve a abrir la sesión de Stripe. Devuelve la URL para que la pantalla
  /// la abra en el navegador, o `null` si no se pudo.
  Future<String?> reanudarPago() async {
    final pedido = state.pedido;
    if (pedido == null || state.ocupado) return null;
    state = state.copyWith(ocupado: true, limpiarAvisos: true);
    try {
      final sesion = await _comercio.checkout(pedido.id);
      final url = sesion.url;
      if (url == null || url.isEmpty) {
        // Stripe pudo confirmar el pago mientras se tocaba el botón. El
        // backend devuelve entonces un estado, pero ya no una URL de cobro.
        if (const [
          'paid',
          'processing',
          'shipped',
          'delivered',
        ].contains(sesion.status)) {
          await cargar(pedido.id);
          state = state.copyWith(
            ocupado: false,
            mensaje: 'Este pedido ya está pagado.',
          );
        } else {
          state = state.copyWith(
            ocupado: false,
            errorAccion:
                'Stripe no devolvió un enlace de pago. Volvé a intentarlo.',
          );
        }
        return null;
      }
      state = state.copyWith(ocupado: false);
      return url;
    } on ApiException catch (error) {
      if (error.statusCode == 409) await cargar(pedido.id);
      state = state.copyWith(ocupado: false, errorAccion: error.message);
      return null;
    } catch (_) {
      state = state.copyWith(
        ocupado: false,
        errorAccion: 'No pudimos abrir Stripe. Intentá nuevamente.',
      );
      return null;
    }
  }

  /// Al volver del navegador se consulta el servidor, que es la única fuente
  /// confiable del resultado de Stripe. Así el pedido no queda visualmente
  /// pendiente después de que el webhook o la conciliación lo acreditó.
  Future<void> reconciliarPago() async {
    final pedido = state.pedido;
    if (pedido == null || state.ocupado || pedido.paymentMethod != 'stripe') {
      return;
    }
    state = state.copyWith(ocupado: true, limpiarAvisos: true);
    try {
      final actualizado = await _comercio.reconciliarPagoPedido(pedido.id);
      state = state.copyWith(
        pedido: actualizado,
        ocupado: false,
        mensaje: actualizado.paymentStatus == 'paid'
            ? 'Pago confirmado. Ya podés seguir el envío.'
            : 'Stripe todavía no confirmó el pago. Podés reintentar en unos instantes.',
      );
      await _leerDevoluciones(pedido.id);
    } on ApiException catch (error) {
      state = state.copyWith(ocupado: false, errorAccion: error.message);
    } catch (_) {
      state = state.copyWith(
        ocupado: false,
        errorAccion: 'No pudimos consultar el pago. Intentá nuevamente.',
      );
    }
  }

  Future<void> solicitarDevolucion() async {
    final pedido = state.pedido;
    if (pedido == null || !state.sePuedeSolicitarDevolucion) return;
    state = state.copyWith(ocupado: true, limpiarAvisos: true);
    try {
      _returnRequestId ??= CommerceApi.nuevaClaveSolicitud();
      await _comercio.solicitarDevolucion(
        pedido.id,
        units: state.seleccion,
        razon: state.razon.trim(),
        clientRequestId: _returnRequestId!,
      );
      _returnRequestId = null;
      await _leerDevoluciones(pedido.id);
      state = state.copyWith(
        ocupado: false,
        seleccion: const {},
        razon: '',
        mensaje: 'Registramos tu solicitud. Te avisamos cuando la revisen.',
      );
    } on ApiException catch (error) {
      state = state.copyWith(ocupado: false, errorAccion: error.message);
    }
  }

  Future<List<OpcionCambio>> opcionesCambio(String variantId) async {
    final pedido = state.pedido;
    if (pedido == null || !state.sePuedeDevolver) return const [];
    return _comercio.opcionesCambio(pedido.id, variantId);
  }

  Future<bool> solicitarCambio({
    required String variantId,
    required String replacementVariantId,
    required int quantity,
    required String reason,
    required String clientRequestId,
  }) async {
    final pedido = state.pedido;
    if (pedido == null || !state.sePuedeDevolver || state.ocupado) return false;
    state = state.copyWith(ocupado: true, limpiarAvisos: true);
    try {
      await _comercio.solicitarCambio(
        pedido.id,
        variantId: variantId,
        replacementVariantId: replacementVariantId,
        quantity: quantity,
        reason: reason.trim(),
        clientRequestId: clientRequestId,
      );
      await _leerDevoluciones(pedido.id);
      state = state.copyWith(
        ocupado: false,
        mensaje: 'Registramos el cambio y apartamos la nueva prenda.',
      );
      return true;
    } on ApiException catch (error) {
      state = state.copyWith(ocupado: false, errorAccion: error.message);
      return false;
    }
  }
}

final pedidoProvider = StateNotifierProvider.autoDispose
    .family<PedidoController, EstadoPedido, String>((ref, id) {
      final controlador = PedidoController(ref.watch(commerceApiProvider));
      controlador.cargar(id);
      return controlador;
    });
