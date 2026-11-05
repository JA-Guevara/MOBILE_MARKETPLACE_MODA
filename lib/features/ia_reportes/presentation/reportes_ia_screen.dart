import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../usuarios_catalogo/application/session_controller.dart';
import '../application/reporte_ia_controller.dart';
import '../domain/reporte_ia.dart';
import '../infrastructure/reportes_ia_api.dart';

final reportesIaApiProvider = Provider<ReportesIaApi>((ref) {
  final client = ref.watch(apiClientProvider);
  return ReportesIaApi(client);
});

final reporteIaControllerProvider =
    StateNotifierProvider<ReporteIaController, EstadoReporteIa>((ref) {
  final api = ref.watch(reportesIaApiProvider);
  return ReporteIaController(api);
});

class ReportesIaScreen extends ConsumerStatefulWidget {
  const ReportesIaScreen({super.key});

  @override
  ConsumerState<ReportesIaScreen> createState() => _ReportesIaScreenState();
}

class _ReportesIaScreenState extends ConsumerState<ReportesIaScreen> {
  final _textController = TextEditingController();

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  void _enviar(String canal) {
    final t = _textController.text.trim();
    if (t.isNotEmpty) {
      ref.read(reporteIaControllerProvider.notifier).pedir(t, canal: canal);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(reporteIaControllerProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Reportes con IA y Voz'),
        actions: [
          if (state.reporte != null)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Chip(
                label: Text(
                  '${state.reporte!.usedCount}/${state.reporte!.limitCount}',
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                ),
                backgroundColor: Colors.blue.shade50,
              ),
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Barra de entrada y micrófono
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.mic, color: Colors.blue),
                          onPressed: () {
                            // Dictado de voz / prompt rápido
                            _textController.text =
                                'Mostrame las ventas de septiembre agrupadas por sucursal';
                            _enviar('VOICE');
                          },
                          tooltip: 'Dictar consulta por voz',
                        ),
                        Expanded(
                          child: TextField(
                            controller: _textController,
                            decoration: const InputDecoration(
                              hintText: 'Escribe o dicta tu consulta...',
                              border: InputBorder.none,
                            ),
                            onSubmitted: (_) => _enviar('TEXT'),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.send, color: Colors.blue),
                          onPressed: () => _enviar('TEXT'),
                        ),
                      ],
                    ),
                    const Divider(height: 16),
                    // Chips de ejemplos (8.2)
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: state.ejemplos.map((ejemplo) {
                          return Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ActionChip(
                              label: Text(
                                ejemplo,
                                style: const TextStyle(fontSize: 11),
                              ),
                              onPressed: () {
                                _textController.text = ejemplo;
                                _enviar('TEXT');
                              },
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Loading
            if (state.cargando)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()),
              ),

            // Error
            if (state.error != null)
              Card(
                color: Colors.red.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    state.error!,
                    style: TextStyle(color: Colors.red.shade800),
                  ),
                ),
              ),

            // 5a: Aclaración
            if (state.interpretacion?.status == 'NEEDS_CLARIFICATION')
              Card(
                color: Colors.amber.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '❓ Consulta incompleta',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      ...state.interpretacion!.questions.map((q) => Text(q)),
                      const SizedBox(height: 8),
                      ElevatedButton(
                        onPressed: () =>
                            ref.read(reporteIaControllerProvider.notifier).usarMesEnCurso(),
                        child: const Text('Usar mes en curso'),
                      ),
                    ],
                  ),
                ),
              ),

            // 5b: No soportado
            if (state.interpretacion?.status == 'UNSUPPORTED')
              Card(
                color: Colors.red.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '🛑 Consulta no admitida',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      ...state.interpretacion!.assumptions.map((a) => Text(a)),
                    ],
                  ),
                ),
              ),

            // Reporte generado
            if (state.reporte != null) ...[
              const SizedBox(height: 12),
              // Chips de filtros activos
              if (state.interpretacion?.spec != null)
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: chipsDeSpec(state.interpretacion!.spec!).map((chip) {
                    return Chip(
                      label: Text('${chip.$1}: ${chip.$2}', style: const TextStyle(fontSize: 11)),
                      backgroundColor: Colors.grey.shade200,
                    );
                  }).toList(),
                ),
              const SizedBox(height: 12),

              // Narrativa inteligente
              Card(
                color: Colors.blue.shade50,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('💡', style: TextStyle(fontSize: 20)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'LECTURA INTELIGENTE',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: Colors.blue,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              state.reporte!.narrative,
                              style: const TextStyle(fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // Selector Gráfico / Tabla
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    state.reporte!.title,
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'grafico', label: Text('Gráfico')),
                      ButtonSegment(value: 'tabla', label: Text('Tabla')),
                    ],
                    selected: {state.vista},
                    onSelectionChanged: (set) {
                      ref.read(reporteIaControllerProvider.notifier).cambiarVista(set.first);
                    },
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Vista Gráfico o Tabla
              if (state.vista == 'grafico')
                Card(
                  elevation: 1,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          state.reporte!.chartLabel.isNotEmpty
                              ? state.reporte!.chartLabel
                              : state.reporte!.title,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                        const SizedBox(height: 16),
                        ...state.reporte!.rows.map((r) {
                          final label = r[state.reporte!.chartX]?.toString() ?? '';
                          final rawVal = r[state.reporte!.chartY];
                          final val = (rawVal is num)
                              ? rawVal.toDouble()
                              : double.tryParse(rawVal?.toString() ?? '0') ?? 0.0;
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(
                                      child: Text(
                                        label,
                                        style: const TextStyle(fontSize: 12),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    Text(
                                      'Bs ${val.toStringAsFixed(2)}',
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold, fontSize: 12),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 2),
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(4),
                                  child: LinearProgressIndicator(
                                    value: (val / 1000).clamp(0.05, 1.0),
                                    minHeight: 8,
                                    backgroundColor: Colors.grey.shade200,
                                    valueColor: const AlwaysStoppedAnimation<Color>(Colors.blue),
                                  ),
                                ),
                              ],
                            ),
                          );
                        }),
                      ],
                    ),
                  ),
                )
              else
                Card(
                  elevation: 1,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: DataTable(
                      columns: state.reporte!.columns.map((c) {
                        return DataColumn(
                          label: Text(c.label, style: const TextStyle(fontWeight: FontWeight.bold)),
                          numeric: c.type != 'text',
                        );
                      }).toList(),
                      rows: state.reporte!.rows.map((row) {
                        return DataRow(
                          cells: state.reporte!.columns.map((c) {
                            final val = row[c.key]?.toString() ?? '-';
                            return DataCell(Text(val));
                          }).toList(),
                        );
                      }).toList(),
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
