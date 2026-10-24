import 'dart:async';

import 'package:flutter/foundation.dart';

class BillingFailure implements Exception {
  const BillingFailure(this.messageKey);
  final String messageKey;
}

class VerifiedEntitlement {
  const VerifiedEntitlement({
    this.active = false,
    this.expiresAt,
    this.verifiedAt,
    this.environment = 'unknown',
    this.status = 'unverified',
    this.projectLimit = 3,
    this.analysisDailyLimit = 5,
  });
  final bool active;
  final DateTime? expiresAt;
  final DateTime? verifiedAt;
  final String environment;
  final String status;
  final int projectLimit;
  final int analysisDailyLimit;

  factory VerifiedEntitlement.fromJson(
    Map<String, dynamic> json, {
    DateTime Function()? clock,
  }) {
    final now = (clock ?? DateTime.now)();
    final verified = DateTime.tryParse(json['verifiedAt']?.toString() ?? '');
    final expires = DateTime.tryParse(json['expiresAt']?.toString() ?? '');
    final expiryValid = json['expiresAt'] == null || expires != null;
    final fresh =
        verified != null &&
        !verified.isAfter(now.add(const Duration(minutes: 5))) &&
        verified.isAfter(now.subtract(const Duration(hours: 24)));
    final environment = json['environment'] as String? ?? 'unknown';
    final status = json['status'] as String? ?? 'unverified';
    final active =
        json['entitlement'] == 'pro' &&
        json['active'] == true &&
        status == 'active' &&
        ['production', 'sandbox'].contains(environment) &&
        fresh &&
        expiryValid &&
        (expires == null || expires.isAfter(now));
    return VerifiedEntitlement(
      active: active,
      projectLimit: active && json['projectLimit'] == 100 ? 100 : 3,
      analysisDailyLimit: active && json['analysisDailyLimit'] == 20 ? 20 : 5,
      expiresAt: expires,
      verifiedAt: verified,
      environment: environment,
      status: status,
    );
  }
}

class BillingPlan {
  const BillingPlan({
    required this.id,
    required this.title,
    required this.description,
    required this.price,
    this.period,
    this.storePackage,
  });
  final String id;
  final String title;
  final String description;

  /// Localized currency string supplied by the store, never a calculated price.
  final String price;
  final String? period;
  final Object? storePackage;
}

class StoreReceipt {
  const StoreReceipt({this.managementUrl});
  final Uri? managementUrl;
  // Intentionally has no paid/active flag. SDK receipts cannot unlock Recall.
}

class BillingCatalog {
  const BillingCatalog({
    required this.plans,
    this.receipt = const StoreReceipt(),
  });
  final List<BillingPlan> plans;
  final StoreReceipt receipt;
}

abstract interface class BillingStore {
  bool get available;
  Future<BillingCatalog> load(String ownerId, bool Function() isCurrent);
  Future<StoreReceipt> purchase(
    String ownerId,
    BillingPlan plan,
    bool Function() isCurrent,
  );
  Future<StoreReceipt> restore(String ownerId, bool Function() isCurrent);
  Future<void> clearIdentity();
}

abstract interface class BillingServer {
  Future<VerifiedEntitlement> read();
  Future<VerifiedEntitlement> refresh();
}

/// Every response is bound to both the operation generation and current Auth UID.
/// No receipt, price or paid state is retained across account transitions.
class BillingController extends ChangeNotifier {
  BillingController({
    required this.store,
    required this.server,
    required this.currentUserId,
  });
  final BillingStore store;
  final BillingServer server;
  final String? Function() currentUserId;
  bool _disposed = false;
  int _generation = 0;
  String? ownerId;
  bool busy = false;
  bool serverConnected = false;
  bool verificationPending = false;
  bool accountChanged = false;
  String? messageKey;
  List<BillingPlan> plans = const [];
  StoreReceipt receipt = const StoreReceipt();
  VerifiedEntitlement entitlement = const VerifiedEntitlement();
  bool get storeAvailable => store.available;
  bool get signedIn => currentUserId() != null;
  Uri? get managementUrl => !accountChanged && ownerId == currentUserId()
      ? receipt.managementUrl
      : null;
  bool get canPurchase =>
      !busy &&
      !accountChanged &&
      signedIn &&
      storeAvailable &&
      serverConnected &&
      !verificationPending &&
      !entitlement.active;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  bool _current(String uid, int generation) =>
      !_disposed &&
      generation == _generation &&
      currentUserId() == uid &&
      ownerId == uid;

  void _check(String uid, int generation) {
    if (!_current(uid, generation)) {
      throw const BillingFailure('subscriptionAccountChanged');
    }
  }

  Future<void> _run(
    Future<void> Function(String uid, int generation) action,
  ) async {
    if (busy || _disposed) return;
    final uid = currentUserId();
    if (uid == null) {
      messageKey = 'subscriptionSignIn';
      _notify();
      return;
    }
    ownerId = uid;
    final generation = ++_generation;
    busy = true;
    messageKey = null;
    _notify();
    try {
      await action(uid, generation);
    } on BillingFailure catch (error) {
      if (_current(uid, generation)) {
        messageKey = error.messageKey;
        if (error.messageKey == 'subscriptionPending') {
          verificationPending = true;
        }
      }
    } catch (_) {
      if (_current(uid, generation)) messageKey = 'subscriptionError';
    } finally {
      if (_current(uid, generation)) {
        busy = false;
        _notify();
      } else if (!_disposed &&
          generation == _generation &&
          currentUserId() != uid) {
        sessionChanged();
      }
    }
  }

  Future<void> initialize() => _run((uid, generation) async {
    accountChanged = false;
    plans = const [];
    receipt = const StoreReceipt();
    entitlement = const VerifiedEntitlement();
    serverConnected = false;
    try {
      final verified = await server.read();
      _check(uid, generation);
      entitlement = verified;
      serverConnected = true;
    } catch (_) {
      _check(uid, generation);
      messageKey = 'subscriptionUnverified';
    }
    if (!storeAvailable) {
      messageKey = 'subscriptionUnavailable';
      return;
    }
    final catalog = await store.load(uid, () => _current(uid, generation));
    _check(uid, generation);
    plans = List.unmodifiable(catalog.plans);
    receipt = catalog.receipt;
    if (plans.isEmpty && messageKey == null) messageKey = 'subscriptionNoPlans';
  });

  Future<void> verify() => _run((uid, generation) async {
    try {
      final verified = await server.refresh();
      _check(uid, generation);
      entitlement = verified;
      serverConnected = true;
      verificationPending = false;
    } catch (_) {
      _check(uid, generation);
      serverConnected = false;
      messageKey = 'subscriptionVerifyFailed';
    }
  });

  Future<void> purchase(BillingPlan plan) async {
    if (!canPurchase || !plans.contains(plan)) return;
    await _run((uid, generation) async {
      // Verify server configuration and existing status before opening payment.
      try {
        final verified = await server.refresh();
        _check(uid, generation);
        entitlement = verified;
        serverConnected = true;
      } catch (_) {
        _check(uid, generation);
        serverConnected = false;
        throw const BillingFailure('subscriptionUnverified');
      }
      if (entitlement.active) return;
      final result = await store.purchase(
        uid,
        plan,
        () => _current(uid, generation),
      );
      _check(uid, generation);
      receipt = result;
      verificationPending = true;
      await _verifyAfterStore(uid, generation);
    });
  }

  Future<void> restore() => _run((uid, generation) async {
    if (!storeAvailable || accountChanged) {
      throw const BillingFailure('subscriptionUnavailable');
    }
    final result = await store.restore(uid, () => _current(uid, generation));
    _check(uid, generation);
    receipt = result;
    verificationPending = true;
    await _verifyAfterStore(uid, generation);
  });

  Future<void> _verifyAfterStore(String uid, int generation) async {
    try {
      final verified = await server.refresh();
      _check(uid, generation);
      entitlement = verified;
      serverConnected = true;
      verificationPending = !verified.active;
      if (!verified.active) messageKey = 'subscriptionVerifyFailed';
    } catch (_) {
      _check(uid, generation);
      entitlement = const VerifiedEntitlement();
      serverConnected = false;
      messageKey = 'subscriptionVerifyFailed';
    }
  }

  void sessionChanged() {
    if (_disposed) return;
    _generation++;
    busy = false;
    ownerId = null;
    plans = const [];
    receipt = const StoreReceipt();
    entitlement = const VerifiedEntitlement();
    serverConnected = false;
    verificationPending = false;
    accountChanged = true;
    messageKey = 'subscriptionAccountChanged';
    _notify();
    unawaited(store.clearIdentity().catchError((_) {}));
  }

  @override
  void dispose() {
    _generation++;
    _disposed = true;
    plans = const [];
    receipt = const StoreReceipt();
    entitlement = const VerifiedEntitlement();
    super.dispose();
  }
}
