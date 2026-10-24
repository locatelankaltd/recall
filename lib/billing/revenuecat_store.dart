import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'billing_service.dart';

/// Purchases is process-global, so bind + store operations share one serial queue.
/// Account changes invalidate the caller immediately while an existing store sheet
/// finishes; its result is discarded before it can enter another account's UI.
class RevenueCatStore implements BillingStore {
  RevenueCatStore({
    this.androidKey = const String.fromEnvironment('REVENUECAT_ANDROID_KEY'),
    this.iosKey = const String.fromEnvironment('REVENUECAT_IOS_KEY'),
  });
  final String androidKey;
  final String iosKey;
  static Future<void> _queue = Future.value();
  static SupabaseClient? _observedClient;
  static StreamSubscription<AuthState>? _authSubscription;
  static String? _observedUid;

  static void observeSession(SupabaseClient client) {
    if (identical(client, _observedClient)) return;
    unawaited(_authSubscription?.cancel());
    _observedClient = client;
    _observedUid = client.auth.currentUser?.id;
    _authSubscription = client.auth.onAuthStateChange.listen((state) {
      final uid = state.session?.user.id;
      if (uid == _observedUid) return;
      _observedUid = uid;
      unawaited(RevenueCatStore().clearIdentity().catchError((_) {}));
    });
  }

  bool get _mobile =>
      !kIsWeb &&
      [
        TargetPlatform.android,
        TargetPlatform.iOS,
      ].contains(defaultTargetPlatform);
  String get _key =>
      defaultTargetPlatform == TargetPlatform.android ? androidKey : iosKey;
  @override
  bool get available =>
      _mobile &&
      _key.startsWith(
        defaultTargetPlatform == TargetPlatform.android ? 'goog_' : 'appl_',
      ) &&
      _key.length > 12 &&
      !RegExp(r'\s').hasMatch(_key);

  static Future<T> _serial<T>(Future<T> Function() operation) {
    final completer = Completer<T>();
    _queue = _queue.then((_) async {
      try {
        completer.complete(await operation());
      } catch (error, stack) {
        completer.completeError(error, stack);
      }
    });
    return completer.future;
  }

  Future<T> _forUser<T>(
    String ownerId,
    bool Function() isCurrent,
    Future<T> Function() operation,
  ) => _serial(() async {
    if (!available) throw const BillingFailure('subscriptionUnavailable');
    void check() {
      if (!isCurrent()) {
        throw const BillingFailure('subscriptionAccountChanged');
      }
    }

    check();
    try {
      if (!await Purchases.isConfigured) {
        check();
        await Purchases.setLogLevel(LogLevel.warn);
        check();
        await Purchases.configure(
          PurchasesConfiguration(_key)..appUserID = ownerId,
        );
      }
      check();
      if (await Purchases.appUserID != ownerId) {
        check();
        await Purchases.logIn(ownerId);
      }
      check();
      if (await Purchases.appUserID != ownerId) {
        throw const BillingFailure('subscriptionAccountChanged');
      }
      check();
      final result = await operation();
      check();
      if (await Purchases.appUserID != ownerId) {
        throw const BillingFailure('subscriptionAccountChanged');
      }
      check();
      return result;
    } on PlatformException catch (error) {
      PurchasesErrorCode code;
      try {
        code = PurchasesErrorHelper.getErrorCode(error);
      } catch (_) {
        code = PurchasesErrorCode.unknownError;
      }
      throw BillingFailure(switch (code) {
        PurchasesErrorCode.purchaseCancelledError => 'subscriptionCancelled',
        PurchasesErrorCode.paymentPendingError => 'subscriptionPending',
        PurchasesErrorCode.operationAlreadyInProgressError =>
          'subscriptionStoreBusy',
        _ => 'subscriptionError',
      });
    }
  });

  @override
  Future<BillingCatalog> load(String ownerId, bool Function() isCurrent) =>
      _forUser(ownerId, isCurrent, () async {
        final offerings = await Purchases.getOfferings();
        if (!isCurrent()) {
          throw const BillingFailure('subscriptionAccountChanged');
        }
        final info = await Purchases.getCustomerInfo();
        final packages =
            offerings.current?.availablePackages ?? const <Package>[];
        return BillingCatalog(
          plans: packages
              .where(
                (package) =>
                    package.storeProduct.productCategory ==
                        ProductCategory.subscription ||
                    package.storeProduct.subscriptionPeriod != null,
              )
              .map(
                (package) => BillingPlan(
                  id: package.identifier,
                  title: package.storeProduct.title,
                  description: package.storeProduct.description,
                  price: package.storeProduct.priceString,
                  period: package.storeProduct.subscriptionPeriod,
                  storePackage: package,
                ),
              )
              .toList(growable: false),
          receipt: StoreReceipt(
            managementUrl: safeManagementUrl(info.managementURL),
          ),
        );
      });

  @override
  Future<StoreReceipt> purchase(
    String ownerId,
    BillingPlan plan,
    bool Function() isCurrent,
  ) => _forUser(ownerId, isCurrent, () async {
    final package = plan.storePackage;
    if (package is! Package) {
      throw const BillingFailure('subscriptionNoPlans');
    }
    final result = await Purchases.purchase(PurchaseParams.package(package));
    return StoreReceipt(
      managementUrl: safeManagementUrl(result.customerInfo.managementURL),
    );
  });

  @override
  Future<StoreReceipt> restore(String ownerId, bool Function() isCurrent) =>
      _forUser(ownerId, isCurrent, () async {
        final result = await Purchases.restorePurchases();
        return StoreReceipt(
          managementUrl: safeManagementUrl(result.managementURL),
        );
      });

  @override
  Future<void> clearIdentity() => _serial(() async {
    if (!_mobile || !await Purchases.isConfigured) return;
    if (!await Purchases.isAnonymous) await Purchases.logOut();
  });

  static Uri? safeManagementUrl(String? value) {
    final uri = Uri.tryParse(value ?? '');
    if (uri != null &&
        uri.scheme == 'https' &&
        uri.userInfo.isEmpty &&
        (!uri.hasPort || uri.port == 443) &&
        !uri.hasFragment &&
        ((uri.host == 'apps.apple.com' &&
                uri.path == '/account/subscriptions') ||
            (uri.host == 'play.google.com' &&
                uri.path == '/store/account/subscriptions'))) {
      return uri;
    }
    if (kIsWeb) return null;
    return switch (defaultTargetPlatform) {
      TargetPlatform.android => Uri.https(
        'play.google.com',
        '/store/account/subscriptions',
      ),
      TargetPlatform.iOS => Uri.https(
        'apps.apple.com',
        '/account/subscriptions',
      ),
      _ => null,
    };
  }
}
