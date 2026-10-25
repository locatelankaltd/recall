import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:recall_next/billing/billing_service.dart';
import 'package:recall_next/billing/firebase_billing_server.dart';
import 'package:recall_next/cloud/recall_cloud.dart';

class BillingIdentity implements RecallApiIdentity {
  String? owner = 'firebase-owner-a';
  @override
  String? get userId => owner;
  @override
  Stream<String?> get userChanges => const Stream.empty();
  @override
  Future<String?> getIdToken() async => 'firebase-token-a';
}

void main() {
  test(
    'Firebase billing refresh reads canonical entitlement instead of trusting refresh response paid flags',
    () async {
      final identity = BillingIdentity();
      final paths = <String>[];
      final client = MockClient((request) async {
        paths.add(request.url.path);
        expect(request.headers['authorization'], 'Bearer firebase-token-a');
        if (request.url.path.endsWith('/refresh-entitlement')) {
          return http.Response(
            '{"active":true}',
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        expect(jsonDecode(request.body), {
          'name': 'recall_entitlement',
          'params': {},
        });
        return http.Response(
          jsonEncode({
            'data': {
              'entitlement': 'pro',
              'active': false,
              'status': 'unverified',
              'environment': 'unknown',
              'projectLimit': 100,
              'analysisDailyLimit': 20,
            },
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      addTearDown(client.close);
      final server = FirebaseBillingServer(
        RecallApiClient(
          endpoint: Uri.parse('https://recall.invalid/api'),
          identity: identity,
          httpClient: client,
        ),
      );
      final entitlement = await server.refresh();
      expect(paths, ['/api/refresh-entitlement', '/api/rpc']);
      expect(entitlement.active, isFalse);
      expect(entitlement.projectLimit, 3);
      expect(entitlement.analysisDailyLimit, 5);
    },
  );
  test(
    'verified Firebase entitlement responses cannot enter another account after a switch',
    () async {
      final identity = BillingIdentity();
      final client = MockClient((request) async {
        identity.owner = 'firebase-owner-b';
        return http.Response(
          '{"data":{"active":true}}',
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      addTearDown(client.close);
      final server = FirebaseBillingServer(
        RecallApiClient(
          endpoint: Uri.parse('https://recall.invalid/api'),
          identity: identity,
          httpClient: client,
        ),
      );
      await expectLater(
        server.read(),
        throwsA(
          isA<CloudException>().having(
            (error) => error.code,
            'code',
            'account_changed',
          ),
        ),
      );
    },
  );
  test(
    'unconfigured Firebase billing never reports a verified subscription',
    () async {
      const server = FirebaseBillingServer(null);
      await expectLater(
        server.read(),
        throwsA(
          isA<BillingFailure>().having(
            (error) => error.messageKey,
            'key',
            'subscriptionSignIn',
          ),
        ),
      );
      await expectLater(server.refresh(), throwsA(isA<BillingFailure>()));
    },
  );
}
