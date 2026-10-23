import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../shared/formato.dart';
import '../../../shared/widgets/estado_vista.dart';
import '../application/favoritos_controller.dart';
import '../domain/commerce_models.dart';

/// «Mis favoritos» (`/mi-cuenta/favoritos`).
///
/// Los avisos de stock y de precio son el motivo real de guardar algo: si no
/// se pueden ver ni cambiar acá, la sección es una lista de deseos muda.
class FavoritosScreen extends ConsumerStatefulWidget {
  const FavoritosScreen({super.key});

  @override
  ConsumerState<FavoritosScreen> createState() => _FavoritosScreenState();
}

class _FavoritosScreenState extends ConsumerState<FavoritosScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(favoritosProvider.notifier).cargar());
  }

  @override
  Widget build(BuildContext context) {
    final estado = ref.watch(favoritosProvider);
    final control = ref.read(favoritosProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: const Text('Mis favoritos')),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: control.cargar,
          child: _cuerpo(estado, control),
        ),
      ),
    );
  }

  Widget _cuerpo(EstadoFavoritos estado, FavoritosController control) {
    if (estado.cargando && estado.favoritos.isEmpty) {
      return const VistaCargando(mensaje: 'Buscando tus favoritos…');
    }
    if (estado.error != null && estado.favoritos.isEmpty) {
      return VistaError(mensaje: estado.error!, onReintentar: control.cargar);
    }
    if (estado.favoritos.isEmpty) {
      return VistaVacia(
        icono: Icons.favorite_border,
        titulo: 'Todavía no guardaste ninguna prenda',
        mensaje: 'Tocá el corazón en una prenda y te avisamos si vuelve el stock '
            'o si baja el precio.',
        accionIcono: Icons.storefront_outlined,
        accionTexto: 'Ver el catálogo',
        onAccion: () => context.go('/'),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: estado.favoritos.length,
      separatorBuilder: (_, __) => const Divider(height: 24),
      itemBuilder: (context, indice) => _TarjetaFavorito(
        favorito: estado.favoritos[indice],
        ocupado: estado.ocupado,
        control: control,
      ),
    );
  }
}

class _TarjetaFavorito extends StatelessWidget {
  const _TarjetaFavorito({
    required this.favorito,
    required this.ocupado,
    required this.control,
  });

  final Favorito favorito;
  final bool ocupado;
  final FavoritosController control;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => context.push('/prendas/${favorito.slug}'),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(
                  width: 70,
                  height: 88,
                  child: favorito.imageUrl == null
                      ? Container(color: tema.colorScheme.surfaceContainerHighest)
                      : CachedNetworkImage(
                          imageUrl: favorito.imageUrl!,
                          fit: BoxFit.cover,
                          errorWidget: (_, __, ___) => Container(
                              color: tema.colorScheme.surfaceContainerHighest),
                        ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(favorito.name, style: tema.textTheme.titleSmall),
                    Text(Formato.moneda(favorito.basePrice),
                        style: tema.textTheme.bodyMedium),
                  ],
                ),
              ),
              IconButton(
                onPressed: ocupado ? null : () => control.quitar(favorito),
                icon: const Icon(Icons.favorite),
                tooltip: 'Quitar de favoritos',
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        SwitchListTile(
          value: favorito.stockAlert,
          onChanged: ocupado
              ? null
              : (valor) => control.cambiarAvisos(favorito, stock: valor),
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: const Text('Avisarme si vuelve el stock'),
        ),
        SwitchListTile(
          value: favorito.priceAlert,
          onChanged: ocupado
              ? null
              : (valor) => control.cambiarAvisos(favorito, precio: valor),
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: const Text('Avisarme si baja el precio'),
        ),
      ],
    );
  }
}
