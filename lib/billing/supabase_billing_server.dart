import 'package:supabase_flutter/supabase_flutter.dart';

import 'billing_service.dart';

class SupabaseBillingServer implements BillingServer {
  const SupabaseBillingServer(this.client);
  final SupabaseClient? client;

  SupabaseClient _authenticated() {
    final value = client;
    if (value == null || value.auth.currentUser == null) {
      throw const BillingFailure('subscriptionSignIn');
    }
    return value;
  }

  @override
  Future<VerifiedEntitlement> read() async {
    final value = _authenticated();
    final owner = value.auth.currentUser!.id;
    final data = await value.rpc('recall_entitlement');
    if (value.auth.currentUser?.id != owner) {
      throw const BillingFailure('subscriptionAccountChanged');
    }
    return VerifiedEntitlement.fromJson(Map<String, dynamic>.from(data as Map));
  }

  @override
  Future<VerifiedEntitlement> refresh() async {
    final value = _authenticated();
    final owner = value.auth.currentUser!.id;
    final result = await value.functions.invoke('refresh-entitlement');
    if (value.auth.currentUser?.id != owner) {
      throw const BillingFailure('subscriptionAccountChanged');
    }
    if (result.status != 200) {
      throw const BillingFailure('subscriptionVerifyFailed');
    }
    // A successful SDK response or Edge response alone never unlocks anything.
    // Read the owner-scoped verified database state after reconciliation.
    return read();
  }
}
