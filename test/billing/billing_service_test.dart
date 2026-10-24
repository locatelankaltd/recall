import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:recall_next/billing/billing_service.dart';

const owner = '11111111-1111-1111-1111-111111111111';
const other = '22222222-2222-2222-2222-222222222222';
const plan = BillingPlan(
  id: 'monthly',
  title: 'Store plan',
  description: 'Store description',
  price: '€8,49',
  period: 'P1M',
);
const active = VerifiedEntitlement(
  active: true,
  status: 'active',
  environment: 'production',
);

class FakeStore implements BillingStore {
  @override
  bool available = true;
  final calls = <String>[];
  Completer<BillingCatalog>? loadWait;
  Completer<StoreReceipt>? purchaseWait;
  BillingFailure? purchaseFailure;
  @override
  Future<BillingCatalog> load(String uid, bool Function() isCurrent) async {
    calls.add('load:$uid');
    return loadWait?.future ?? const BillingCatalog(plans: [plan]);
  }

  @override
  Future<StoreReceipt> purchase(
    String uid,
    BillingPlan plan,
    bool Function() isCurrent,
  ) async {
    calls.add('purchase:$uid');
    if (purchaseFailure != null) throw purchaseFailure!;
    return purchaseWait?.future ??
        StoreReceipt(
          managementUrl: Uri.https('apps.apple.com', '/account/subscriptions'),
        );
  }

  @override
  Future<StoreReceipt> restore(String uid, bool Function() isCurrent) async {
    calls.add('restore:$uid');
    return StoreReceipt(
      managementUrl: Uri.https('apps.apple.com', '/account/subscriptions'),
    );
  }

  @override
  Future<void> clearIdentity() async {
    calls.add('clear');
  }
}

class FakeServer implements BillingServer {
  final calls = <String>[];
  VerifiedEntitlement value = const VerifiedEntitlement();
  Completer<VerifiedEntitlement>? refreshWait;
  List<VerifiedEntitlement> refreshResults = [];
  bool failRefresh = false;
  @override
  Future<VerifiedEntitlement> read() async {
    calls.add('read');
    return value;
  }

  @override
  Future<VerifiedEntitlement> refresh() async {
    calls.add('refresh');
    if (failRefresh) throw Exception('private server detail');
    if (refreshResults.isNotEmpty) return refreshResults.removeAt(0);
    return refreshWait?.future ?? value;
  }
}

void main() {
  test(
    'unconfigured stores stay unavailable while free workspace remains usable',
    () async {
      final store = FakeStore()..available = false;
      final controller = BillingController(
        store: store,
        server: FakeServer(),
        currentUserId: () => owner,
      );
      await controller.initialize();
      expect(controller.canPurchase, false);
      expect(controller.plans, isEmpty);
      expect(store.calls, isEmpty);
      expect(controller.messageKey, 'subscriptionUnavailable');
      controller.dispose();
    },
  );
  test('signed-out subscriptions do no store or server work', () async {
    final store = FakeStore();
    final server = FakeServer();
    final controller = BillingController(
      store: store,
      server: server,
      currentUserId: () => null,
    );
    await controller.initialize();
    await controller.restore();
    expect(store.calls, isEmpty);
    expect(server.calls, isEmpty);
    expect(controller.entitlement.active, false);
    controller.dispose();
  });
  test(
    'SDK receipt alone cannot unlock Pro if server remains inactive',
    () async {
      final store = FakeStore();
      final server = FakeServer();
      final controller = BillingController(
        store: store,
        server: server,
        currentUserId: () => owner,
      );
      await controller.initialize();
      await controller.purchase(plan);
      expect(store.calls, ['load:$owner', 'purchase:$owner']);
      expect(controller.entitlement.active, false);
      expect(controller.verificationPending, true);
      expect(controller.canPurchase, false);
      expect(controller.messageKey, 'subscriptionVerifyFailed');
      controller.dispose();
    },
  );
  test(
    'only a server verification after actual purchase unlocks paid state',
    () async {
      final store = FakeStore();
      final server = FakeServer()
        ..refreshResults = [const VerifiedEntitlement(), active];
      final controller = BillingController(
        store: store,
        server: server,
        currentUserId: () => owner,
      );
      await controller.initialize();
      await controller.purchase(plan);
      expect(server.calls, ['read', 'refresh', 'refresh']);
      expect(controller.entitlement.active, true);
      expect(controller.canPurchase, false);
      controller.dispose();
    },
  );
  test(
    'server unavailable before payment prevents the store purchase call',
    () async {
      final store = FakeStore();
      final server = FakeServer()..failRefresh = true;
      final controller = BillingController(
        store: store,
        server: server,
        currentUserId: () => owner,
      );
      await controller.initialize();
      await controller.purchase(plan);
      expect(store.calls, ['load:$owner']);
      expect(controller.messageKey, 'subscriptionUnverified');
      controller.dispose();
    },
  );
  test(
    'cancelled and pending payments have distinct states without unlock',
    () async {
      for (final key in ['subscriptionCancelled', 'subscriptionPending']) {
        final store = FakeStore()..purchaseFailure = BillingFailure(key);
        final controller = BillingController(
          store: store,
          server: FakeServer(),
          currentUserId: () => owner,
        );
        await controller.initialize();
        await controller.purchase(plan);
        expect(controller.messageKey, key);
        expect(controller.entitlement.active, false);
        expect(controller.canPurchase, key == 'subscriptionCancelled');
        controller.dispose();
      }
    },
  );
  test('restore still requires verified server status', () async {
    final store = FakeStore();
    final server = FakeServer()..value = active;
    final controller = BillingController(
      store: store,
      server: server,
      currentUserId: () => owner,
    );
    await controller.initialize();
    await controller.restore();
    expect(store.calls, ['load:$owner', 'restore:$owner']);
    expect(server.calls, ['read', 'refresh']);
    expect(controller.entitlement.active, true);
    controller.dispose();
  });
  test(
    'account change discards an in-flight store receipt and clears prices',
    () async {
      String? uid = owner;
      final wait = Completer<StoreReceipt>();
      final store = FakeStore()..purchaseWait = wait;
      final controller = BillingController(
        store: store,
        server: FakeServer(),
        currentUserId: () => uid,
      );
      await controller.initialize();
      final pending = controller.purchase(plan);
      await Future<void>.delayed(Duration.zero);
      uid = other;
      controller.sessionChanged();
      wait.complete(
        StoreReceipt(
          managementUrl: Uri.https('apps.apple.com', '/account/subscriptions'),
        ),
      );
      await pending;
      expect(controller.entitlement.active, false);
      expect(controller.receipt.managementUrl, isNull);
      expect(controller.plans, isEmpty);
      expect(controller.accountChanged, true);
      expect(store.calls.last, 'clear');
      controller.dispose();
    },
  );
  test(
    'account change during server precheck prevents payment and discards paid response',
    () async {
      String? uid = owner;
      final wait = Completer<VerifiedEntitlement>();
      final store = FakeStore();
      final server = FakeServer()..refreshWait = wait;
      final controller = BillingController(
        store: store,
        server: server,
        currentUserId: () => uid,
      );
      await controller.initialize();
      final pending = controller.purchase(plan);
      await Future<void>.delayed(Duration.zero);
      uid = other;
      controller.sessionChanged();
      wait.complete(active);
      await pending;
      expect(controller.entitlement.active, false);
      expect(store.calls.where((call) => call.startsWith('purchase')), isEmpty);
      controller.dispose();
    },
  );
  test(
    'UID guard clears stale response even without a delivered auth event',
    () async {
      String? uid = owner;
      final wait = Completer<VerifiedEntitlement>();
      final server = FakeServer()..refreshWait = wait;
      final controller = BillingController(
        store: FakeStore(),
        server: server,
        currentUserId: () => uid,
      );
      await controller.initialize();
      final pending = controller.verify();
      uid = other;
      wait.complete(active);
      await pending;
      expect(controller.entitlement.active, false);
      expect(controller.accountChanged, true);
      expect(controller.busy, false);
      controller.dispose();
    },
  );
  test('duplicate taps serialize to one store transaction', () async {
    final wait = Completer<StoreReceipt>();
    final store = FakeStore()..purchaseWait = wait;
    final controller = BillingController(
      store: store,
      server: FakeServer(),
      currentUserId: () => owner,
    );
    await controller.initialize();
    final pending = controller.purchase(plan);
    await Future<void>.delayed(Duration.zero);
    await controller.purchase(plan);
    expect(store.calls.where((call) => call.startsWith('purchase')).length, 1);
    wait.complete(const StoreReceipt());
    await pending;
    controller.dispose();
  });
  test(
    'late disposed responses do not notify or retain another owner receipt',
    () async {
      final wait = Completer<BillingCatalog>();
      final store = FakeStore()..loadWait = wait;
      final controller = BillingController(
        store: store,
        server: FakeServer(),
        currentUserId: () => owner,
      );
      final pending = controller.initialize();
      await Future<void>.delayed(Duration.zero);
      controller.dispose();
      wait.complete(const BillingCatalog(plans: [plan]));
      await pending;
      expect(controller.plans, isEmpty);
      expect(controller.entitlement.active, false);
    },
  );
  test(
    'verified JSON refuses SDK-shaped, stale, expired or malformed unlocks',
    () {
      final now = DateTime.utc(2026, 10, 24, 12);
      final good = {
        'entitlement': 'pro',
        'active': true,
        'status': 'active',
        'environment': 'production',
        'projectLimit': 100,
        'analysisDailyLimit': 20,
        'verifiedAt': now.toIso8601String(),
        'expiresAt': now.add(const Duration(days: 1)).toIso8601String(),
      };
      expect(VerifiedEntitlement.fromJson(good, clock: () => now).active, true);
      expect(
        VerifiedEntitlement.fromJson(good, clock: () => now).projectLimit,
        100,
      );
      expect(
        VerifiedEntitlement.fromJson(good, clock: () => now).analysisDailyLimit,
        20,
      );
      for (final change in [
        <String, dynamic>{'verifiedAt': null},
        {'verifiedAt': now.subtract(const Duration(days: 2)).toIso8601String()},
        {'expiresAt': 'invalid'},
        {
          'expiresAt': now
              .subtract(const Duration(seconds: 1))
              .toIso8601String(),
        },
        {'environment': 'unknown'},
        {'status': 'unverified'},
        {'entitlement': 'different'},
      ]) {
        expect(
          VerifiedEntitlement.fromJson({
            ...good,
            ...change,
          }, clock: () => now).active,
          false,
        );
      }
    },
  );
}
