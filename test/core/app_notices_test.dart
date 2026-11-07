import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_marketplace_moda/app/router.dart';
import 'package:mobile_marketplace_moda/core/notifications/app_notices.dart';
import 'package:mobile_marketplace_moda/core/notifications/notices_host.dart';
import 'package:mobile_marketplace_moda/features/usuarios_catalogo/application/session_controller.dart';

final identity = StateProvider<(String?, String?)>(
  (ref) => ('customer-a', 'tenant-a'),
);

void main() {
  test('pendiente no anuncia un pago confirmado', () {
    final notice = paymentNotice(
      id: 'o1',
      number: 'FS-001',
      amount: 150,
      currency: 'BOB',
      status: 'pending',
    );
    expect(notice.tone, 'warning');
    expect(notice.title, 'Pago pendiente de confirmación');
    expect(notice.detail, contains('Todavía no se confirmó'));
  });
  test(
    'confirmación incluye importe y referencia y no se repite en la sesión',
    () {
      final queue = AppNotices();
      final notice = paymentNotice(
        id: 'o1',
        number: 'FS-001',
        amount: 150,
        currency: 'BOB',
        status: 'paid',
      );
      queue.show(notice);
      queue.show(notice);
      expect(queue.state, hasLength(1));
      expect(queue.state.single.detail, contains('150.00 BOB'));
      expect(queue.state.single.important, isTrue);
      queue.dismiss(notice.key);
      queue.show(notice);
      expect(queue.state, isEmpty);
      queue.dispose();
    },
  );
  test('al cambiar de empresa se descartan las ventanas de la anterior', () {
    final container = ProviderContainer(
      overrides: [
        identidadSesionProvider.overrideWith((ref) => ref.watch(identity)),
      ],
    );
    addTearDown(container.dispose);
    final subscription = container.listen(appNoticesProvider, (_, _) {});
    container
        .read(appNoticesProvider.notifier)
        .show(
          const AppNotice(
            key: 'a',
            title: 'Pago A',
            detail: '',
            important: true,
          ),
        );
    container.read(identity.notifier).state = ('customer-b', 'tenant-b');
    expect(container.read(appNoticesProvider), isEmpty);
    subscription.close();
  });
  testWidgets(
    'la ventana destaca el pago y permite cerrarlo sin perder la pantalla',
    (tester) async {
      final container = ProviderContainer(
        overrides: [
          identidadSesionProvider.overrideWith((ref) => ref.watch(identity)),
          notificationFeedProvider.overrideWith((ref) async => []),
        ],
      );
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            navigatorKey: appNavigatorKey,
            builder: (context, child) => NoticesHost(child: child!),
            home: const Scaffold(body: Text('Detalle del pedido')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      container
          .read(appNoticesProvider.notifier)
          .show(
            paymentNotice(
              id: 'o1',
              number: 'FS-001',
              amount: 150,
              currency: 'BOB',
              status: 'paid',
            ),
          );
      await tester.pump();
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('Pago confirmado'), findsOneWidget);
      expect(find.textContaining('FS-001 · 150.00 BOB'), findsOneWidget);
      await tester.tap(find.text('Entendido'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('Detalle del pedido'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      container.dispose();
    },
  );
}
