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
      final cajas = id == null ? <CajaLocal>[] : await control.dao.cajas(id);
      if (mounted) {
        setState(() {
          _cajas = cajas;
          _caja = cajas.firstOrNull?.id;
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    }
  }

  @override
  void dispose() {
    _efectivo.dispose();
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
          );
      if (!mounted) return;
      setState(() {
        _comprobante = venta;
        _cantidades.clear();
        _efectivo.clear();
      });
      await ref.read(catalogoOfflineProvider.notifier).iniciar();
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
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
            const Text(
              'COMPROBANTE PROVISIONAL',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            Text('${comprobante['folio']} · ${comprobante['estado']}'),
            Text(
              'Total Bs ${(comprobante['total'] as num).toStringAsFixed(2)}',
            ),
            Text(
              'Vuelto Bs ${(comprobante['vuelto'] as num).toStringAsFixed(2)}',
            ),
            FilledButton(
              onPressed: () => context.push('/sin-conexion/operaciones'),
              child: const Text('Consultar operaciones locales'),
            ),
            TextButton(
              onPressed: () => setState(() => _comprobante = null),
              child: const Text('Nueva venta'),
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
