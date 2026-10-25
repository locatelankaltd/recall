import '../cloud/recall_api.dart';
import 'billing_service.dart';

class FirebaseBillingServer implements BillingServer {
  const FirebaseBillingServer(this.client);
  final RecallApiClient? client;
  RecallApiClient _authenticated() {
    final value = client;
    if (value == null || value.userId == null) {
      throw const BillingFailure('subscriptionSignIn');
    }
    return value;
  }

  @override
  Future<VerifiedEntitlement> read() async {
    final value = _authenticated();
    final owner = value.userId;
    final data = await value.rpc('recall_entitlement', {});
    if (value.userId != owner) {
      throw const BillingFailure('subscriptionAccountChanged');
    }
    return VerifiedEntitlement.fromJson(Map<String, dynamic>.from(data as Map));
  }

  @override
  Future<VerifiedEntitlement> refresh() async {
    final value = _authenticated();
    final owner = value.userId;
    await value.invoke('refresh-entitlement');
    if (value.userId != owner) {
      throw const BillingFailure('subscriptionAccountChanged');
    }
    // Purchase SDK state cannot unlock Recall; read canonical verified state.
    return read();
  }
}
