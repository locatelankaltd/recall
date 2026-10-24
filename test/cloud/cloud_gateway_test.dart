import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:recall_next/cloud/cloud_gateway.dart';
import 'package:recall_next/domain/agreement_engine.dart';

class FakeTransport implements CloudRpcTransport {
  final calls = <({String function, Map<String, dynamic> params})>[];
  Future<dynamic> Function(String, Map<String, dynamic>)? handle;
  @override
  Future<dynamic> rpc(String function, Map<String, dynamic> params) async {
    calls.add((function: function, params: Map.of(params)));
    return await handle!(function, params);
  }
}

void main() {
  final project = AgreementEngine().createProject(
    title: 'Website',
    clientName: 'Sam',
  );
  Map<String, dynamic> envelope(int version) => {
    'project': project.toJson(),
    'version': version,
  };

  test(
    'mutations send the last canonical server version and only update from server',
    () async {
      final transport = FakeTransport();
      final gateway = RpcCloudProjectGateway(
        transport: transport,
        currentUserId: () => 'account-a',
      );
      transport.handle = (function, params) async {
        if (function == 'recall_list_projects') return [envelope(3)];
        return envelope((params['p_expected_version'] as int) + 1);
      };
      await gateway.fetchProjects();
      await gateway.mutateProject(
        projectId: project.id,
        action: 'set_status',
        payload: {'itemId': 'item-1', 'status': 'open', 'actorId': 'you'},
      );
      await gateway.mutateProject(
        projectId: project.id,
        action: 'set_status',
        payload: {'itemId': 'item-1', 'status': 'delivered', 'actorId': 'you'},
      );
      expect(transport.calls[1].params['p_expected_version'], 3);
      expect(transport.calls[2].params['p_expected_version'], 4);
      expect(
        transport.calls[1].params['p_request_id'],
        isNot(transport.calls[2].params['p_request_id']),
      );
    },
  );

  test('uncertain create and mutation retry reuse request IDs', () async {
    final transport = FakeTransport();
    final gateway = RpcCloudProjectGateway(
      transport: transport,
      currentUserId: () => 'account-a',
    );
    var failed = false;
    transport.handle = (function, params) async {
      if (function == 'recall_list_projects') return [envelope(1)];
      if (!failed) {
        failed = true;
        throw const CloudException('Network interrupted');
      }
      return envelope(2);
    };
    await expectLater(
      gateway.createProject(title: 'Website', clientName: 'Sam'),
      throwsA(isA<CloudException>()),
    );
    await gateway.createProject(title: 'Website', clientName: 'Sam');
    expect(
      transport.calls[0].params['p_request_id'],
      transport.calls[1].params['p_request_id'],
    );
    failed = false;
    await expectLater(
      gateway.mutateProject(
        projectId: project.id,
        action: 'confirm',
        payload: {'revisionId': 'r-2'},
      ),
      throwsA(isA<CloudException>()),
    );
    await gateway.mutateProject(
      projectId: project.id,
      action: 'confirm',
      payload: {'revisionId': 'r-2'},
    );
    expect(
      transport.calls[2].params['p_request_id'],
      transport.calls[3].params['p_request_id'],
    );
    expect(transport.calls[3].params['p_expected_version'], 2);
  });

  test(
    'an account switch discards pending snapshots and old project versions',
    () async {
      var user = 'account-a';
      final transport = FakeTransport();
      final pending = Completer<dynamic>();
      transport.handle = (_, _) => pending.future;
      final gateway = RpcCloudProjectGateway(
        transport: transport,
        currentUserId: () => user,
      );
      final loading = gateway.fetchProjects();
      user = 'account-b';
      pending.complete([envelope(1)]);
      await expectLater(loading, throwsA(isA<CloudException>()));
      await expectLater(
        gateway.mutateProject(projectId: project.id, action: 'delete'),
        throwsA(isA<CloudException>()),
      );
      expect(transport.calls, hasLength(1));
    },
  );

  test(
    'failed version conflict preserves the expected version until refresh',
    () async {
      final transport = FakeTransport();
      final gateway = RpcCloudProjectGateway(
        transport: transport,
        currentUserId: () => 'account-a',
      );
      transport.handle = (function, _) async {
        if (function == 'recall_list_projects') return [envelope(1)];
        throw const CloudException('Refresh', code: '40001');
      };
      await gateway.fetchProjects();
      for (var attempt = 0; attempt < 2; attempt++) {
        await expectLater(
          gateway.mutateProject(projectId: project.id, action: 'delete'),
          throwsA(isA<CloudException>()),
        );
      }
      expect(transport.calls[1].params['p_expected_version'], 1);
      expect(transport.calls[2].params['p_expected_version'], 1);
    },
  );

  test(
    'review responses validate correction and retry an uncertain receipt once',
    () async {
      final transport = FakeTransport();
      final gateway = RpcCloudReviewGateway(transport: transport);
      await expectLater(
        gateway.respond(token: 'private-token', action: 'correction'),
        throwsA(isA<CloudException>()),
      );
      expect(transport.calls, isEmpty);
      var failed = false;
      transport.handle = (_, _) async {
        if (!failed) {
          failed = true;
          throw const CloudException('Network interrupted');
        }
        return {
          'receiptId': 'receipt-1',
          'revisionId': 'revision-2',
          'version': 2,
          'action': 'confirm',
          'status': 'confirmed',
          'identity': 'link-holder response; identity not verified',
        };
      };
      await expectLater(
        gateway.respond(token: 'private-token', action: 'confirm'),
        throwsA(isA<CloudException>()),
      );
      final receipt = await gateway.respond(
        token: 'private-token',
        action: 'confirm',
      );
      expect(receipt.action, 'confirm');
      expect(
        transport.calls[0].params['p_request_id'],
        transport.calls[1].params['p_request_id'],
      );
      expect(transport.calls[0].function, 'recall_respond_review');
    },
  );

  test('share URLs keep tokens in fragment and clear unrelated queries', () {
    final link = ReviewLink.fromJson({
      'id': 'link-1',
      'token': 'private-bearer',
      'expires': '2026-11-01T00:00:00Z',
      'revisionId': 'revision-2',
      'participantId': 'client',
      'itemIds': ['item-1'],
    });
    final url = link.urlFor(
      Uri.parse('https://recall.example/?old=secret#old-route'),
    );
    expect(url.query, isEmpty);
    expect(url.fragment, 'review=private-bearer');
  });

  test('link list has no bearer token and cannot regenerate a share URL', () {
    final link = ReviewLink.fromJson({
      'id': 'link-1',
      'expires': '2026-11-01T00:00:00Z',
      'revisionId': 'revision-2',
      'participantId': 'client',
      'itemIds': ['item-1'],
      'revoked': false,
      'responded': false,
    });
    expect(link.token, isNull);
    expect(
      () => link.urlFor(Uri.parse('https://recall.example/')),
      throwsA(isA<CloudException>()),
    );
  });
}
