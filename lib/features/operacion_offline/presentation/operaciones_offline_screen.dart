import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/offline/base_local.dart';
import '../../usuarios_catalogo/application/session_controller.dart';
import '../application/sincronizacion_controller.dart';
import '../domain/sincronizacion.dart';
import '../infrastructure/operaciones_dao.dart';
import '../infrastructure/sync_api.dart';
import 'offline_widgets.dart';
import 'reintegro_offline.dart';

class OperacionesOfflineScreen extends ConsumerStatefulWidget {
  const OperacionesOfflineScreen({super.key});
  @override
  ConsumerState<OperacionesOfflineScreen> createState() =>
      _OperacionesOfflineScreenState();
}

class _OperacionesOfflineScreenState
    extends ConsumerState<OperacionesOfflineScreen> {
  List<Map<String, Object?>> _operaciones = [];
  List<Map<String, dynamic>> _conflictos = [];
  String? _error;
  bool _ocupado = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(_cargar);
  }

  Future<void> _cargar() async {
    final user = ref.read(sessionProvider).usuario;
    if (user?.empresa == null) return;
    try {
      final base = ref.read(baseLocalProvider);
      final rows = await OperacionesDao(
        base,
      ).listarTodas(user!.empresa!.id, user.id);
      final db = await base.abrir();
      for (final row in rows.where((op) => op['tipo'] == 'COMPRA')) {
        final compraId = row['compra_id'] as String? ?? row['id'] as String;
        final compras = await db.query(
          'compras_locales',
          columns: ['estado', 'total', 'pago_vence_en'],
          where: 'id=? AND tenant_id=? AND usuario_id=?',
          whereArgs: [compraId, user.empresa!.id, user.id],
        );
        if (compras.isNotEmpty) {
          row['estado_compra'] = compras.single['estado'];
          row['total_compra'] = compras.single['total'];
          row['pago_vence_en'] = compras.single['pago_vence_en'];
        }
      }
      if (mounted) setState(() => _operaciones = rows);
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    }
  }

  Future<void> _sincronizar() async {
    setState(() {
      _ocupado = true;
      _error = null;
    });
    try {
      await ref
          .read(sincronizacionControllerProvider.notifier)
          .sincronizarAhora();
      await _cargar();
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  Future<void> _conflictosServidor() async {
    setState(() {
      _ocupado = true;
      _error = null;
    });
    try {
      final response = await SyncApi(
        ref.read(apiClientProvider),
      ).obtenerConflictos(estado: 'ALL');
      if (mounted) {
        setState(
          () => _conflictos = (response['items'] as List<dynamic>)
              .cast<Map<String, dynamic>>(),
        );
      }
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  Future<void> _resolver(Map<String, dynamic> conflict, String action) async {
    final note = TextEditingController();
    final lines = (conflict['lines'] as List<dynamic>? ?? [])
        .cast<Map<String, dynamic>>();
    final quantities = <String, int>{
      for (final line in lines)
        line['variant_id'] as String: (line['available_quantity'] as num)
            .toInt()
            .clamp(0, (line['requested_quantity'] as num).toInt()),
    };
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: Text(
            action == 'ADJUST' ? 'Ajustar cantidades' : 'Resolver conflicto',
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (action == 'ADJUST')
                  for (final line in lines)
                    TextFormField(
                      initialValue: '${quantities[line['variant_id']]}',
                      decoration: InputDecoration(
                        labelText: line['product_name'] as String,
                      ),
                      keyboardType: TextInputType.number,
                      onChanged: (value) =>
                          quantities[line['variant_id'] as String] =
                              int.tryParse(value) ?? -1,
                    ),
                TextField(
                  controller: note,
                  decoration: const InputDecoration(
                    labelText: 'Motivo (mínimo 5 caracteres)',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Volver'),
            ),
            FilledButton(
              onPressed: () {
                if (note.text.trim().length >= 5) Navigator.pop(context, true);
              },
              child: const Text('Confirmar'),
            ),
          ],
        ),
      ),
    );
    final reason = note.text.trim();
    note.dispose();
    if (confirmed != true || !mounted) return;
    setState(() => _ocupado = true);
    try {
      await SyncApi(ref.read(apiClientProvider)).resolverConflicto(
        conflict['id'] as String,
        resolucion: action,
        notas: reason,
        ajustesLinea: action == 'ADJUST' ? quantities : null,
      );
      await _conflictosServidor();
      await _sincronizar();
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  Future<void> _detalle(Map<String, Object?> operation) async {
    if (operation['tipo'] == 'COMPRA' && operation['server_ref'] is String) {
      context.push('/mi-cuenta/pedidos/${operation['server_ref']}');
      return;
    }
    final db = await ref.read(baseLocalProvider).abrir();
    final sales = operation['venta_id'] == null
        ? <Map<String, Object?>>[]
        : await db.query(
            'ventas_locales',
            where: 'id=? AND tenant_id=? AND usuario_id=?',
            whereArgs: [
              operation['venta_id'],
              operation['tenant_id'],
              operation['usuario_id'],
            ],
          );
    final items = sales.isEmpty
        ? <Map<String, Object?>>[]
        : await db.query(
            'venta_items_locales',
            where: 'venta_id=?',
            whereArgs: [operation['venta_id']],
          );
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          sales.isEmpty ? 'Operación local' : 'Comprobante de venta local',
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${operation['estado']} · ${operation['creada_en']}'),
              if (sales.isNotEmpty) ...[
                Text('Folio ${sales.single['folio']}'),
                if (sales.single['cliente_nombre'] != null)
                  Text('Cliente ${sales.single['cliente_nombre']}'),
                for (final item in items)
                  Text(
                    '${item['producto_nombre']} · ${item['cantidad']} · Bs ${item['total_linea']}',
                  ),
                Text(
                  'Total Bs ${sales.single['total']} · Vuelto Bs ${sales.single['vuelto']}',
                ),
              ],
              if (operation['server_numero'] != null)
                Text('Confirmación ${operation['server_numero']}'),
              if (operation['refund_amount'] != null)
                Text(
                  'Reintegro ${operation['refund_status'] == 'confirmed' ? 'confirmado' : 'pendiente'}: Bs ${operation['refund_amount']}',
                ),
              if (operation['ultimo_error'] != null)
                Text('${operation['ultimo_error']}'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(sincronizacionControllerProvider, (anterior, actual) {
      if (anterior?.sincronizando == true && !actual.sincronizando) {
        Future.microtask(_cargar);
      }
    });
    final sync = ref.watch(sincronizacionControllerProvider);
    final user = ref.watch(sessionProvider).usuario;
    final autenticado = ref.watch(sessionProvider).autenticado;
    final sesionVencida = !autenticado && sync.pendientes > 0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Operaciones locales'),
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(36),
          child: IndicadorSincronizacion(),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _cargar,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (_error != null)
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            if (sesionVencida)
              AvisoOffline(
                'Tenés ${sync.pendientes > 0 ? sync.pendientes : 1} ventas por subir. Iniciá sesión para enviarlas.',
                peligro: true,
              ),
            if (sync.ultimoError != null && !sesionVencida)
              Text(sync.ultimoError!),
            OutlinedButton.icon(
              onPressed: _ocupado || sync.sincronizando ? null : _sincronizar,
              icon: const Icon(Icons.sync),
              label: Text(
                sync.sincronizando ? 'Sincronizando…' : 'Sincronizar ahora',
              ),
            ),
            if (sync.ultimoResultado != null)
              Text(
                '${sync.ultimoResultado!.confirmed} confirmadas · ${sync.ultimoResultado!.conflicts} conflictos · ${sync.ultimoResultado!.rejected} rechazadas',
              ),
            OutlinedButton.icon(
              onPressed: () => context.push('/sin-conexion/historial'),
              icon: const Icon(Icons.history),
              label: const Text('Historial de sincronización'),
            ),
            for (final operation in _operaciones) ...[
              Builder(
                builder: (context) {
                  final tipoStr = etiquetaTipo(
                    operation['tipo'] as String? ?? '',
                  );
                  final estadoStr = etiquetaEstado(
                    operation['estado'] as String? ?? '',
                  );
                  final fecha = DateTime.tryParse(
                    operation['creada_en'] as String? ?? '',
                  );
                  final fechaStr = fecha != null
                      ? formatearFechaCorta(fecha.toLocal())
                      : (operation['creada_en'] as String? ?? '');
                  final esConflicto =
                      (operation['estado'] as String?)?.toUpperCase() ==
                      'CONFLICTO';
                  String? folio = operation['folio'] as String?;
                  String? totalStr;
                  if (operation['payload'] != null) {
                    try {
                      final payloadMap = jsonDecode(
                        operation['payload'] as String,
                      );
                      if (payloadMap is Map && payloadMap['total'] != null) {
                        totalStr = 'Bs ${payloadMap['total']}';
                      }
                    } catch (_) {}
                  }

                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      title: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              '$tipoStr${folio != null ? ' · $folio' : ''} · $fechaStr${totalStr != null ? ' · $totalStr' : ''}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: esConflicto
                                  ? Colors.amber.shade100
                                  : estadoStr == 'Confirmada'
                                  ? Colors.green.shade100
                                  : Colors.blue.shade100,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              estadoStr,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: esConflicto
                                    ? Colors.amber.shade900
                                    : estadoStr == 'Confirmada'
                                    ? Colors.green.shade900
                                    : Colors.blue.shade900,
                              ),
                            ),
                          ),
                        ],
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (operation['server_numero'] != null)
                            Text('Confirmación ${operation['server_numero']}'),
                          if (operation['tipo'] == 'COMPRA')
                            Text(switch (operation['estado_compra']) {
                              'PENDIENTE_PAGO' =>
                                'Pedido confirmado · pago pendiente',
                              'APARTADA_RETIRO' =>
                                'Confirmado · pago al retirar',
                              'EN_CONFLICTO' =>
                                'No se confirmó · revisá el aviso antes de volver a intentar',
                              'RECHAZADA_SIN_COBRO' || 'CANCELADA_SIN_COBRO' =>
                                'No se realizó ningún cobro',
                              _ =>
                                'Compra guardada en este dispositivo · todavía sin cobro',
                            }),
                          if (operation['tipo'] == 'COMPRA' &&
                              operation['server_ref'] is String)
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton.icon(
                                onPressed: () => _detalle(operation),
                                icon: Icon(
                                  operation['payment_required'] == 1
                                      ? Icons.credit_card
                                      : Icons.receipt_long,
                                ),
                                label: Text(
                                  operation['payment_required'] == 1
                                      ? 'Pagar / ver pedido'
                                      : 'Ver pedido',
                                ),
                              ),
                            ),
                          if (operation['refund_amount'] != null)
                            Text(
                              'Reintegro ${operation['refund_status'] == 'confirmed' ? 'confirmado' : 'pendiente'}: Bs ${operation['refund_amount']}',
                            ),
                          if (operation['ultimo_error'] != null)
                            Text('${operation['ultimo_error']}'),
                          if (esConflicto &&
                              user?.puede('sync_conflicts.read') == true)
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton.icon(
                                onPressed: () => _conflictosServidor(),
                                icon: const Icon(Icons.arrow_forward, size: 14),
                                label: const Text('Resolver →'),
                              ),
                            ),
                        ],
                      ),
                      onTap: () => _detalle(operation),
                    ),
                  );
                },
              ),
            ],
            if (_operaciones.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Text(
                  'No hay operaciones guardadas en este dispositivo.',
                  textAlign: TextAlign.center,
                ),
              ),
            if (user?.puede('sync_conflicts.read') == true)
              OutlinedButton(
                onPressed: _ocupado ? null : _conflictosServidor,
                child: const Text('Consultar conflictos de la empresa'),
              ),
            for (final conflict in _conflictos)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        '${conflict['type']} · ${conflict['branch_name'] ?? ''}',
                      ),
                      for (final line
                          in conflict['lines'] as List<dynamic>? ?? [])
                        Text(
                          '${line['product_name']} · solicitado ${line['requested_quantity']} · disponible ${line['available_quantity']}',
                        ),
                      if (conflict['refund'] is Map &&
                          user?.puede('sync_conflicts.resolve') == true)
                        ReintegroOffline(
                          key: ValueKey(
                            '${conflict['id']}-${(conflict['refund'] as Map)['status']}',
                          ),
                          conflictId: conflict['id'] as String,
                          refund: Map<String, dynamic>.from(
                            conflict['refund'] as Map,
                          ),
                          onActualizar: _conflictosServidor,
                        ),
                      if (conflict['status'] == 'OPEN' &&
                          user?.puede('sync_conflicts.resolve') == true) ...[
                        if (conflict['type'] == 'STOCK')
                          TextButton(
                            onPressed: _ocupado
                                ? null
                                : () => _resolver(conflict, 'ADJUST'),
                            child: const Text('Ajustar cantidades'),
                          ),
                        if (conflict['type'] == 'PRICE')
                          TextButton(
                            onPressed: _ocupado
                                ? null
                                : () => _resolver(conflict, 'AUTHORIZE_PRICE'),
                            child: const Text('Autorizar precio cobrado'),
                          ),
                        if (conflict['type'] == 'SUBSCRIPTION' ||
                            conflict['type'] == 'PRODUCT_INACTIVE')
                          TextButton(
                            onPressed: _ocupado
                                ? null
                                : () => _resolver(conflict, 'RETRY'),
                            child: const Text('Reevaluar'),
                          ),
                        TextButton(
                          onPressed: _ocupado
                              ? null
                              : () => _resolver(conflict, 'CANCEL'),
                          child: const Text('Rechazar operación'),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
