import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../usuarios_catalogo/application/session_controller.dart';
import '../../ventas_pagos/infrastructure/commerce_api.dart';
import '../infrastructure/sync_api.dart';

class ReintegroOffline extends ConsumerStatefulWidget {
  const ReintegroOffline({
    super.key,
    required this.conflictId,
    required this.refund,
    required this.onActualizar,
  });
  final String conflictId;
  final Map<String, dynamic> refund;
  final Future<void> Function() onActualizar;
  @override
  ConsumerState<ReintegroOffline> createState() => _ReintegroOfflineState();
}

class _ReintegroOfflineState extends ConsumerState<ReintegroOffline> {
  final reference = TextEditingController();
  final attempt = CommerceApi.nuevaClaveSolicitud();
  bool confirmed = false, busy = false;
  String? error;
  @override
  void dispose() {
    reference.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    if (!confirmed || busy || reference.text.trim().length < 3) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await SyncApi(
        ref.read(apiClientProvider),
      ).confirmarReintegro(widget.conflictId, {
        'request_id': attempt,
        'amount': widget.refund['amount'],
        'reference': reference.text.trim(),
      });
      await widget.onActualizar();
    } catch (_) {
      if (mounted) {
        setState(
          () => error =
              'No se confirmó el reintegro. Revisá la conexión y el importe antes de volver a intentar.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final refund = widget.refund;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Reintegro ${refund['status'] == 'confirmed' ? 'confirmado' : 'pendiente'}: ${refund['currency']} ${refund['amount']}',
        ),
        if (refund['status'] == 'pending') ...[
          const Text(
            'Entregá el efectivo al cliente. Confirmar registra la entrega; no envía dinero automáticamente.',
          ),
          TextField(
            controller: reference,
            decoration: const InputDecoration(labelText: 'Referencia de caja'),
            maxLength: 255,
          ),
          CheckboxListTile(
            value: confirmed,
            onChanged: busy
                ? null
                : (value) => setState(() => confirmed = value ?? false),
            title: const Text('Entregué el importe completo al cliente'),
          ),
          FilledButton(
            onPressed: busy || !confirmed ? null : submit,
            child: const Text('Confirmar reintegro entregado'),
          ),
        ] else
          Text('Referencia: ${refund['reference'] ?? ''}'),
        if (error != null) Text(error!),
      ],
    );
  }
}
