import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:recall_next/billing/billing_service.dart';
import 'package:recall_next/billing/revenuecat_store.dart';

const owner = '11111111-1111-1111-1111-111111111111';
const channel = MethodChannel('purchases_flutter');
Map<String, dynamic> customer() => {
  'entitlements': {'all': {}, 'active': {}, 'verification': 'NOT_REQUESTED'},
  'allPurchaseDates': <String, String>{},
  'activeSubscriptions': <String>[],
  'allPurchasedProductIdentifiers': <String>[],
  'nonSubscriptionTransactions': [],
  'firstSeen': '2026-10-24T12:00:00Z',
  'originalAppUserId': owner,
  'allExpirationDates': <String, String>{},
  'requestDate': '2026-10-24T12:00:00Z',
  'managementURL': 'https://play.google.com/store/account/subscriptions',
};
BillingPlan plan() => const BillingPlan(
  id: 'monthly',
  title: 'Store plan',
  description: 'Subscription',
  price: '€8,49',
  storePackage: Package(
    'monthly',
    PackageType.monthly,
    StoreProduct(
      'store-monthly',
      'Subscription',
      'Store plan',
      8.49,
      '€8,49',
      'EUR',
      productCategory: ProductCategory.subscription,
      subscriptionPeriod: 'P1M',
    ),
    PresentedOfferingContext('default', null, null),
  ),
);
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final calls = <MethodCall>[];
  late bool configured;
  late String sdkUid;
  Completer<dynamic>? loginWait;
  PlatformException? storeFailure;
  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    configured = true;
    sdkUid = 'old-owner';
    calls.clear();
    loginWait = null;
    storeFailure = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          switch (call.method) {
            case 'isConfigured':
              return configured;
            case 'getAppUserID':
              return sdkUid;
            case 'setLogLevel':
              return null;
            case 'setupPurchases':
              configured = true;
              sdkUid = (call.arguments as Map)['appUserId'] as String;
              return null;
            case 'logIn':
              if (loginWait != null) return loginWait!.future;
              sdkUid = (call.arguments as Map)['appUserID'] as String;
              return {'customerInfo': customer(), 'created': false};
            case 'purchasePackage':
              if (storeFailure != null) throw storeFailure!;
              return {
                'customerInfo': customer(),
                'transaction': {
                  'productIdentifier': 'store-monthly',
                  'purchaseDate': '2026-10-24T12:00:00Z',
                  'transactionIdentifier': 'mock-only',
                },
              };
            case 'restorePurchases':
              return customer();
            case 'getCustomerInfo':
              return customer();
            case 'getOfferings':
              return {'all': {}, 'current': null};
            case 'isAnonymous':
              return sdkUid.startsWith(r'$RCAnonymousID:');
            case 'logOut':
              sdkUid = r'$RCAnonymousID:mock';
              return customer();
            default:
              throw StateError('Unexpected native method ${call.method}');
          }
        });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    debugDefaultTargetPlatformOverride = null;
  });
  test(
    'native purchase waits for login and binds the Supabase UUID first',
    () async {
      loginWait = Completer<dynamic>();
      final store = RevenueCatStore(androidKey: 'goog_mock_public_key');
      final pending = store.purchase(owner, plan(), () => true);
      await Future<void>.delayed(Duration.zero);
      expect(calls.any((call) => call.method == 'logIn'), true);
      expect(calls.any((call) => call.method == 'purchasePackage'), false);
      sdkUid = owner;
      loginWait!.complete({'customerInfo': customer(), 'created': false});
      final receipt = await pending;
      expect(calls.where((call) => call.method == 'purchasePackage').length, 1);
      expect(receipt.managementUrl!.host, 'play.google.com');
    },
  );
  test(
    'identity invalidated during native login prevents the store transaction',
    () async {
      loginWait = Completer<dynamic>();
      var current = true;
      final store = RevenueCatStore(androidKey: 'goog_mock_public_key');
      final pending = store.purchase(owner, plan(), () => current);
      await Future<void>.delayed(Duration.zero);
      current = false;
      sdkUid = owner;
      loginWait!.complete({'customerInfo': customer(), 'created': false});
      await expectLater(
        pending,
        throwsA(
          isA<BillingFailure>().having(
            (error) => error.messageKey,
            'message',
            'subscriptionAccountChanged',
          ),
        ),
      );
      expect(calls.any((call) => call.method == 'purchasePackage'), false);
    },
  );
  test(
    'initial SDK configuration sets owner before fetching offerings',
    () async {
      configured = false;
      final store = RevenueCatStore(androidKey: 'goog_mock_public_key');
      final catalog = await store.load(owner, () => true);
      final setup = calls.indexWhere((call) => call.method == 'setupPurchases');
      final offerings = calls.indexWhere(
        (call) => call.method == 'getOfferings',
      );
      expect(setup, greaterThanOrEqualTo(0));
      expect(offerings, greaterThan(setup));
      expect((calls[setup].arguments as Map)['appUserId'], owner);
      expect(catalog.plans, isEmpty);
      expect(calls.any((call) => call.method == 'purchasePackage'), false);
    },
  );
  test(
    'native cancellation and pending errors map to different safe messages',
    () async {
      sdkUid = owner;
      final store = RevenueCatStore(androidKey: 'goog_mock_public_key');
      for (final code in [
        PurchasesErrorCode.purchaseCancelledError,
        PurchasesErrorCode.paymentPendingError,
      ]) {
        storeFailure = PlatformException(
          code: code.index.toString(),
          message: 'private store detail',
        );
        await expectLater(
          store.purchase(owner, plan(), () => true),
          throwsA(
            isA<BillingFailure>().having(
              (error) => error.messageKey,
              'message',
              code == PurchasesErrorCode.purchaseCancelledError
                  ? 'subscriptionCancelled'
                  : 'subscriptionPending',
            ),
          ),
        );
      }
    },
  );
  test(
    'sign-out clears native SDK identity after any queued operation',
    () async {
      sdkUid = owner;
      final store = RevenueCatStore(androidKey: 'goog_mock_public_key');
      await store.clearIdentity();
      expect(calls.any((call) => call.method == 'logOut'), true);
      expect(sdkUid.startsWith(r'$RCAnonymousID:'), true);
    },
  );
  test('only safe HTTPS store management destinations can be opened', () {
    for (final candidate in [
      'https://evil.invalid',
      'javascript:alert(1)',
      'https://play.google.com.evil.invalid/store/account/subscriptions',
      'https://user:password@play.google.com/store/account/subscriptions',
      'http://apps.apple.com/account/subscriptions',
      'https://apps.apple.com/account/subscriptions#redirect',
    ]) {
      final safe = RevenueCatStore.safeManagementUrl(candidate);
      expect(safe?.host, 'play.google.com');
      expect(safe?.scheme, 'https');
      expect(safe?.userInfo, isEmpty);
    }
    expect(
      RevenueCatStore.safeManagementUrl(
        'https://apps.apple.com/account/subscriptions',
      )?.host,
      'apps.apple.com',
    );
  });
}
