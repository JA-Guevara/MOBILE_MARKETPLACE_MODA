import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/usuarios_catalogo/application/session_controller.dart';
import 'router.dart';
import 'theme.dart';

/// Raíz de la aplicación.
class FashionStoreApp extends ConsumerStatefulWidget {
  const FashionStoreApp({super.key});

  @override
  ConsumerState<FashionStoreApp> createState() => _FashionStoreAppState();
}

class _FashionStoreAppState extends ConsumerState<FashionStoreApp> {
  @override
  void initState() {
    super.initState();
    // Reabrir la sesión guardada antes de que el usuario toque nada.
    Future.microtask(() => ref.read(sessionProvider.notifier).restaurar());
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'FashionStore',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.claro,
      darkTheme: AppTheme.oscuro,
      routerConfig: ref.watch(routerProvider),
    );
  }
}

