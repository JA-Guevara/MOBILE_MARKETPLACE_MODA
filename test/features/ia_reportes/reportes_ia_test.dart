import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_marketplace_moda/features/ia_reportes/application/reporte_ia_controller.dart';
import 'package:mobile_marketplace_moda/features/ia_reportes/domain/reporte_ia.dart';
import 'package:mobile_marketplace_moda/features/ia_reportes/infrastructure/reportes_ia_api.dart';

class MockReportesIaApi implements ReportesIaApi {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  Future<List<Map<String, dynamic>>> obtenerDefiniciones() async {
    return [
      {
        'code': 'ventas_por_sucursal',
        'title': 'Ventas por sucursal',
        'description': 'Ingresos y pedidos',
        'metrics': ['REVENUE', 'ORDERS'],
        'dimensions': ['BRANCH'],
        'default_chart': 'BAR',
        'examples': ['Ventas de septiembre'],
      }
    ];
  }

  @override
  Future<InterpretResult> interpretar(String texto, {String canal = 'TEXT'}) async {
    if (texto.contains('borrar')) {
      return const InterpretResult(
        status: 'UNSUPPORTED',
        assumptions: ['No se admiten operaciones de escritura.'],
        suggestions: ['Ventas por sucursal'],
      );
    }
    if (texto.contains('ambigua')) {
      return const InterpretResult(
        status: 'NEEDS_CLARIFICATION',
        questions: ['¿A qué sucursal te refieres?'],
      );
    }

    return const InterpretResult(
      status: 'READY',
      requestId: 'req-101',
      spec: ReportSpec(
        definitionCode: 'ventas_por_sucursal',
        metrics: ['REVENUE', 'ORDERS'],
        dimensions: ['BRANCH'],
        filters: ReportFilters(
          period: ReportPeriod(
            dateFrom: '2026-09-01',
            dateTo: '2026-09-30',
            label: 'Septiembre',
          ),
          branchNames: ['Central'],
        ),
      ),
    );
  }

  @override
  Future<ReportResponse> ejecutar(ReportSpec spec, {String? requestId}) async {
    return const ReportResponse(
      requestId: 'req-101',
      definitionCode: 'ventas_por_sucursal',
      title: 'Ventas por sucursal',
      columns: [
        ReportColumn(key: 'branch', label: 'Sucursal', type: 'text'),
        ReportColumn(key: 'revenue', label: 'Ventas (Bs)', type: 'money'),
      ],
      rows: [
        {'branch': 'Central', 'revenue': 450.0},
      ],
      totals: {'branch': 'TOTAL', 'revenue': 450.0},
      chartKind: 'BAR',
      chartX: 'branch',
      chartY: 'revenue',
      chartLabel: 'Ventas por sucursal',
      narrative: 'La sucursal Central lidera las ventas.',
      usedCount: 5,
      limitCount: 1000,
    );
  }
}

void main() {
  group('CU-09 Reportes con IA y voz (Móvil)', () {
    test('chipsDeSpec genera etiquetas para los filtros interpretados', () {
      const spec = ReportSpec(
        definitionCode: 'top_productos',
        metrics: ['UNITS'],
        dimensions: ['PRODUCT'],
        filters: ReportFilters(
          period: ReportPeriod(dateFrom: '2026-09-01', dateTo: '2026-09-30', label: 'Septiembre'),
          branchNames: ['Central', 'Norte'],
          categoryNames: ['Vestidos'],
        ),
        topN: 10,
        comparePrevious: true,
      );

      final chips = chipsDeSpec(spec);
      expect(chips.length, 5);
      expect(chips.any((c) => c.$1 == 'Período' && c.$2 == 'Septiembre'), isTrue);
      expect(chips.any((c) => c.$1 == 'Sucursales' && c.$2 == 'Central, Norte'), isTrue);
      expect(chips.any((c) => c.$1 == 'Límite' && c.$2 == 'Top 10'), isTrue);
      expect(chips.any((c) => c.$1 == 'Comparativa' && c.$2 == 'vs. previo'), isTrue);
    });

    test('ReporteIaController pide consulta y ejecuta reporte con datos reales', () async {
      final api = MockReportesIaApi();
      final controller = ReporteIaController(api);

      await controller.pedir('ventas de septiembre por sucursal');

      final state = controller.state;
      expect(state.cargando, isFalse);
      expect(state.error, isNull);
      expect(state.interpretacion?.status, 'READY');
      expect(state.reporte, isNotNull);
      expect(state.reporte!.definitionCode, 'ventas_por_sucursal');
      expect(state.reporte!.rows.length, 1);
      expect(state.reporte!.rows.first['branch'], 'Central');
      expect(state.reporte!.usedCount, 5);
    });

    test('ReporteIaController maneja aclaración y consultas no soportadas', () async {
      final api = MockReportesIaApi();
      final controller = ReporteIaController(api);

      // Consulta ambigua
      await controller.pedir('consulta ambigua');
      expect(controller.state.interpretacion?.status, 'NEEDS_CLARIFICATION');
      expect(controller.state.reporte, isNull);

      // Consulta de borrado no soportada
      await controller.pedir('borrar registros');
      expect(controller.state.interpretacion?.status, 'UNSUPPORTED');
      expect(controller.state.reporte, isNull);
    });

    test('ReporteIaController cambia vista entre grafico y tabla', () {
      final api = MockReportesIaApi();
      final controller = ReporteIaController(api);

      expect(controller.state.vista, 'grafico');
      controller.cambiarVista('tabla');
      expect(controller.state.vista, 'tabla');
    });
  });
}
