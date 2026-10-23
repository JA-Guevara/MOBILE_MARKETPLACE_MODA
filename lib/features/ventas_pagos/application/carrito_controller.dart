import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../usuarios_catalogo/domain/address.dart';
import '../../usuarios_catalogo/infrastructure/direcciones_api.dart';
import '../domain/commerce_models.dart';
import '../infrastructure/commerce_api.dart';
import 'commerce_providers.dart';

/// Datos de entrega que se escriben a mano cuando no hay una guardada.
class FormularioEntrega {
  const FormularioEntrega({
    this.destinatario = '',
    this.telefono = '',
    this.linea = '',
    this.ciudad = '',
    this.codigoPostal = '',
    this.pais = 'BO',
  });

  final String destinatario;
  final String telefono;
  final String linea;
  final String ciudad;
  final String codigoPostal;
  final String pais;

  /// Lo mínimo que el backend acepta para poder entregar el pedido.
  bool get completo =>
      destinatario.trim().isNotEmpty &&
      telefono.trim().isNotEmpty &&
      linea.trim().isNotEmpty &&
      ciudad.trim().isNotEmpty;

  bool get sinDatos =>
      destinatario.trim().isEmpty &&
      telefono.trim().isEmpty &&
      linea.trim().isEmpty &&
      ciudad.trim().isEmpty &&
      codigoPostal.trim().isEmpty;

  DireccionEntrega comoEntrega() => DireccionEntrega(
    recipient: destinatario.trim(),
    phone: telefono.trim(),
    line1: linea.trim(),
    city: ciudad.trim(),
    country: pais.trim().isEmpty ? 'BO' : pais.trim(),
    postalCode: codigoPostal.trim().isEmpty ? null : codigoPostal.trim(),
  );

  /// Una dirección guardada, traducida al formulario. Los nombres de campo del
  /// perfil (`recipient_name`, `address_line`) y los del pedido (`recipient`,
  /// `line1`) no coinciden; la traducción vive acá y en un solo lugar.
  factory FormularioEntrega.desdeGuardada(Direccion direccion) =>
      FormularioEntrega(
        destinatario: direccion.recipientName,
        telefono: direccion.phone,
        linea: direccion.addressLine,
        ciudad: direccion.city,
        codigoPostal: direccion.postalCode ?? '',
        pais: direccion.country ?? 'BO',
      );

  FormularioEntrega copyWith({
    String? destinatario,
    String? telefono,
    String? linea,
    String? ciudad,
    String? codigoPostal,
    String? pais,
  }) => FormularioEntrega(
    destinatario: destinatario ?? this.destinatario,
    telefono: telefono ?? this.telefono,
    linea: linea ?? this.linea,
    ciudad: ciudad ?? this.ciudad,
    codigoPostal: codigoPostal ?? this.codigoPostal,
    pais: pais ?? this.pais,
  );
}

/// Todo lo que la pantalla del carrito necesita.
class EstadoCarrito {
  const EstadoCarrito({
    this.carrito,
    this.sucursales = const [],
    this.sucursalId = '',
    this.guardadas = const [],
    this.direccionGuardadaId = '',
    this.entrega = const FormularioEntrega(),
    this.guardarEnPerfil = false,
    this.cupon = '',
    this.metodoPago = 'manual',
    this.cargando = true,
    this.ocupado = false,
    this.error,
    this.mensajeCupon,
    this.errorCupon,
    this.ultimoPedido,
    this.sucursalManual = false,
    this.ningunaSucursalCubre = false,
  });

  final Carrito? carrito;
  final List<Sucursal> sucursales;

  /// Sucursal de retiro. El backend calcula el stock disponible contra ella,
  /// así que cambiarla recarga el carrito.
  final String sucursalId;

  final List<Direccion> guardadas;

  /// `''` significa «escribir una dirección nueva».
  final String direccionGuardadaId;

  final FormularioEntrega entrega;
  final bool guardarEnPerfil;
  final String cupon;

  /// `manual` (efectivo o transferencia) o `stripe`, igual que la web.
  final String metodoPago;

  final bool cargando;
  final bool ocupado;
  final String? error;
  final String? mensajeCupon;
  final String? errorCupon;

  /// Último pedido creado desde este carrito. Sirve como salida de recuperación
  /// si el navegador de Stripe no se abre de inmediato: las prendas ya no
  /// están en el carrito porque fueron apartadas por el pedido.
  final Pedido? ultimoPedido;

  /// La sucursal la eligió la persona, no la app. A partir de ahí no se toca:
  /// cambiarle la sucursal a alguien que acaba de elegirla es peor que
  /// mostrarle que ahí falta stock.
  final bool sucursalManual;

  /// Ya se probaron todas las sucursales y ninguna cubre el carrito completo.
  /// Sirve para decirlo en vez de dejar los botones grises sin explicación.
  final bool ningunaSucursalCubre;

  List<ItemCarrito> get items => carrito?.items ?? const [];
  bool get vacio => items.isEmpty;

  /// Alguna línea pide más unidades de las que hay en la sucursal elegida.
  bool get haySobregiro => items.any((i) => i.quantity > i.available);

  bool get sePuedeComprar =>
      !vacio &&
      !cargando &&
      !ocupado &&
      !haySobregiro &&
      sucursalId.isNotEmpty &&
      entrega.completo;

  EstadoCarrito copyWith({
    Carrito? carrito,
    List<Sucursal>? sucursales,
    String? sucursalId,
    List<Direccion>? guardadas,
    String? direccionGuardadaId,
    FormularioEntrega? entrega,
    bool? guardarEnPerfil,
    String? cupon,
    String? metodoPago,
    bool? cargando,
    bool? ocupado,
    String? error,
    String? mensajeCupon,
    String? errorCupon,
    bool? sucursalManual,
    bool? ningunaSucursalCubre,
    Pedido? ultimoPedido,
    bool limpiarError = false,
    bool limpiarCupon = false,
    bool limpiarUltimoPedido = false,
    bool limpiarCarrito = false,
  }) => EstadoCarrito(
    carrito: limpiarCarrito ? null : (carrito ?? this.carrito),
    sucursales: sucursales ?? this.sucursales,
    sucursalId: sucursalId ?? this.sucursalId,
    guardadas: guardadas ?? this.guardadas,
    direccionGuardadaId: direccionGuardadaId ?? this.direccionGuardadaId,
    entrega: entrega ?? this.entrega,
    guardarEnPerfil: guardarEnPerfil ?? this.guardarEnPerfil,
    cupon: cupon ?? this.cupon,
    metodoPago: metodoPago ?? this.metodoPago,
    cargando: cargando ?? this.cargando,
    ocupado: ocupado ?? this.ocupado,
    error: limpiarError ? null : (error ?? this.error),
    mensajeCupon: limpiarCupon ? null : (mensajeCupon ?? this.mensajeCupon),
    errorCupon: limpiarCupon ? null : (errorCupon ?? this.errorCupon),
    ultimoPedido: limpiarUltimoPedido
        ? null
        : (ultimoPedido ?? this.ultimoPedido),
    sucursalManual: sucursalManual ?? this.sucursalManual,
    ningunaSucursalCubre: ningunaSucursalCubre ?? this.ningunaSucursalCubre,
  );
}

/// Dueño del carrito: líneas, cupón, sucursal, entrega y creación del pedido.
///
/// Réplica de `cart-page.component.ts`. Como en la web, el carrito **vive en
/// el backend**, no en el teléfono: cada cambio de cantidad vuelve a pedir el
/// carrito entero en vez de recalcular local, porque los descuentos y el stock
/// disponible los decide el servidor.
class CarritoController extends StateNotifier<EstadoCarrito> {
  CarritoController(this._comercio, this._direcciones)
    : super(const EstadoCarrito());

  final CommerceApi _comercio;
  final DireccionesApi _direcciones;
  int _ultimaCarga = 0;
  int _ultimaLectura = 0;

  Future<void> cargar() async {
    final carga = ++_ultimaCarga;
    state = state.copyWith(cargando: true, limpiarError: true);
    try {
      // Las sucursales y las direcciones no dependen una de la otra. Pedirlas
      // a la vez en lugar de una detrás de otra corta a la mitad la espera,
      // que en una red de telefono se nota.
      final futuroSucursales = _comercio.sucursales();
      final futuroGuardadas = _leerGuardadas();

      final sucursales = await futuroSucursales;
      if (!mounted || carga != _ultimaCarga) return;
      final elegida = state.sucursalId.isNotEmpty
          ? state.sucursalId
          : (sucursales.isEmpty ? '' : sucursales.first.id);
      state = state.copyWith(sucursales: sucursales, sucursalId: elegida);

      await _releerCarrito();
      if (!mounted || carga != _ultimaCarga) return;

      // La sucursal la habia elegido la app, no la persona. Si ahi no hay
      // stock de lo que tiene en el carrito, el boton de comprar queda gris
      // para siempre y nadie entiende por que: se busca una que si lo cubra.
      await _acomodarSucursal(carga);
      if (!mounted || carga != _ultimaCarga) return;

      _aplicarGuardadas(await futuroGuardadas);
      if (!mounted || carga != _ultimaCarga) return;
      state = state.copyWith(cargando: false);
    } on ApiException catch (error) {
      if (mounted && carga == _ultimaCarga) {
        state = state.copyWith(cargando: false, error: error.message);
      }
    } catch (_) {
      if (mounted && carga == _ultimaCarga) {
        state = state.copyWith(
          cargando: false,
          error: 'No pudimos actualizar el carrito. Intentá nuevamente.',
        );
      }
    }
  }

  Future<void> _releerCarrito() async {
    final lectura = ++_ultimaLectura;
    final carrito = await _comercio.carrito(
      branchId: state.sucursalId.isEmpty ? null : state.sucursalId,
      couponCode: state.cupon.isEmpty ? null : state.cupon,
    );
    if (!mounted || lectura != _ultimaLectura) return;
    state = state.copyWith(
      carrito: carrito,
      // Un pedido anterior no debe reemplazar la acción de crear uno nuevo
      // cuando el servidor ya confirma que hay prendas otra vez.
      limpiarUltimoPedido: carrito.items.isNotEmpty,
    );
  }

  /// Las direcciones guardadas son una comodidad: si fallan, se compra igual
  /// escribiendo la entrega a mano. Por eso nunca propagan el error.
  Future<List<Direccion>> _leerGuardadas() async {
    try {
      return await _direcciones.listar();
    } catch (_) {
      return const [];
    }
  }

  void _aplicarGuardadas(List<Direccion> guardadas) {
    state = state.copyWith(guardadas: guardadas);
    if (state.direccionGuardadaId.isEmpty && guardadas.isNotEmpty) {
      final predeterminada = guardadas.firstWhere(
        (d) => d.isDefault,
        orElse: () => guardadas.first,
      );
      elegirGuardada(predeterminada.id);
    }
  }

  /// Busca una sucursal que cubra el carrito entero.
  ///
  /// El backend devuelve `available: 0` cuando la variante no tiene fila de
  /// stock en la sucursal consultada —no distingue «cero unidades» de «esta
  /// sucursal no trabaja esa prenda»—, y con eso el carrito se bloquea. Si la
  /// sucursal la puso la app, se prueban las demás antes de darse por vencido.
  Future<void> _acomodarSucursal(int carga) async {
    if (state.sucursalManual || state.vacio || !state.haySobregiro) {
      state = state.copyWith(ningunaSucursalCubre: false);
      return;
    }
    for (final sucursal in state.sucursales) {
      if (sucursal.id == state.sucursalId) continue;
      final Carrito prueba;
      try {
        prueba = await _comercio.carrito(
          branchId: sucursal.id,
          couponCode: state.cupon.isEmpty ? null : state.cupon,
        );
      } on ApiException {
        continue;
      }
      if (!mounted || carga != _ultimaCarga) return;
      final cubre = prueba.items.every((i) => i.quantity <= i.available);
      if (cubre) {
        state = state.copyWith(
          sucursalId: sucursal.id,
          carrito: prueba,
          ningunaSucursalCubre: false,
        );
        return;
      }
    }
    // Ninguna la cubre: se deja la elegida y la pantalla lo explica.
    state = state.copyWith(ningunaSucursalCubre: true);
  }

  Future<void> elegirSucursal(String id) async {
    if (id == state.sucursalId) return;
    state = state.copyWith(
      sucursalId: id,
      sucursalManual: true,
      ningunaSucursalCubre: false,
      ocupado: true,
      limpiarError: true,
    );
    try {
      await _releerCarrito();
    } on ApiException catch (error) {
      state = state.copyWith(error: error.message);
    } finally {
      state = state.copyWith(ocupado: false);
    }
  }

  Future<void> cambiarCantidad(ItemCarrito item, int cantidad) async {
    if (state.ocupado) return;
    // Bajar a cero es quitar: el backend no acepta una línea sin unidades.
    if (cantidad <= 0) return quitar(item);
    state = state.copyWith(ocupado: true, limpiarError: true);
    try {
      await _comercio.cambiarCantidad(item.variantId, cantidad);
      await _releerCarrito();
    } on ApiException catch (error) {
      state = state.copyWith(error: error.message);
    } finally {
      state = state.copyWith(ocupado: false);
    }
  }

  Future<void> quitar(ItemCarrito item) async {
    if (state.ocupado) return;
    state = state.copyWith(ocupado: true, limpiarError: true);
    try {
      await _comercio.quitarItem(item.variantId);
      await _releerCarrito();
    } on ApiException catch (error) {
      state = state.copyWith(error: error.message);
    } finally {
      state = state.copyWith(ocupado: false);
    }
  }

  Future<void> vaciar() async {
    if (state.ocupado) return;
    state = state.copyWith(ocupado: true, limpiarError: true);
    try {
      await _comercio.vaciarCarrito();
      await _releerCarrito();
    } on ApiException catch (error) {
      state = state.copyWith(error: error.message);
    } finally {
      state = state.copyWith(ocupado: false);
    }
  }

  void escribirCupon(String codigo) =>
      state = state.copyWith(cupon: codigo, limpiarCupon: true);

  /// Aplica el cupón pidiendo el carrito con el código: el backend responde
  /// con los descuentos ya calculados, así que el resultado es el precio real
  /// y no una estimación que después cambie al confirmar.
  Future<void> aplicarCupon() async {
    if (state.ocupado) return;
    state = state.copyWith(ocupado: true, limpiarCupon: true);
    try {
      await _releerCarrito();
      final descuentos = state.carrito?.discounts ?? const [];
      if (state.cupon.isEmpty) {
        state = state.copyWith(mensajeCupon: 'Quitamos el cupón.');
      } else if (descuentos.isEmpty) {
        state = state.copyWith(
          errorCupon: 'Ese cupón no se aplica a las prendas de tu carrito.',
        );
      } else {
        state = state.copyWith(
          mensajeCupon: descuentos.map((d) => d.name).join(' · '),
        );
      }
    } on ApiException catch (error) {
      state = state.copyWith(errorCupon: error.message);
    } finally {
      state = state.copyWith(ocupado: false);
    }
  }

  void elegirGuardada(String id) {
    final guardada = state.guardadas.where((d) => d.id == id).firstOrNull;
    state = state.copyWith(
      direccionGuardadaId: id,
      entrega: guardada == null
          ? const FormularioEntrega()
          : FormularioEntrega.desdeGuardada(guardada),
      // Guardar en el perfil algo que ya está guardado no tiene sentido.
      guardarEnPerfil: guardada == null && state.guardarEnPerfil,
    );
  }

  void escribirEntrega(FormularioEntrega entrega) =>
      state = state.copyWith(entrega: entrega, direccionGuardadaId: '');

  void alternarGuardarEnPerfil(bool valor) =>
      state = state.copyWith(guardarEnPerfil: valor);

  void elegirMetodoPago(String metodo) =>
      state = state.copyWith(metodoPago: metodo);

  /// Crea el pedido y devuelve la URL de pago si el método es Stripe.
  ///
  /// Devuelve `null` si algo falló; el mensaje queda en `state.error`. La
  /// pantalla se encarga de abrir el navegador y de navegar, porque el
  /// controlador no conoce el `context`.
  Future<({Pedido pedido, String? urlPago, String? errorPago})?>
  comprar() async {
    if (!state.sePuedeComprar) return null;
    state = state.copyWith(ocupado: true, limpiarError: true);
    try {
      final pedido = await _comercio.crearPedido(
        branchId: state.sucursalId,
        direccion: state.entrega.comoEntrega(),
        metodoPago: state.metodoPago,
        cuponCode: state.cupon.isEmpty ? null : state.cupon,
      );
      if (state.guardarEnPerfil && state.direccionGuardadaId.isEmpty) {
        await _guardarDireccion();
      }
      String? url;
      String? errorPago;
      if (state.metodoPago == 'stripe') {
        // El pedido ya existe y el carrito ya fue vaciado antes de pedir la
        // sesión. Si Stripe no responde, no se puede dejar a la persona con
        // un botón girando ni obligarla a crear otra compra: se abre el pedido
        // pendiente y desde ahí puede reintentar el pago.
        try {
          url = (await _comercio.checkout(pedido.id)).url;
        } on ApiException catch (error) {
          errorPago = error.message;
        } catch (_) {
          errorPago =
              'Stripe devolvió una respuesta inesperada. Abrí el pedido para reintentar.';
        }
      }
      // El pedido ya vació el carrito del lado del servidor.
      state = state.copyWith(
        carrito: const Carrito(items: []),
        ocupado: false,
        ultimoPedido: pedido,
      );
      return (pedido: pedido, urlPago: url, errorPago: errorPago);
    } on ApiException catch (error) {
      state = state.copyWith(ocupado: false, error: error.message);
      return null;
    } catch (_) {
      state = state.copyWith(
        ocupado: false,
        error:
            'No pudimos confirmar la compra. Revisá Mis pedidos antes de volver a intentarlo.',
      );
      return null;
    }
  }

  /// Guarda la dirección escrita para no volver a tipearla en la próxima
  /// compra. Si falla no se interrumpe nada: el pedido ya está creado.
  Future<void> _guardarDireccion() async {
    try {
      await _direcciones.crear(
        DireccionesApi.cuerpo(
          etiqueta: 'Entrega',
          destinatario: state.entrega.destinatario,
          telefono: state.entrega.telefono,
          linea: state.entrega.linea,
          ciudad: state.entrega.ciudad,
          codigoPostal: state.entrega.codigoPostal,
          pais: state.entrega.pais,
          predeterminada: state.guardadas.isEmpty,
        ),
      );
    } catch (_) {
      // Comodidad, no requisito.
    }
  }
}

final StateNotifierProvider<CarritoController, EstadoCarrito> carritoProvider =
    StateNotifierProvider<CarritoController, EstadoCarrito>(
      (ref) => CarritoController(
        ref.watch(commerceApiProvider),
        ref.watch(direccionesApiProvider),
      ),
    );
