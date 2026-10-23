import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/usuarios_catalogo/application/session_controller.dart';
import '../features/ventas_pagos/application/pedidos_controller.dart';
import '../features/ventas_pagos/application/commerce_providers.dart';
import '../features/ventas_pagos/infrastructure/pending_payment_store.dart';
import 'router.dart';
import 'theme.dart';

/// Raíz de la aplicación.
class FashionStoreApp extends ConsumerStatefulWidget {
  const FashionStoreApp({super.key});

  @override
  ConsumerState<FashionStoreApp> createState() => _FashionStoreAppState();
}

class _FashionStoreAppState extends ConsumerState<FashionStoreApp>
    with WidgetsBindingObserver {
  bool _verificandoPago = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Reabrir la sesión guardada antes de que el usuario toque nada.
    Future.microtask(() => ref.read(sessionProvider.notifier).restaurar());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_verificarPagoPendiente());
    }
  }

  Future<void> _verificarPagoPendiente() async {
    if (_verificandoPago || !mounted || !ref.read(sessionProvider).autenticado) {
      return;
    }
    _verificandoPago = true;
    try {
      final almacen = ref.read(pendingPaymentStoreProvider);
      final id = await almacen.read();
      if (id == null || !mounted) return;
      // Stripe y su webhook pueden tardar unos segundos en quedar sincronizados.
      for (var intento = 0; intento < 3; intento++) {
        if (intento > 0) await Future<void>.delayed(const Duration(seconds: 2));
        if (!mounted || !ref.read(sessionProvider).autenticado) return;
        final pedido = await ref.read(commerceApiProvider).reconciliarPagoPedido(id);
        if (!mounted) return;
        ref.invalidate(pedidoProvider(id));
        unawaited(ref.read(pedidosProvider.notifier).cargar());
        if (pedido.paymentStatus == 'paid' ||
            pedido.status == 'cancelled' ||
            pedido.status == 'expired' ||
            pedido.paymentStatus == 'cancelled') {
          await almacen.clear();
          return;
        }
      }
    } catch (_) {
      // Se conserva el pedido pendiente para reintentar con conexión.
    } finally {
      _verificandoPago = false;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(sessionProvider, (_, actual) {
      if (actual.autenticado) unawaited(_verificarPagoPendiente());
    });
    return MaterialApp.router(
      title: 'FashionStore',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.claro,
      darkTheme: AppTheme.oscuro,
      routerConfig: ref.watch(routerProvider),
    );
  }
}

