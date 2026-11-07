import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../domain/reporte_ia.dart';
import '../infrastructure/reportes_ia_api.dart';

class EstadoReporteIa {
  const EstadoReporteIa({
    this.cargando = false,
    this.error,
    this.interpretacion,
    this.reporte,
    this.vista = 'grafico',
    this.ejemplos = const [
      'Mostrame las ventas de septiembre agrupadas por sucursal',
      '¿Cuáles fueron los diez productos más vendidos este mes?',
      'Generá un gráfico de ventas por semana',
      'Compará las ventas de las sucursales durante los últimos tres meses',
      'Mostrame los productos con menor existencia',
      '¿Qué categorías generaron mayores ingresos durante este período?',
    ],
  });

  final bool cargando;
  final String? error;
  final InterpretResult? interpretacion;
  final ReportResponse? reporte;
  final String vista; // 'grafico' | 'tabla'
  final List<String> ejemplos;

  EstadoReporteIa copyWith({
    bool? cargando,
    String? error,
    InterpretResult? interpretacion,
    ReportResponse? reporte,
    String? vista,
    List<String>? ejemplos,
    bool limpiarError = false,
  }) {
    return EstadoReporteIa(
      cargando: cargando ?? this.cargando,
      error: limpiarError ? null : (error ?? this.error),
      interpretacion: interpretacion ?? this.interpretacion,
      reporte: reporte ?? this.reporte,
      vista: vista ?? this.vista,
      ejemplos: ejemplos ?? this.ejemplos,
    );
  }
}

class ReporteIaController extends StateNotifier<EstadoReporteIa> {
  ReporteIaController(this._api) : super(const EstadoReporteIa());

  final ReportesIaApi _api;

  void cambiarVista(String v) {
    state = state.copyWith(vista: v);
  }

  Future<void> pedir(String texto, {String canal = 'TEXT'}) async {
    final query = texto.trim();
    if (query.isEmpty) return;

    state = state.copyWith(cargando: true, limpiarError: true);
    try {
      final inter = await _api.interpretar(query, canal: canal);
      if (!mounted) return;
      state = state.copyWith(interpretacion: inter);

      if (inter.status == 'READY' && inter.spec != null) {
        final rep = await _api.ejecutar(
          inter.spec!,
          requestId: inter.requestId,
        );
        if (!mounted) return;
        state = state.copyWith(cargando: false, reporte: rep);
      } else {
        state = state.copyWith(cargando: false, reporte: null);
      }
    } catch (e) {
      if (!mounted) return;
      state = state.copyWith(cargando: false, error: e.toString());
    }
  }

  Future<void> usarSugerencia(String texto) async {
    await pedir(texto, canal: 'TEXT');
  }

  Future<void> usarMesEnCurso() async {
    final promptPrevio = state.interpretacion?.spec?.definitionCode ?? '';
    await pedir('$promptPrevio este mes', canal: 'TEXT');
  }
}
