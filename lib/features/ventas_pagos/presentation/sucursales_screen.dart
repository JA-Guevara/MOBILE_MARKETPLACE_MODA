import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../shared/widgets/estado_vista.dart';
import '../application/commerce_providers.dart';
import '../domain/commerce_models.dart';

/// Sucursales (`/sucursales`), réplica de `branches-page.component.ts`.
///
/// Es pública: sirve para saber dónde retirar antes de tener cuenta.
final FutureProvider<List<Sucursal>> sucursalesProvider =
    FutureProvider<List<Sucursal>>(
        (ref) => ref.watch(commerceApiProvider).sucursales());

class SucursalesScreen extends ConsumerWidget {
  const SucursalesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sucursales = ref.watch(sucursalesProvider);
    final tema = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Sucursales')),
      body: SafeArea(
        child: sucursales.when(
          loading: () => const VistaCargando(mensaje: 'Buscando sucursales…'),
          error: (error, _) => VistaError(
            mensaje: error is ApiException
                ? error.message
                : 'No pudimos traer las sucursales.',
            onReintentar: () => ref.invalidate(sucursalesProvider),
          ),
          data: (lista) => lista.isEmpty
              ? const VistaVacia(
                  icono: Icons.store_outlined,
                  titulo: 'Todavía no hay sucursales publicadas',
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: lista.length,
                  separatorBuilder: (_, __) => const Divider(height: 20),
                  itemBuilder: (context, indice) {
                    final sucursal = lista[indice];
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.storefront_outlined),
                      title: Text(sucursal.nombre),
                      subtitle: sucursal.direccion.isEmpty
                          ? null
                          : Text(sucursal.direccion,
                              style: tema.textTheme.bodySmall),
                    );
                  },
                ),
        ),
      ),
    );
  }
}
