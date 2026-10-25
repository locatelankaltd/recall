import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:recall_next/cloud/recall_cloud.dart';

class TestApiIdentity implements RecallApiIdentity {
  TestApiIdentity({this.owner = 'account-a'});
  String? owner;
  int ownerReads = 0;
  int tokenReads = 0;
  Future<String?> Function()? token;
  @override
  String? get userId {
    ownerReads++;
    return owner;
  }

  @override
  Stream<String?> get userChanges => const Stream.empty();
  @override
  Future<String?> getIdToken() async {
    tokenReads++;
    return token == null ? 'test-token-a' : await token!();
  }
}

RecallApiClient api(TestApiIdentity identity, http.Client client) =>
    RecallApiClient(
      endpoint: Uri.parse('https://recall.invalid/api'),
      identity: identity,
      httpClient: client,
    );
http.Response jsonResponse(
  http.Request request,
  Object body, {
  int status = 200,
}) => http.Response(
  jsonEncode(body),
  status,
  request: request,
  headers: {'content-type': 'application/json'},
);

void main() {
  test(
    'RPC uses frozen Firebase path/envelope and a captured user ID token',
    () async {
      final identity = TestApiIdentity();
      final client = MockClient((request) async {
        expect(request.url.toString(), 'https://recall.invalid/api/rpc');
        expect(request.headers['authorization'], 'Bearer test-token-a');
        expect(request.headers.containsKey('apikey'), isFalse);
        expect(jsonDecode(request.body), {
          'name': 'recall_list_projects',
          'params': {},
        });
        return jsonResponse(request, {'data': []});
      });
      addTearDown(client.close);
      expect(
        await api(identity, client).rpc('recall_list_projects', {}),
        isEmpty,
      );
      expect(identity.tokenReads, 1);
    },
  );
  test(
    'account change while obtaining a token prevents the private request',
    () async {
      final identity = TestApiIdentity();
      final token = Completer<String?>();
      identity.token = () => token.future;
      var calls = 0;
      final client = MockClient((request) async {
        calls++;
        return jsonResponse(request, {'data': []});
      });
      addTearDown(client.close);
      final pending = api(
        identity,
        client,
      ).rpc('recall_create_project', {'p_title': 'A private title'});
      final rejected = expectLater(
        pending,
        throwsA(
          isA<CloudException>().having(
            (e) => e.code,
            'code',
            'account_changed',
          ),
        ),
      );
      identity.owner = 'account-b';
      token.complete('test-token-a');
      await rejected;
      expect(calls, 0);
    },
  );
  test(
    'failed Firebase token refresh blocks a private request without leaking SDK details',
    () async {
      final identity = TestApiIdentity()
        ..token = () async => throw StateError('Private authentication detail');
      var calls = 0;
      final client = MockClient((request) async {
        calls++;
        return jsonResponse(request, {'data': []});
      });
      addTearDown(client.close);
      await expectLater(
        api(identity, client).rpc('recall_list_projects', {}),
        throwsA(
          isA<CloudException>()
              .having((e) => e.code, 'code', '28000')
              .having(
                (e) => e.message,
                'message',
                isNot(contains('Private authentication')),
              ),
        ),
      );
      expect(calls, 0);
    },
  );
  test(
    'cancelling source analysis during token refresh never sends a late paid request',
    () async {
      final identity = TestApiIdentity();
      final token = Completer<String?>();
      final abort = Completer<void>();
      identity.token = () => token.future;
      var calls = 0;
      final client = MockClient((request) async {
        calls++;
        return jsonResponse(request, {'status': 'review_required'});
      });
      addTearDown(client.close);
      final pending = api(identity, client).invoke(
        'analyze-source',
        body: {'consent': true, 'source_text': 'chosen source'},
        abortSignal: abort.future,
      );
      final rejected = expectLater(pending, throwsA(isA<TimeoutException>()));
      abort.complete();
      await rejected;
      token.complete('late-token-a');
      await Future<void>.delayed(Duration.zero);
      expect(calls, 0);
    },
  );
  test(
    'in-flight request stays under its clicked account and discards a later response after switching',
    () async {
      final identity = TestApiIdentity();
      final entered = Completer<void>();
      final release = Completer<void>();
      final client = MockClient((request) async {
        expect(request.headers['authorization'], 'Bearer test-token-a');
        entered.complete();
        await release.future;
        return jsonResponse(request, {'data': []});
      });
      addTearDown(client.close);
      final pending = api(
        identity,
        client,
      ).rpc('recall_create_project', {'p_title': 'A private title'});
      final rejected = expectLater(
        pending,
        throwsA(
          isA<CloudException>().having(
            (e) => e.code,
            'code',
            'account_changed',
          ),
        ),
      );
      await entered.future;
      identity.owner = 'account-b';
      release.complete();
      await rejected;
      expect(identity.tokenReads, 1);
    },
  );
  test(
    'public review read and response bypass expired owner tokens and Authorization',
    () async {
      final identity = TestApiIdentity();
      identity.token = () async =>
          throw StateError('Expired token refresh must not be called');
      final methods = <String>[];
      final client = MockClient((request) async {
        expect(request.headers.containsKey('authorization'), isFalse);
        expect(request.headers.containsKey('apikey'), isFalse);
        final body = jsonDecode(request.body) as Map;
        methods.add(body['name'] as String);
        identity.owner = 'account-b';
        return jsonResponse(request, {
          'data': {'receiptId': 'test-receipt'},
        });
      });
      addTearDown(client.close);
      final value = api(identity, client);
      await value.rpc('recall_review_link', {
        'p_token': 'private-review-token',
      });
      await value.rpc('recall_respond_review', {
        'p_token': 'private-review-token',
        'p_action': 'confirm',
        'p_request_id': 'request-1',
      });
      expect(methods, ['recall_review_link', 'recall_respond_review']);
      expect(identity.tokenReads, 0);
      expect(identity.ownerReads, 0);
    },
  );
  test(
    'Firebase API errors expose safe messages and preserve CAS error codes',
    () async {
      final client = MockClient(
        (request) async => jsonResponse(request, {
          'code': '40001',
          'message': 'Private internal database detail',
        }, status: 409),
      );
      addTearDown(client.close);
      await expectLater(
        api(TestApiIdentity(), client).rpc('recall_mutate_project', {}),
        throwsA(
          isA<RecallApiException>()
              .having((e) => e.code, 'code', '40001')
              .having((e) => e.status, 'status', 409)
              .having(
                (e) => e.message,
                'message',
                isNot(contains('Private internal')),
              ),
        ),
      );
    },
  );
  test(
    'JSON service calls preserve raw bodies outside the RPC envelope',
    () async {
      final client = MockClient((request) async {
        expect(request.url.path, '/api/analyze-source');
        expect(jsonDecode(request.body), {
          'consent': true,
          'source_text': 'chosen source',
        });
        return jsonResponse(request, {'status': 'review_required'});
      });
      addTearDown(client.close);
      final result = await api(TestApiIdentity(), client).invoke(
        'analyze-source',
        body: {'consent': true, 'source_text': 'chosen source'},
      );
      expect(result['status'], 'review_required');
    },
  );
  test(
    'multipart transcription sends consent and audio to the same authenticated Firebase endpoint',
    () async {
      final client = MockClient((request) async {
        expect(request.url.path, '/api/transcribe-recording');
        expect(request.headers['authorization'], 'Bearer test-token-a');
        expect(
          request.headers['content-type'],
          startsWith('multipart/form-data;'),
        );
        expect(request.body, contains('name="consent"'));
        expect(request.body, contains('name="audio"'));
        expect(request.body, contains('filename="recording.m4a"'));
        return jsonResponse(request, {
          'status': 'review_required',
          'text': 'draft',
        });
      });
      addTearDown(client.close);
      await api(TestApiIdentity(), client).invoke(
        'transcribe-recording',
        body: {'consent': 'true'},
        files: [
          http.MultipartFile.fromBytes('audio', [
            1,
            2,
            3,
          ], filename: 'recording.m4a'),
        ],
      );
    },
  );
}
