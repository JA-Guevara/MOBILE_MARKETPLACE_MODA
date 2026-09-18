/// Envoltorio con el que responde el backend: `{ success, message, data }`.
///
/// Es el mismo contrato que consume el frontend web (`shared/models.ts`), así
/// que la app no necesita endpoints propios: lee exactamente lo mismo.
class ApiResponse<T> {
  const ApiResponse({required this.success, required this.message, required this.data});

  final bool success;
  final String message;
  final T data;

  factory ApiResponse.from(Map<String, dynamic> json, T Function(dynamic) parse) {
    return ApiResponse(
      success: json['success'] as bool? ?? true,
      message: json['message'] as String? ?? '',
      data: parse(json['data']),
    );
  }
}

/// Listado paginado del backend.
class Page<T> {
  const Page({
    required this.items,
    required this.total,
    required this.page,
    required this.pageSize,
    required this.pages,
  });

  final List<T> items;
  final int total;
  final int page;
  final int pageSize;
  final int pages;

  factory Page.from(Map<String, dynamic> json, T Function(Map<String, dynamic>) parse) {
    return Page(
      items: (json['items'] as List<dynamic>? ?? [])
          .map((row) => parse(row as Map<String, dynamic>))
          .toList(),
      total: json['total'] as int? ?? 0,
      page: json['page'] as int? ?? 1,
      pageSize: json['page_size'] as int? ?? 0,
      pages: json['pages'] as int? ?? 1,
    );
  }

  bool get hasMore => page < pages;
}
