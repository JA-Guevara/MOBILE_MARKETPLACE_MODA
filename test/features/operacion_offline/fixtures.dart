import 'package:mobile_marketplace_moda/features/operacion_offline/domain/catalogo_local.dart';
import 'package:mobile_marketplace_moda/features/operacion_offline/domain/reserva_local.dart';
import 'package:mobile_marketplace_moda/features/usuarios_catalogo/domain/usuario.dart';

Map<String, dynamic> snapshotJson({
  String tenant = 'tenant-a',
  String version = '2026-10-23T12:00:00Z',
  bool full = true,
  int stock = 4,
}) => {
  'version': version,
  'generated_at': DateTime.tryParse(version) != null ? version : '2026-10-23T12:00:00Z',
  'full': full,
  'tenant': {
    'id': tenant,
    'slug': tenant,
    'trade_name': 'Moda local',
    'status': 'ACTIVA',
  },
  'branches': [
    {'id': 'b1', 'code': 'CENTRO', 'name': 'Centro', 'address': 'Calle 1'},
    {'id': 'b2', 'code': 'NORTE', 'name': 'Norte', 'address': 'Calle 2'},
  ],
  'products': [
    {
      'id': 'p1',
      'name': 'Vestido lino Aurora',
      'slug': 'vestido',
      'category': 'Vestidos',
      'brand': 'Aurora',
      'base_price': '320.00',
      'offer_price': '289.00',
      'image_url': null,
      'is_featured': true,
    },
    {
      'id': 'p2',
      'name': 'Polera básica algodón',
      'slug': 'polera',
      'category': 'Poleras',
      'brand': 'Rio',
      'base_price': 89,
      'offer_price': null,
      'image_url': null,
      'is_featured': false,
    },
  ],
  'variants': [
    {
      'id': 'v1',
      'product_id': 'p1',
      'sku': 'V-S',
      'size': 'S',
      'color': 'Borgoña',
      'color_hex': '#74394e',
      'price': null,
      'is_active': true,
    },
    {
      'id': 'v2',
      'product_id': 'p1',
      'sku': 'V-M',
      'size': 'M',
      'color': 'Borgoña',
      'color_hex': '#74394e',
      'price': null,
      'is_active': true,
    },
    {
      'id': 'v3',
      'product_id': 'p1',
      'sku': 'V-L',
      'size': 'L',
      'color': 'Azul',
      'color_hex': '#0000ff',
      'price': '300',
      'is_active': true,
    },
    {
      'id': 'v4',
      'product_id': 'p2',
      'sku': 'P-M',
      'size': 'M',
      'color': 'Negro',
      'color_hex': '#000000',
      'price': null,
      'is_active': true,
    },
    {
      'id': 'v5',
      'product_id': 'p2',
      'sku': 'P-L',
      'size': 'L',
      'color': 'Negro',
      'color_hex': '#000000',
      'price': null,
      'is_active': false,
    },
  ],
  'stock': [
    {'variant_id': 'v1', 'branch_id': 'b1', 'quantity': stock},
    {'variant_id': 'v2', 'branch_id': 'b1', 'quantity': 1},
    {'variant_id': 'v4', 'branch_id': 'b1', 'quantity': 22},
    {'variant_id': 'v1', 'branch_id': 'b2', 'quantity': 8},
  ],
  'customers': [
    {
      'id': 'c1',
      'name': 'Ana Perez',
      'document_tail': '123',
      'phone': '70123456',
    },
  ],
  'removed': {'products': [], 'variants': []},
};
InstantaneaCatalogo instantanea({
  String tenant = 'tenant-a',
  String version = '2026-10-23T12:00:00Z',
  bool full = true,
  int stock = 4,
}) => InstantaneaCatalogo.desdeJson(
  snapshotJson(tenant: tenant, version: version, full: full, stock: stock),
);
Usuario usuarioOffline({
  String id = 'u1',
  String tenant = 'tenant-a',
  String estado = 'ACTIVA',
  String fin = '2030-12-31',
}) => Usuario.desdeJson({
  'id': id,
  'email': 'ana@example.test',
  'first_name': 'Ana',
  'last_name': 'Perez',
  'roles': [
    {
      'permissions': ['reservations.write'],
    },
  ],
  'tenant': {
    'id': tenant,
    'slug': tenant,
    'trade_name': 'Moda local',
    'status': 'ACTIVA',
  },
  'subscription': {
    'plan_code': 'BASICO',
    'plan_name': 'Básico',
    'status': estado,
    'end_date': fin,
    'features': {'offline': true, 'reservations': true},
    'limits': {'max_active_branches': 2},
  },
});
ReservaLocal reserva({
  String id = '12345678-abcd-4567-8910-123456789012',
  String tenant = 'tenant-a',
  String usuario = 'u1',
  String branch = 'b1',
}) => ReservaLocal(
  id: id,
  tenantId: tenant,
  sucursalId: branch,
  usuarioId: usuario,
  agendadaPara: DateTime.utc(2030, 10, 25, 14, 30),
  creadaEn: DateTime.utc(2026, 10, 23, 20, 42),
);
List<ItemReservaLocal> itemsPara(
  ReservaLocal r, {
  int cantidad = 2,
  String variante = 'v1',
}) => [
  ItemReservaLocal(reservaId: r.id, varianteId: variante, cantidad: cantidad),
];
OperacionPendiente operacion(ReservaLocal r, List<ItemReservaLocal> items) =>
    OperacionPendiente(
      id: 'op-${r.id}',
      tenantId: r.tenantId,
      sucursalId: r.sucursalId,
      usuarioId: r.usuarioId,
      dispositivoId: 'dispositivo-test',
      payload: construirPayload(r, items, 'dispositivo-test'),
      creadaEn: r.creadaEn,
      actualizadaEn: r.creadaEn,
    );

const instantaneaSinSucursales = {
  'success': false,
  'error': {
    'code': 'no_authorized_branches',
    'message':
        'Tu usuario no tiene sucursales asignadas. Pedile al administrador que te asigne una.',
  },
};

const instantaneaSinModulo = {
  'success': false,
  'error': {
    'code': 'feature_not_in_plan',
    'message': 'Tu plan no incluye la operación sin conexión.',
    'details': {
      'module_code': 'offline',
    },
  },
};

const loteConfirmada = {
  'batch_id': 'cccccccc-0000-4000-8000-000000000001',
  'received_at': '2026-11-11T15:00:02Z',
  'request_id': 'req-0001',
  'results': [
    {
      'client_request_id': 'bbbbbbbb-0000-4000-8000-000000000001',
      'status': 'CONFIRMED',
      'server_ref': 'dddddddd-0000-4000-8000-000000000001',
      'server_number': 'FS-A8F3D1',
      'conflict_id': null,
      'conflict_type': null,
      'reason_code': null,
      'message': 'Venta sincronizada y confirmada exitosamente.',
      'replay': false,
      'refund_amount': null,
      'refund_status': null,
    },
  ],
};

const loteConflicto = {
  'batch_id': 'cccccccc-0000-4000-8000-000000000002',
  'received_at': '2026-11-11T15:00:04Z',
  'request_id': 'req-0002',
  'results': [
    {
      'client_request_id': 'bbbbbbbb-0000-4000-8000-000000000001',
      'status': 'CONFLICT',
      'server_ref': null,
      'server_number': null,
      'conflict_id': 'c0ffee00-0000-4000-8000-000000000201',
      'conflict_type': 'STOCK',
      'reason_code': null,
      'message': 'Stock insuficiente en 1 prenda(s).',
      'replay': false,
      'refund_amount': null,
      'refund_status': null,
    },
  ],
};

const loteReintentar = {
  'batch_id': 'cccccccc-0000-4000-8000-000000000003',
  'received_at': '2026-11-11T15:00:06Z',
  'request_id': 'req-0003',
  'results': [
    {
      'client_request_id': 'bbbbbbbb-0000-4000-8000-000000000001',
      'status': 'RETRY',
      'server_ref': null,
      'server_number': null,
      'conflict_id': null,
      'conflict_type': null,
      'reason_code': 'server_error',
      'message':
          'No se pudo confirmar la operación. Se conserva para reintentar.',
      'replay': false,
      'refund_amount': null,
      'refund_status': null,
    },
  ],
};

const loteSesionVencida = {
  'success': false,
  'error': {
    'code': 'unauthenticated',
    'message': 'Tu sesión venció. Iniciá sesión para continuar.',
  },
};

const pingOk = {
  'status': 'ok',
};

