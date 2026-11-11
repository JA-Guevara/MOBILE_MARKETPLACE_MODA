import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/offline/base_local.dart';
import '../../usuarios_catalogo/application/session_controller.dart';
import '../application/catalogo_offline_controller.dart';
import '../infrastructure/ventas_locales_dao.dart';
import '../domain/catalogo_local.dart';

class VentaOfflineScreen extends ConsumerStatefulWidget {
  const VentaOfflineScreen({super.key});
  @override
  ConsumerState<VentaOfflineScreen> createState() => _VentaOfflineScreenState();
}

class _VentaOfflineScreenState extends ConsumerState<VentaOfflineScreen> {
  final _efectivo = TextEditingController();
  final _buscarCliente = TextEditingController();
  ClienteLocal? _cliente;
  final _cantidades = <String, int>{};
  List<CajaLocal> _cajas = [];
  String? _caja, _error;
  String _busqueda = '';
  bool _guardando = false;
  Map<String, Object?>? _comprobante;

  @override
  void initState() {
    super.initState();
    Future.microtask(_cargar);
  }

  Future<void> _cargar() async {
    try {
      final control = ref.read(catalogoOfflineProvider.notifier);
      await control.iniciar();
      final id = ref.read(catalogoOfflineProvider).sucursalId;
      var cajas = id == null ? <CajaLocal>[] : await control.dao.cajas(id);
      if (cajas.isEmpty && id != null) {
        cajas = [
          CajaLocal(
            id: 'caja-principal-$id',
            sucursalId: id,
            nombre: 'Caja 1 (Principal)',
            codigo: 'CAJA-01',
          ),
        ];
      }
      if (mounted) {
        setState(() {
          _cajas = cajas;
          _caja = _caja ?? cajas.firstOrNull?.id;
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    }
  }

  @override
  void dispose() {
    _efectivo.dispose();
    _buscarCliente.dispose();
    super.dispose();
  }

  Future<void> _cobrar() async {
    if (_guardando) return;
    setState(() {
      _guardando = true;
      _error = null;
    });
    try {
      final usuario = ref.read(sessionProvider).usuario;
      if (usuario == null || _caja == null) {
        throw StateError('Elegí una caja autorizada.');
      }
      final venta = await VentasLocalesDao(ref.read(baseLocalProvider))
          .registrar(
            usuario: usuario,
            cajaId: _caja!,
            cantidades: _cantidades,
            recibido:
                double.tryParse(_efectivo.text.replaceAll(',', '.')) ??
                double.nan,
            clienteId: _cliente?.id,
          );
      if (!mounted) return;
      setState(() {
        _comprobante = venta;
        _cantidades.clear();
        _efectivo.clear();
        _cliente = null;
        _buscarCliente.clear();
      });
      await ref.read(catalogoOfflineProvider.notifier).iniciar();
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  /// CU-18: cliente opcional, buscado por nombre entre los clientes que el
  /// snapshot de la empresa dejó en este dispositivo.
  Widget _selectorCliente(List<ClienteLocal> clientes) {
    final elegido = _cliente;
    if (elegido != null) {
      return ListTile(
        key: const Key('venta-cliente-elegido'),
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.person),
        title: Text(elegido.nombre),
        subtitle: const Text('Cliente de la venta'),
        trailing: IconButton(
          tooltip: 'Quitar cliente',
          onPressed: _guardando
              ? null
              : () => setState(() {
                  _cliente = null;
                  _buscarCliente.clear();
                }),
          icon: const Icon(Icons.close),
        ),
      );
    }
    final texto = _buscarCliente.text.trim().toLowerCase();
    final coincidencias = texto.isEmpty
        ? const <ClienteLocal>[]
        : clientes
              .where((c) => c.nombre.toLowerCase().contains(texto))
              .take(5)
              .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          key: const Key('venta-buscar-cliente'),
          controller: _buscarCliente,
          enabled: !_guardando && clientes.isNotEmpty,
          decoration: InputDecoration(
            labelText: 'Cliente (opcional)',
            hintText: clientes.isEmpty
                ? 'No hay clientes descargados'
                : 'Buscar por nombre',
            prefixIcon: const Icon(Icons.person_search),
          ),
          onChanged: (_) => setState(() {}),
        ),
        for (final c in coincidencias)
          ListTile(
            dense: true,
            title: Text(c.nombre),
            subtitle: c.documentoFinal == null
                ? null
                : Text('Documento …${c.documentoFinal}'),
            onTap: () => setState(() {
              _cliente = c;
              _buscarCliente.clear();
            }),
          ),
        if (texto.isNotEmpty && coincidencias.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text(
              'Sin coincidencias. La venta puede seguir sin cliente.',
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final estado = ref.watch(catalogoOfflineProvider);
    final datos = estado.datos;
    final variantes = datos.variantes
        .where(
          (v) =>
              v.activa &&
              ('${v.sku} ${datos.productos.where((p) => p.id == v.productoId).firstOrNull?.nombre ?? ''}')
                  .toLowerCase()
                  .contains(_busqueda.toLowerCase()),
        )
        .toList();
    var total = 0.0;
    for (final v in datos.variantes) {
      final producto = datos.productos
          .where((p) => p.id == v.productoId)
          .firstOrNull;
      total +=
          (v.precio ?? producto?.precioBase ?? 0) * (_cantidades[v.id] ?? 0);
    }
    final comprobante = _comprobante;
    return Scaffold(
      appBar: AppBar(title: const Text('Venta de contado local')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Pago en efectivo. La aceptación definitiva se confirma al sincronizar.',
          ),
          if (_error != null)
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          if (comprobante != null) ...[
            Container(
              margin: const EdgeInsets.symmetric(vertical: 12),
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFF86EFAC), width: 1.5),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: const BoxDecoration(
                      color: Color(0xFFDCFCE7),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.check_circle_rounded, color: Color(0xFF16A34A), size: 34),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    '¡Venta Provisional Registrada!',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Folio: #${comprobante['folio']} · ${comprobante['estado']}',
                    style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13),
                  ),
                  if (comprobante['cliente_nombre'] != null) ...[
                    const SizedBox(height: 4),
                    Text('Cliente: ${comprobante['cliente_nombre']}', style: const TextStyle(fontWeight: FontWeight.w600)),
                  ],
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Column(
                      children: [
                        Text('TOTAL COBRADO', style: TextStyle(fontSize: 11, letterSpacing: 1.1, color: Colors.grey[600], fontWeight: FontWeight.bold)),
                        const SizedBox(height: 2),
                        Text(
                          'Bs ${(comprobante['total'] as num).toStringAsFixed(2)}',
                          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Color(0xFF1E293B)),
                        ),
                        if ((comprobante['vuelto'] as num? ?? 0) > 0) ...[
                          const SizedBox(height: 6),
                          Text(
                            'Vuelto a entregar: Bs ${(comprobante['vuelto'] as num).toStringAsFixed(2)}',
                            style: const TextStyle(color: Color(0xFF16A34A), fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: () => context.push('/sin-conexion/operaciones'),
                    icon: const Icon(Icons.list_alt_rounded),
                    label: const Text('Consultar operaciones locales'),
                  ),
                  const SizedBox(height: 6),
                  TextButton.icon(
                    onPressed: () => setState(() => _comprobante = null),
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Nueva venta'),
                  ),
                ],
              ),
            ),
          ] else if (estado.version == null) ...[
            const Text('Prepará el catálogo de tu empresa antes de vender.'),
            TextButton(
              onPressed: () => context.push('/sin-conexion'),
              child: const Text('Preparar catálogo'),
            ),
          ] else ...[
            DropdownButtonFormField<String>(
              initialValue: _caja,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Caja'),
              items: _cajas
                  .map(
                    (c) => DropdownMenuItem(value: c.id, child: Text(c.nombre)),
                  )
                  .toList(),
              onChanged: _guardando
                  ? null
                  : (value) => setState(() => _caja = value),
            ),
            _selectorCliente(datos.clientes),
            TextField(
              decoration: const InputDecoration(
                labelText: 'Buscar por prenda o SKU',
              ),
              onChanged: (value) => setState(() => _busqueda = value),
            ),
            for (final variant in variantes)
              ListTile(
                title: Text(
                  datos.productos
                          .where((p) => p.id == variant.productoId)
                          .firstOrNull
                          ?.nombre ??
                      variant.sku,
                ),
                subtitle: Text(
                  '${variant.talla} · ${variant.color} · Stock ${datos.stock(variant.id)}',
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      onPressed: _guardando
                          ? null
                          : () => setState(() {
                              final n = _cantidades[variant.id] ?? 0;
                              if (n > 1) {
                                _cantidades[variant.id] = n - 1;
                              } else {
                                _cantidades.remove(variant.id);
                              }
                            }),
                      icon: const Icon(Icons.remove),
                    ),
                    Text('${_cantidades[variant.id] ?? 0}'),
                    IconButton(
                      onPressed: _guardando
                          ? null
                          : () => setState(() {
                              final n = _cantidades[variant.id] ?? 0;
                              if (n < datos.stock(variant.id)) {
                                _cantidades[variant.id] = n + 1;
                              }
                            }),
                      icon: const Icon(Icons.add),
                    ),
                  ],
                ),
              ),
            Text('Total Bs ${total.toStringAsFixed(2)}'),
            TextField(
              controller: _efectivo,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(labelText: 'Efectivo recibido'),
            ),
            FilledButton(
              onPressed: _guardando || _cantidades.isEmpty ? null : _cobrar,
              child: Text(
                _guardando ? 'Guardando…' : 'Cobrar y guardar venta local',
              ),
            ),
          ],
        ],
      ),
    );
  }
}
