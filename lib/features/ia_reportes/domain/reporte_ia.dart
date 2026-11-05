class ReportPeriod {
  const ReportPeriod({
    required this.dateFrom,
    required this.dateTo,
    this.label,
  });

  final String dateFrom;
  final String dateTo;
  final String? label;

  factory ReportPeriod.fromJson(Map<String, dynamic> json) {
    return ReportPeriod(
      dateFrom: json['date_from'] as String? ?? '',
      dateTo: json['date_to'] as String? ?? '',
      label: json['label'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'date_from': dateFrom,
        'date_to': dateTo,
        if (label != null) 'label': label,
      };
}

class ReportFilters {
  const ReportFilters({
    this.period,
    this.branchNames = const [],
    this.categoryNames = const [],
    this.productNames = const [],
    this.status,
    this.lowStockLt,
  });

  final ReportPeriod? period;
  final List<String> branchNames;
  final List<String> categoryNames;
  final List<String> productNames;
  final String? status;
  final int? lowStockLt;

  factory ReportFilters.fromJson(Map<String, dynamic> json) {
    return ReportFilters(
      period: json['period'] != null
          ? ReportPeriod.fromJson(json['period'] as Map<String, dynamic>)
          : null,
      branchNames: (json['branch_names'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      categoryNames: (json['category_names'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      productNames: (json['product_names'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      status: json['status'] as String?,
      lowStockLt: json['low_stock_lt'] as int?,
    );
  }

  Map<String, dynamic> toJson() => {
        if (period != null) 'period': period!.toJson(),
        'branch_names': branchNames,
        'category_names': categoryNames,
        'product_names': productNames,
        if (status != null) 'status': status,
        if (lowStockLt != null) 'low_stock_lt': lowStockLt,
      };
}

class ReportSpec {
  const ReportSpec({
    required this.definitionCode,
    this.metrics = const [],
    this.dimensions = const [],
    this.filters = const ReportFilters(),
    this.topN,
    this.order = 'desc',
    this.comparePrevious = false,
    this.chart,
  });

  final String definitionCode;
  final List<String> metrics;
  final List<String> dimensions;
  final ReportFilters filters;
  final int? topN;
  final String order;
  final bool comparePrevious;
  final String? chart;

  factory ReportSpec.fromJson(Map<String, dynamic> json) {
    return ReportSpec(
      definitionCode: json['definition_code'] as String? ?? 'ventas_por_sucursal',
      metrics: (json['metrics'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? const [],
      dimensions: (json['dimensions'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? const [],
      filters: json['filters'] != null
          ? ReportFilters.fromJson(json['filters'] as Map<String, dynamic>)
          : const ReportFilters(),
      topN: json['top_n'] as int?,
      order: json['order'] as String? ?? 'desc',
      comparePrevious: json['compare_previous'] as bool? ?? false,
      chart: json['chart'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'definition_code': definitionCode,
        'metrics': metrics,
        'dimensions': dimensions,
        'filters': filters.toJson(),
        if (topN != null) 'top_n': topN,
        'order': order,
        'compare_previous': comparePrevious,
        if (chart != null) 'chart': chart,
      };
}

class InterpretResult {
  const InterpretResult({
    required this.status,
    this.spec,
    this.questions = const [],
    this.assumptions = const [],
    this.suggestions = const [],
    this.interpreter = 'FALLBACK',
    this.requestId,
  });

  final String status; // 'READY', 'NEEDS_CLARIFICATION', 'UNSUPPORTED'
  final ReportSpec? spec;
  final List<String> questions;
  final List<String> assumptions;
  final List<String> suggestions;
  final String interpreter;
  final String? requestId;

  factory InterpretResult.fromJson(Map<String, dynamic> json) {
    return InterpretResult(
      status: json['status'] as String? ?? 'READY',
      spec: json['spec'] != null
          ? ReportSpec.fromJson(json['spec'] as Map<String, dynamic>)
          : null,
      questions: (json['questions'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? const [],
      assumptions: (json['assumptions'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? const [],
      suggestions: (json['suggestions'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? const [],
      interpreter: json['interpreter'] as String? ?? 'FALLBACK',
      requestId: json['request_id'] as String?,
    );
  }
}

class ReportColumn {
  const ReportColumn({
    required this.key,
    required this.label,
    this.type = 'text',
  });

  final String key;
  final String label;
  final String type; // 'text', 'money', 'int', 'pct'

  factory ReportColumn.fromJson(Map<String, dynamic> json) {
    return ReportColumn(
      key: json['key'] as String? ?? '',
      label: json['label'] as String? ?? '',
      type: json['type'] as String? ?? 'text',
    );
  }
}

class ReportResponse {
  const ReportResponse({
    this.requestId,
    required this.definitionCode,
    required this.title,
    this.columns = const [],
    this.rows = const [],
    this.totals = const {},
    this.chartKind = 'BAR',
    this.chartX = '',
    this.chartY = '',
    this.chartLabel = '',
    required this.narrative,
    this.durationMs = 0,
    this.usedCount = 0,
    this.limitCount = 1000,
  });

  final String? requestId;
  final String definitionCode;
  final String title;
  final List<ReportColumn> columns;
  final List<Map<String, dynamic>> rows;
  final Map<String, dynamic> totals;
  final String chartKind;
  final String chartX;
  final String chartY;
  final String chartLabel;
  final String narrative;
  final int durationMs;
  final int usedCount;
  final int limitCount;

  factory ReportResponse.fromJson(Map<String, dynamic> json) {
    final chartMap = json['chart'] as Map<String, dynamic>? ?? {};
    final usageMap = json['usage'] as Map<String, dynamic>? ?? {};

    return ReportResponse(
      requestId: json['request_id'] as String?,
      definitionCode: json['definition_code'] as String? ?? '',
      title: json['title'] as String? ?? '',
      columns: (json['columns'] as List<dynamic>?)
              ?.map((e) => ReportColumn.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
      rows: (json['rows'] as List<dynamic>?)
              ?.map((e) => Map<String, dynamic>.from(e as Map))
              .toList() ??
          const [],
      totals: json['totals'] as Map<String, dynamic>? ?? const {},
      chartKind: chartMap['kind'] as String? ?? 'BAR',
      chartX: chartMap['x'] as String? ?? '',
      chartY: chartMap['y'] as String? ?? '',
      chartLabel: chartMap['label'] as String? ?? '',
      narrative: json['narrative'] as String? ?? '',
      durationMs: json['duration_ms'] as int? ?? 0,
      usedCount: usageMap['used'] as int? ?? 0,
      limitCount: usageMap['limit'] as int? ?? 1000,
    );
  }
}

List<(String, String)> chipsDeSpec(ReportSpec spec) {
  final chips = <(String, String)>[];
  if (spec.filters.period != null) {
    final p = spec.filters.period!;
    chips.add(('Período', p.label ?? '${p.dateFrom} - ${p.dateTo}'));
  }
  if (spec.filters.branchNames.isNotEmpty) {
    chips.add(('Sucursales', spec.filters.branchNames.join(', ')));
  }
  if (spec.filters.categoryNames.isNotEmpty) {
    chips.add(('Categorías', spec.filters.categoryNames.join(', ')));
  }
  if (spec.topN != null) {
    chips.add(('Límite', 'Top ${spec.topN}'));
  }
  if (spec.comparePrevious) {
    chips.add(('Comparativa', 'vs. previo'));
  }
  return chips;
}
