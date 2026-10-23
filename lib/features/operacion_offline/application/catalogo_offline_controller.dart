import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../../../core/offline/base_local.dart';
import '../../usuarios_catalogo/application/session_controller.dart';
import '../../usuarios_catalogo/domain/usuario.dart';
import '../domain/catalogo_local.dart';
import '../infrastructure/catalogo_local_dao.dart';
import '../infrastructure/instantanea_api.dart';
import '../infrastructure/imagenes_offline.dart';

class EstadoCatalogoOffline {
  const EstadoCatalogoOffline({
    this.datos = const DatosLocales(),
    this.filtros = const FiltrosOffline(),
    this.descargadoEn,
    this.version,
    this.sucursalId,
    this.descargando = false,
    this.progreso = 0,
    this.error,
    this.cargando = true,
  });
  final DatosLocales datos;
  final FiltrosOffline filtros;
  final DateTime? descargadoEn;
  final String? version, sucursalId, error;
  final bool descargando, cargando;
  final double progreso;
  bool get desactualizado => estaDesactualizado(descargadoEn, DateTime.now());
  List<ProductoVista> get vista => filtrar(datos, filtros);
  EstadoCatalogoOffline copyWith({
    DatosLocales? datos,
    FiltrosOffline? filtros,
    DateTime? descargadoEn,
    String? version,
    String? sucursalId,
    bool? descargando,
    double? progreso,
    String? error,
    bool? cargando,
  }) => EstadoCatalogoOffline(
    datos: datos ?? this.datos,
    filtros: filtros ?? this.filtros,
    descargadoEn: descargadoEn ?? this.descargadoEn,
    version: version ?? this.version,
    sucursalId: sucursalId ?? this.sucursalId,
    descargando: descargando ?? this.descargando,
    progreso: progreso ?? this.progreso,
    error: error,
    cargando: cargando ?? this.cargando,
  );
}

bool puedeOperarOffline(Usuario? usuario, {DateTime? ahora}) {
  final s = usuario?.suscripcion;
  final fin = DateTime.tryParse(s?.fin ?? '');
  final hoy = ahora ?? DateTime.now();
  final fecha = DateTime(hoy.year, hoy.month, hoy.day);
  return usuario?.empresa?.estado == 'ACTIVA' &&
      s?.estado == 'ACTIVA' &&
      s?.permite('offline') == true &&
      (fin == null || !DateTime(fin.year, fin.month, fin.day).isBefore(fecha));
}

class CatalogoOfflineController extends StateNotifier<EstadoCatalogoOffline> {
  CatalogoOfflineController(this.dao, this.api, this.imagenes, this.usuario)
    : super(const EstadoCatalogoOffline());
  final CatalogoLocalDao dao;
  final InstantaneaApi api;
  final ImagenesOffline imagenes;
  final Usuario? usuario;
  Future<void> iniciar() async {
    try {
      final m = await dao.meta();
      if (!mounted) return;
      if (usuario == null ||
          m.tenantId != usuario!.empresa?.id ||
          m.usuarioId != usuario!.id ||
          m.sucursalId == null) {
        state = const EstadoCatalogoOffline(cargando: false);
        return;
      }
      final datos = await dao.leer(m.sucursalId!);
      if (mounted) {
        state = state.copyWith(
          datos: datos,
          descargadoEn: m.descargadoEn,
          version: m.version,
          sucursalId: m.sucursalId,
          cargando: false,
        );
      }
    } catch (error) {
      if (mounted) {
        state = state.copyWith(
          cargando: false,
          error: 'No se pudo leer el catálogo guardado: $error',
        );
      }
    }
  }

  Future<void> descargar({String? sucursalId}) async {
    if (state.descargando) return;
    if (!puedeOperarOffline(usuario)) {
      state = state.copyWith(
        error:
            'Tu suscripción no permite descargar datos sin conexión. Puedes consultar lo guardado.',
      );
      return;
    }
    state = state.copyWith(descargando: true, progreso: .05);
    try {
      final previa = await dao.meta();
      final sucursal = sucursalId ?? state.sucursalId;
      final incremental =
          previa.tenantId == usuario!.empresa!.id &&
          previa.usuarioId == usuario!.id &&
          previa.sucursalId == sucursal;
      final i = await api.obtener(
        sucursalId: sucursal,
        desde: incremental ? previa.version : null,
      );
      if (!mounted) return;
      if (i.empresa.id != usuario!.empresa!.id) {
        throw StateError('La descarga no corresponde a tu empresa.');
      }
      if (i.sucursales.isEmpty) {
        throw StateError('Tu empresa no tiene sucursales activas.');
      }
      final elegida = sucursal ?? i.sucursales.first.id;
      state = state.copyWith(progreso: .35);
      await imagenes.preparar(
        i.productos.map((p) => p.imagenUrl ?? ''),
        progreso: (n, total) {
          if (mounted) state = state.copyWith(progreso: .35 + .5 * n / total);
        },
      );
      if (!mounted) return;
      await dao.guardar(i, elegida, usuarioId: usuario!.id);
      if (!mounted) return;
      await iniciar();
      if (mounted) state = state.copyWith(descargando: false, progreso: 1);
    } catch (error) {
      if (mounted) {
        state = state.copyWith(
          descargando: false,
          error:
              'La descarga se interrumpió. ${state.descargadoEn == null ? 'No se guardaron cambios.' : 'Sigues usando la versión del ${state.descargadoEn!.toLocal()}.'} $error',
        );
      }
    }
  }

  Future<void> elegirSucursal(String id) async {
    if (!state.datos.sucursales.any((s) => s.id == id)) return;
    final datos = await dao.leer(id);
    await dao.base.guardarMeta('sucursal_id', id);
    if (mounted) state = state.copyWith(datos: datos, sucursalId: id);
  }

  void aplicarFiltros(FiltrosOffline f) => state = state.copyWith(filtros: f);
}

final catalogoLocalDaoProvider = Provider(
  (ref) => CatalogoLocalDao(ref.watch(baseLocalProvider)),
);
final imagenesOfflineProvider = Provider((ref) => ImagenesOffline());
final catalogoOfflineProvider =
    StateNotifierProvider<CatalogoOfflineController, EstadoCatalogoOffline>((
      ref,
    ) {
      final usuario = ref.watch(sessionProvider.select((s) => s.usuario));
      final autenticado = ref.watch(
        sessionProvider.select((s) => s.autenticado),
      );
      final control = CatalogoOfflineController(
        ref.watch(catalogoLocalDaoProvider),
        InstantaneaApi(ref.watch(apiClientProvider)),
        ref.watch(imagenesOfflineProvider),
        usuario,
      );
      control.iniciar().then((_) async {
        if (!control.mounted || !autenticado || !puedeOperarOffline(usuario)) {
          return;
        }
        try {
          final automatico = await control.dao.base.leerMeta(
            'descarga_automatica',
          );
          if (automatico == 'false') return;
          final conexion = await Connectivity().checkConnectivity();
          if (control.mounted && conexion.contains(ConnectivityResult.wifi)) {
            await control.descargar();
          }
        } catch (_) {
          /* Una detección de Wi-Fi no disponible no bloquea la descarga manual. */
        }
      });
      return control;
    });
