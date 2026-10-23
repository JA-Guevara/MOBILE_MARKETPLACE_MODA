import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/offline/conectividad.dart';
import '../../../shared/widgets/indicador_conexion.dart';
import '../../usuarios_catalogo/application/session_controller.dart';
import '../../usuarios_catalogo/presentation/catalog_screen.dart';
import '../application/catalogo_offline_controller.dart';
import 'catalogo_offline_screen.dart';

class CatalogoAdaptable extends ConsumerWidget {
  const CatalogoAdaptable({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(catalogoOfflineProvider);
    final offline =
        ref.watch(conectividadProvider).asData?.value == false ||
        ref.watch(sessionProvider).sinConexion;
    if (offline) return const CatalogoOfflineScreen();
    return const Stack(
      children: [
        CatalogScreen(),
        Positioned(
          top: 0,
          right: 8,
          child: SafeArea(child: IndicadorConexion()),
        ),
      ],
    );
  }
}
