import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:recall_next/billing/billing_service.dart';
import 'package:recall_next/design/recall_theme.dart';
import 'package:recall_next/ui/subscription_page.dart';

class UnavailableStore implements BillingStore {
  @override
  bool get available => false;
  @override
  Future<void> clearIdentity() async {}
  @override
  Future<BillingCatalog> load(
    String ownerId,
    bool Function() isCurrent,
  ) async => const BillingCatalog(plans: []);
  @override
  Future<StoreReceipt> purchase(
    String ownerId,
    BillingPlan plan,
    bool Function() isCurrent,
  ) async => throw StateError('No store purchase expected');
  @override
  Future<StoreReceipt> restore(
    String ownerId,
    bool Function() isCurrent,
  ) async => throw StateError('No restore expected');
}

class Server implements BillingServer {
  @override
  Future<VerifiedEntitlement> read() async => const VerifiedEntitlement();
  @override
  Future<VerifiedEntitlement> refresh() async => const VerifiedEntitlement();
}

void main() {
  testWidgets('unconfigured device offers no fake plan or purchase button', (
    tester,
  ) async {
    final controller = BillingController(
      store: UnavailableStore(),
      server: Server(),
      currentUserId: () => '11111111-1111-1111-1111-111111111111',
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: RecallTheme.light,
        home: SubscriptionPage(controller: controller),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Continue with this plan'), findsNothing);
    expect(find.text('Restore purchases'), findsNothing);
    expect(
      find.text(
        'Store subscriptions are unavailable on this device or are not configured.',
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });
  testWidgets(
    'signed-out subscription page asks for an account without opening payment',
    (tester) async {
      final controller = BillingController(
        store: UnavailableStore(),
        server: Server(),
        currentUserId: () => null,
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: RecallTheme.light,
          home: SubscriptionPage(controller: controller),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Sign in to view your subscription.'), findsOneWidget);
      expect(find.text('Continue with this plan'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
  );
}
