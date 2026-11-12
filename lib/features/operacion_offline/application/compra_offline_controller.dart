import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/offline/base_local.dart';
import '../../usuarios_catalogo/application/session_controller.dart';
import '../../usuarios_catalogo/domain/usuario.dart';
import '../../ventas_pagos/domain/commerce_models.dart' show ItemCarrito;
import '../domain/catalogo_local.dart';
import '../domain/compra_local.dart';
import '../infrastructure/compras_locales_dao.dart';
import 'catalogo_offline_controller.dart';

class EstadoCompraOffline {
  const EstadoCompraOffline({
    this.items = const [],
    this.sucursalId,
    this.contactoNombre = '',
    this.contactoTelefono = '',
    this.formaPago = 'TARJETA_AL_RECONECTAR',
    this.notas = '',
    this.error,
    this.guardando = false,
    this.compraGuardada,
  });
  final List<ItemCompraLocal> items;
  final String? sucursalId;
  final String contactoNombre, contactoTelefono, formaPago, notas;
  final String? error;
  final bool guardando;
  final CompraLocal? compraGuardada;
  double get total => items.fold(0, (sum, item) => sum + item.total);
  EstadoCompraOffline copyWith({
    List<ItemCompraLocal>? items,
    String? sucursalId,
    String? contactoNombre,
    String? contactoTelefono,
    String? formaPago,
    String? notas,
    String? error,
    bool? guardando,
    CompraLocal? compraGuardada,
    bool limpiarError = false,
    bool limpiarCompra = false,
  }) => EstadoCompraOffline(
    items: items ?? this.items,
    sucursalId: sucursalId ?? this.sucursalId,
    contactoNombre: contactoNombre ?? this.contactoNombre,
    contactoTelefono: contactoTelefono ?? this.contactoTelefono,
    formaPago: formaPago ?? this.formaPago,
    notas: notas ?? this.notas,
    error: limpiarError ? null : error ?? this.error,
    guardando: guardando ?? this.guardando,
    compraGuardada: limpiarCompra
        ? null
        : compraGuardada ?? this.compraGuardada,
  );
}

class CompraOfflineController extends StateNotifier<EstadoCompraOffline> {
  CompraOfflineController(this.dao, this.usuario, this.catalogo)
    : super(
        EstadoCompraOffline(
          sucursalId: catalogo().sucursalId,
          contactoNombre: usuario?.nombreCompleto ?? '',
          contactoTelefono: usuario?.telefono ?? '',
        ),
      );
  final ComprasLocalesDao dao;
  final Usuario? usuario;
  final EstadoCatalogoOffline Function() catalogo;

  String? agregar(VarianteLocal variante, {int cantidad = 1}) {
    if (usuario == null || usuario!.puede('commerce.write')) {
      return 'Esta compra está disponible para cuentas de cliente.';
    }
    final catalogoActual = catalogo();
    if (catalogoActual.version == null || catalogoActual.sucursalId == null) {
      return 'Todavía no hay catálogo en este dispositivo. Se descargará solo cuando haya conexión.';
    }
    if (!variante.activa) return 'Esta variante no está disponible.';
    final actuales = state.items.where(
      (item) => item.varianteId == variante.id,
    );
    final anterior = actuales.isEmpty ? 0 : actuales.first.cantidad;
    final stock = catalogoActual.datos.stock(variante.id);
    if (cantidad < 1 || anterior + cantidad > 10) {
      return 'Elegí una cantidad entre 1 y 10 por prenda.';
    }
    if (anterior + cantidad > stock) {
      return 'Solo quedan $stock unidades de esta prenda según los datos guardados.';
    }
    final producto = catalogoActual.datos.productos
        .where((item) => item.id == variante.productoId)
        .firstOrNull;
    if (producto == null) {
      return 'La prenda ya no está en el catálogo guardado.';
    }
    // El backend valida el precio regular y la compra diferida aún no reserva
    // promociones. Mostramos el mismo precio que se enviará a validar.
    final precio = variante.precio ?? producto.precioBase;
    final item = ItemCompraLocal(
      varianteId: variante.id,
      productoNombre: producto.nombre,
      varianteDesc: '${variante.talla} · ${variante.color}',
      cantidad: anterior + cantidad,
      precioUnitario: precio,
      stockDisponible: stock,
    );
    state = state.copyWith(
      items: [...state.items.where((i) => i.varianteId != variante.id), item],
      sucursalId: state.sucursalId ?? catalogoActual.sucursalId,
      limpiarError: true,
      limpiarCompra: true,
    );
    return null;
  }

  String? prepararDesdeCarrito({
    required List<ItemCarrito> carrito,
    required String sucursalId,
    required String contactoNombre,
    required String contactoTelefono,
    required String formaPago,
  }) {
    final datos = catalogo();
    if (datos.version == null || datos.sucursalId == null) {
      return 'No hay un catálogo descargado para validar esta compra sin conexión.';
    }
    final lineas = <ItemCompraLocal>[];
    for (final item in carrito) {
      final variante = datos.datos.variantes
          .where((v) => v.id == item.variantId)
          .firstOrNull;
      if (variante == null) {
        return 'Una prenda del carrito no está en el catálogo guardado. Conectate y actualizá el catálogo.';
      }
      final producto = datos.datos.productos
          .where((p) => p.id == variante.productoId)
          .firstOrNull;
      if (producto == null) {
        return 'Una prenda del carrito no está en el catálogo guardado.';
      }
      final stock = datos.datos.stock(variante.id);
      lineas.add(
        ItemCompraLocal(
          varianteId: variante.id,
          productoNombre: producto.nombre,
          varianteDesc: '${variante.talla} · ${variante.color}',
          cantidad: item.quantity,
          precioUnitario: variante.precio ?? producto.precioBase,
          stockDisponible: stock,
        ),
      );
    }
    final error = validarItemsCompra(lineas);
    if (error != null) return error;
    state = EstadoCompraOffline(
      items: lineas,
      sucursalId: sucursalId,
      contactoNombre: contactoNombre,
      contactoTelefono: contactoTelefono,
      formaPago: formaPago == 'stripe'
          ? 'TARJETA_AL_RECONECTAR'
          : 'EFECTIVO_AL_RETIRAR',
    );
    return null;
  }

  void cambiarCantidad(String varianteId, int cantidad) {
    if (state.guardando) return;
    if (cantidad <= 0) return quitar(varianteId);
    state = state.copyWith(
      items: [
        for (final item in state.items)
          if (item.varianteId == varianteId)
            item.copyWith(cantidad: cantidad)
          else
            item,
      ],
      limpiarError: true,
      limpiarCompra: true,
    );
  }

  void quitar(String varianteId) => state = state.copyWith(
    items: state.items.where((item) => item.varianteId != varianteId).toList(),
    limpiarError: true,
    limpiarCompra: true,
  );

  void configurar({
    String? sucursalId,
    String? contactoNombre,
    String? contactoTelefono,
    String? formaPago,
    String? notas,
  }) => state = state.copyWith(
    sucursalId: sucursalId,
    contactoNombre: contactoNombre,
    contactoTelefono: contactoTelefono,
    formaPago: formaPago,
    notas: notas,
    limpiarError: true,
  );

  void nuevaCompra() => state = EstadoCompraOffline(
    sucursalId: catalogo().sucursalId,
    contactoNombre: usuario?.nombreCompleto ?? '',
    contactoTelefono: usuario?.telefono ?? '',
  );

  Future<CompraLocal?> guardar() async {
    if (state.guardando) return null;
    final usuarioActual = usuario;
    if (usuarioActual == null || usuarioActual.puede('commerce.write')) {
      state = state.copyWith(
        error: 'Iniciá sesión con una cuenta de cliente válida.',
      );
      return null;
    }
    final catalogoActual = catalogo();
    if (catalogoActual.version == null || catalogoActual.sucursalId == null) {
      state = state.copyWith(
        error:
            'Todavía no hay catálogo en este dispositivo. Se descargará solo cuando haya conexión.',
      );
      return null;
    }
    final error = validarItemsCompra(state.items);
    if (error != null) {
      state = state.copyWith(error: error);
      return null;
    }
    state = state.copyWith(guardando: true, limpiarError: true);
    try {
      final compra = await dao.registrar(
        usuario: usuarioActual,
        sucursalId: state.sucursalId ?? catalogoActual.sucursalId!,
        items: state.items,
        contactoNombre: state.contactoNombre,
        contactoTelefono: state.contactoTelefono,
        formaPago: state.formaPago,
        notas: state.notas,
      );
      if (!mounted) return compra;
      state = EstadoCompraOffline(
        sucursalId: state.sucursalId,
        contactoNombre: state.contactoNombre,
        contactoTelefono: state.contactoTelefono,
        formaPago: state.formaPago,
        compraGuardada: compra,
      );
      return compra;
    } catch (_) {
      if (mounted) {
        state = state.copyWith(
          guardando: false,
          error:
              'No se pudo guardar tu compra. Revisá las cantidades e intentá de nuevo.',
        );
      }
      return null;
    }
  }
}

final comprasLocalesDaoProvider = Provider(
  (ref) => ComprasLocalesDao(ref.watch(baseLocalProvider)),
);
final compraOfflineProvider =
    StateNotifierProvider<CompraOfflineController, EstadoCompraOffline>((ref) {
      final usuario = ref.watch(sessionProvider.select((s) => s.usuario));
      return CompraOfflineController(
        ref.watch(comprasLocalesDaoProvider),
        usuario,
        () => ref.read(catalogoOfflineProvider),
      );
    });
