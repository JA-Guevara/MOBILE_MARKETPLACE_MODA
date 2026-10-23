import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../domain/address.dart';
import '../infrastructure/direcciones_api.dart';

class EstadoDirecciones {
  const EstadoDirecciones({
    this.direcciones = const [],
    this.cargando = true,
    this.ocupado = false,
    this.error,
    this.mensaje,
  });

  final List<Direccion> direcciones;
  final bool cargando;
  final bool ocupado;
  final String? error;
  final String? mensaje;

  EstadoDirecciones copyWith({
    List<Direccion>? direcciones,
    bool? cargando,
    bool? ocupado,
    String? error,
    String? mensaje,
    bool limpiarAvisos = false,
  }) =>
      EstadoDirecciones(
        direcciones: direcciones ?? this.direcciones,
        cargando: cargando ?? this.cargando,
        ocupado: ocupado ?? this.ocupado,
        error: limpiarAvisos ? null : (error ?? this.error),
        mensaje: limpiarAvisos ? null : (mensaje ?? this.mensaje),
      );
}

/// ABM de direcciones del perfil (`/mi-cuenta/direcciones`).
///
/// En la web esto lo resuelve el `ResourcePageComponent` genérico, que arma
/// tabla y formulario desde una descripción de campos. Acá se escribe directo:
/// un genérico de ese tipo en Flutter costaría más que las cuatro operaciones
/// que reemplaza, y son solo cuatro.
class DireccionesController extends StateNotifier<EstadoDirecciones> {
  DireccionesController(this._api) : super(const EstadoDirecciones());

  final DireccionesApi _api;

  Future<void> cargar() async {
    state = state.copyWith(cargando: true, limpiarAvisos: true);
    try {
      state = state.copyWith(direcciones: await _api.listar(), cargando: false);
    } on ApiException catch (error) {
      state = state.copyWith(cargando: false, error: error.message);
    }
  }

  Future<bool> guardar({
    String? id,
    required String etiqueta,
    required String destinatario,
    required String telefono,
    required String linea,
    required String ciudad,
    String codigoPostal = '',
    String pais = 'BO',
    bool predeterminada = false,
  }) async {
    if (state.ocupado) return false;
    state = state.copyWith(ocupado: true, limpiarAvisos: true);
    final cuerpo = DireccionesApi.cuerpo(
      etiqueta: etiqueta,
      destinatario: destinatario,
      telefono: telefono,
      linea: linea,
      ciudad: ciudad,
      codigoPostal: codigoPostal,
      pais: pais,
      // La primera dirección se marca predeterminada sola: si no, la compra
      // siguiente no tiene ninguna sugerida y hay que elegirla a mano igual.
      predeterminada: predeterminada || (id == null && state.direcciones.isEmpty),
    );
    try {
      if (id == null) {
        await _api.crear(cuerpo);
      } else {
        await _api.actualizar(id, cuerpo);
      }
      await cargar();
      state = state.copyWith(
        ocupado: false,
        mensaje: id == null ? 'Guardamos la dirección.' : 'Actualizamos la dirección.',
      );
      return true;
    } on ApiException catch (error) {
      state = state.copyWith(ocupado: false, error: error.message);
      return false;
    }
  }

  Future<void> eliminar(Direccion direccion) async {
    if (state.ocupado) return;
    state = state.copyWith(ocupado: true, limpiarAvisos: true);
    try {
      await _api.eliminar(direccion.id);
      await cargar();
      state = state.copyWith(ocupado: false, mensaje: 'Borramos la dirección.');
    } on ApiException catch (error) {
      state = state.copyWith(ocupado: false, error: error.message);
    }
  }

  /// El backend deja una sola predeterminada: al marcar esta, limpia el resto.
  Future<void> marcarPredeterminada(Direccion direccion) async {
    if (state.ocupado) return;
    state = state.copyWith(ocupado: true, limpiarAvisos: true);
    try {
      await _api.actualizar(direccion.id, {'is_default': true});
      await cargar();
      state = state.copyWith(ocupado: false);
    } on ApiException catch (error) {
      state = state.copyWith(ocupado: false, error: error.message);
    }
  }
}

final StateNotifierProvider<DireccionesController, EstadoDirecciones>
    direccionesProvider =
    StateNotifierProvider<DireccionesController, EstadoDirecciones>(
        (ref) => DireccionesController(ref.watch(direccionesApiProvider)));
