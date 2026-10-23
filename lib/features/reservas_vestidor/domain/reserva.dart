/// Modelos de reservas (`/reservations`).
///
/// La capa de reservas no existía en el móvil: ni modelos, ni API, ni
/// controlador. Se escribe acá siguiendo el mismo contrato que consume la web
/// en `reservas.service.ts` y que devuelve `reserva_data()` del backend.
library;

/// Una prenda reservada para probarse: variante y cuántas unidades.
class ItemReserva {
  const ItemReserva({
    required this.variantId,
    required this.cantidad,
    this.producto = '',
    this.talla = '',
    this.color = '',
    this.imagenUrl,
  });

  final String variantId;
  final int cantidad;

  /// Los datos de la prenda no siempre vienen en la reserva guardada: el
  /// backend persiste `{variant_id, quantity}` y agrega el resto cuando puede.
  final String producto;
  final String talla;
  final String color;
  final String? imagenUrl;

  String get etiqueta =>
      [talla, color].where((t) => t.isNotEmpty).join(' · ');

  Map<String, dynamic> aJson() => {
        'variant_id': variantId,
        'quantity': cantidad,
      };

  factory ItemReserva.desdeJson(Map<String, dynamic> json) => ItemReserva(
        variantId: '${json['variant_id']}',
        cantidad: (json['quantity'] as num?)?.toInt() ?? 1,
        producto: json['product'] as String? ?? json['name'] as String? ?? '',
        talla: json['size'] as String? ?? '',
        color: json['color'] as String? ?? '',
        imagenUrl: json['image_url'] as String?,
      );

  ItemReserva copyWith({int? cantidad}) => ItemReserva(
        variantId: variantId,
        cantidad: cantidad ?? this.cantidad,
        producto: producto,
        talla: talla,
        color: color,
        imagenUrl: imagenUrl,
      );
}

/// Una etapa del seguimiento de la reserva.
class PasoReserva {
  const PasoReserva({required this.estado, this.nota = '', this.fecha = ''});

  final String estado;
  final String nota;
  final String fecha;

  String get etiqueta => etiquetaReserva(estado);

  factory PasoReserva.desdeJson(Map<String, dynamic> json) => PasoReserva(
        estado: json['status'] as String? ?? '',
        nota: json['note'] as String? ?? '',
        fecha: json['date'] as String? ?? json['at'] as String? ?? '',
      );
}

/// Visita agendada para probarse prendas en una sucursal (RF09–RF12).
class Reserva {
  const Reserva({
    required this.id,
    required this.branchId,
    required this.estado,
    required this.agendadaPara,
    this.items = const [],
    this.notas,
    this.tracking = const [],
    this.sucursal,
    this.creadaEn = '',
    this.inventarioApartado = false,
  });

  final String id;
  final String branchId;
  final String estado;

  /// ISO. El backend la guarda en UTC y la app la muestra en hora local.
  final String agendadaPara;

  final List<ItemReserva> items;
  final String? notas;
  final List<PasoReserva> tracking;
  final String? sucursal;
  final String creadaEn;
  final bool inventarioApartado;

  String get etiquetaEstado => etiquetaReserva(estado);

  /// El backend solo permite cancelar desde `pending`, `confirmed` y `ready`.
  bool get sePuedeCancelar =>
      const ['pending', 'confirmed', 'ready'].contains(estado);

  int get unidades => items.fold(0, (total, item) => total + item.cantidad);

  factory Reserva.desdeJson(Map<String, dynamic> json) => Reserva(
        id: '${json['id']}',
        branchId: '${json['branch_id']}',
        estado: json['status'] as String? ?? '',
        agendadaPara: '${json['scheduled_at'] ?? ''}',
        items: (json['items'] as List<dynamic>? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(ItemReserva.desdeJson)
            .toList(),
        notas: json['notes'] as String?,
        tracking: (json['tracking'] as List<dynamic>? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(PasoReserva.desdeJson)
            .toList(),
        sucursal: json['branch_name'] as String?,
        creadaEn: '${json['created_at'] ?? ''}',
        inventarioApartado: json['inventory_held'] as bool? ?? false,
      );
}

/// Respuesta de `/reservations/availability` para una variante.
class DisponibilidadVariante {
  const DisponibilidadVariante({
    required this.variantId,
    required this.disponible,
    required this.cantidad,
    required this.pedidas,
    this.producto,
    this.talla,
    this.color,
    this.motivo,
  });

  final String variantId;
  final bool disponible;
  final int cantidad;
  final int pedidas;
  final String? producto;
  final String? talla;
  final String? color;

  /// Por qué no alcanza. El backend lo escribe en español ya listo para mostrar.
  final String? motivo;

  factory DisponibilidadVariante.desdeJson(Map<String, dynamic> json) =>
      DisponibilidadVariante(
        variantId: '${json['variant_id']}',
        disponible: json['available'] as bool? ?? false,
        cantidad: (json['quantity'] as num?)?.toInt() ?? 0,
        pedidas: (json['requested'] as num?)?.toInt() ?? 0,
        producto: json['product'] as String?,
        talla: json['size'] as String?,
        color: json['color'] as String?,
        motivo: json['reason'] as String?,
      );
}

// --- Etiquetas (mismas palabras que la web) ---

const Map<String, String> _reservas = {
  'pending': 'Pendiente de confirmar',
  'confirmed': 'Confirmada',
  'ready': 'Lista para tu visita',
  'attended': 'Atendida',
  'cancelled': 'Cancelada',
  'expired': 'Vencida',
};

String etiquetaReserva(String valor) => _reservas[valor] ?? valor;

/// Escala de color de la web (`ok`, `aviso`, `mal`).
String colorDeEstadoReserva(String estado) => switch (estado) {
      'attended' || 'ready' => 'ok',
      'cancelled' || 'expired' => 'mal',
      'pending' => 'aviso',
      _ => '',
    };

/// Límites que impone el backend al crear una reserva (RF09).
const int maxVariantesPorReserva = 20;
const int maxUnidadesPorVariante = 10;
