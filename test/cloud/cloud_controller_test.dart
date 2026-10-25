import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:recall_next/cloud/recall_cloud.dart';
import 'package:recall_next/data/recall_controller.dart';
import 'package:recall_next/domain/agreement_engine.dart';

class PrivateRepositorySpy implements RecallRepository {
  PrivateRepositorySpy(this.value);
  RecallWorkspace value;
  var loads = 0;
  var saves = 0;
  @override
  Future<RecallWorkspace?> load() async {
    loads++;
    return value;
  }

  @override
  Future<void> save(RecallWorkspace workspace) async {
    saves++;
    value = workspace;
  }
}

class ControllerGateway implements CloudProjectGateway {
  ControllerGateway(List<Project> projects) : remote = List.of(projects);
  List<Project> remote;
  final events = <String>[];
  final mutations =
      <({String projectId, String action, Map<String, dynamic> payload})>[];
  Future<Project?> Function(
    String projectId,
    String action,
    Map<String, dynamic> payload,
  )?
  onMutation;
  Future<Project> Function(String title, String client, String category)?
  onCreate;
  Future<List<Project>> Function()? onFetch;
  var creates = 0;
  var fetches = 0;
  @override
  Future<List<Project>> fetchProjects() async {
    fetches++;
    events.add('fetch');
    return onFetch == null ? List.of(remote) : await onFetch!();
  }

  @override
  Future<Project> createProject({
    required String title,
    required String clientName,
    String category = 'Creative',
  }) async {
    creates++;
    events.add('create');
    if (onCreate != null) return await onCreate!(title, clientName, category);
    throw StateError('Unexpected cloud project creation');
  }

  @override
  Future<Project?> mutateProject({
    required String projectId,
    required String action,
    Map<String, dynamic> payload = const {},
  }) async {
    mutations.add((
      projectId: projectId,
      action: action,
      payload: Map<String, dynamic>.from(
        jsonDecode(jsonEncode(payload)) as Map,
      ),
    ));
    events.add('mutation-start');
    final result = onMutation == null
        ? remote.single
        : await onMutation!(projectId, action, payload);
    events.add('mutation-end');
    return result;
  }
}

void main() {
  final engine = AgreementEngine();
  final baseline = engine.addItem(
    engine.createProject(title: 'Cloud project', clientName: 'Sam'),
    const PlanItem(
      id: 'item-1',
      title: 'Server deliverable',
      details: 'Confirmed scope',
    ),
  );
  final serverAfterAdd = engine.addItem(
    baseline,
    const PlanItem(id: 'server-item-2', title: 'Server accepted value'),
  );
  final proposal = engine.proposeChange(
    baseline,
    items: [baseline.items.single.copyWith(details: 'Requested revised scope')],
    authorId: 'you',
    evidence: [
      Evidence(
        id: 'server-source',
        text: 'Please change the scope',
        language: 'en',
        kind: 'originalText',
        createdAt: DateTime.utc(2026),
      ),
    ],
  );
  final privateProject = engine.createProject(
    title: 'Private device project',
    clientName: 'Local client',
  );

  test(
    'cloud mutations display only canonical server snapshots after completion',
    () async {
      final gateway = ControllerGateway([baseline]);
      final pending = Completer<Project?>();
      gateway.onMutation = (_, _, _) => pending.future;
      final controller = RecallController(cloudGateway: gateway);
      addTearDown(controller.dispose);
      await controller.initialize();
      final writing = controller.addItem(
        projectId: baseline.id,
        title: 'Unconfirmed local title',
      );
      await Future<void>.delayed(Duration.zero);
      expect(identical(controller.projects.single, baseline), isTrue);
      expect(
        controller.projects.single.items.any(
          (i) => i.title == 'Unconfirmed local title',
        ),
        isFalse,
      );
      expect(gateway.mutations.single.action, 'add_item');
      pending.complete(serverAfterAdd);
      await writing;
      expect(identical(controller.projects.single, serverAfterAdd), isTrue);
      expect(controller.projects.single.items.last.id, 'server-item-2');
      expect(
        controller.projects.single.items.any(
          (i) => i.title == 'Unconfirmed local title',
        ),
        isFalse,
      );
    },
  );

  test(
    'an ambiguous write leaves confirmed plan untouched until a successful refresh',
    () async {
      final gateway = ControllerGateway([baseline]);
      gateway.onMutation = (_, _, _) async {
        // The server could have committed despite a lost response.
        gateway.remote = [serverAfterAdd];
        throw const CloudException('The response was interrupted.');
      };
      final controller = RecallController(cloudGateway: gateway);
      addTearDown(controller.dispose);
      await controller.initialize();
      final before = controller.exportJson;
      await expectLater(
        controller.addItem(projectId: baseline.id, title: 'Requested addition'),
        throwsA(isA<CloudException>()),
      );
      expect(controller.exportJson, before);
      expect(controller.error, 'The response was interrupted.');
      await controller.refreshFromCloud();
      expect(identical(controller.projects.single, serverAfterAdd), isTrue);
      expect(controller.error, isNull);
    },
  );

  test(
    'cloud operations and locale changes never overwrite a private repository',
    () async {
      final repository = PrivateRepositorySpy(
        RecallWorkspace(projects: [privateProject]),
      );
      final gateway = ControllerGateway([baseline]);
      final created = engine.createProject(
        title: 'Server-created project',
        clientName: 'Cloud client',
      );
      gateway.onCreate = (_, _, _) async => created;
      gateway.onMutation = (_, action, _) async =>
          action == 'delete' ? null : serverAfterAdd;
      final controller = RecallController(
        cloudGateway: gateway,
        repository: repository,
      );
      addTearDown(controller.dispose);
      await controller.initialize();
      await controller.createProject(
        title: 'Requested cloud title',
        clientName: 'Requested cloud client',
      );
      await controller.addItem(projectId: baseline.id, title: 'Cloud addition');
      await controller.markItemStatus(
        projectId: baseline.id,
        itemId: 'item-1',
        status: ItemStatus.delivered,
      );
      await controller.setLocale('fr');
      await controller.refreshFromCloud();
      await controller.deleteProject(baseline.id);
      expect(repository.loads, 0);
      expect(repository.saves, 0);
      expect(repository.value.projects.single.id, privateProject.id);
      expect(controller.locale, 'fr');
    },
  );

  test(
    'cloud owner cannot submit confirmations corrections or progress as another person',
    () async {
      final gateway = ControllerGateway([proposal]);
      final controller = RecallController(cloudGateway: gateway);
      addTearDown(controller.dispose);
      await controller.initialize();
      final before = controller.exportJson;
      await expectLater(
        controller.confirmProposal(
          projectId: proposal.id,
          revisionId: proposal.proposals.single.id,
          participantId: 'client',
        ),
        throwsA(isA<AgreementException>()),
      );
      await expectLater(
        controller.requestCorrection(
          projectId: proposal.id,
          revisionId: proposal.proposals.single.id,
          participantId: 'client',
          note: 'Change the scope',
        ),
        throwsA(isA<AgreementException>()),
      );
      await expectLater(
        controller.markItemStatus(
          projectId: proposal.id,
          itemId: 'item-1',
          actorId: 'client',
          status: ItemStatus.accepted,
        ),
        throwsA(isA<AgreementException>()),
      );
      expect(gateway.mutations, isEmpty);
      expect(controller.exportJson, before);
    },
  );

  test(
    'cloud proposal payload strips device recording paths and keeps source provenance',
    () async {
      final gateway = ControllerGateway([baseline]);
      gateway.onMutation = (_, action, payload) async {
        expect(action, 'propose_change');
        return engine.proposeChange(
          baseline,
          items: (payload['items'] as List)
              .map(
                (item) =>
                    PlanItem.fromJson(Map<String, dynamic>.from(item as Map)),
              )
              .toList(),
          authorId: 'you',
          evidence: (payload['evidence'] as List)
              .map(
                (source) =>
                    Evidence.fromJson(Map<String, dynamic>.from(source as Map)),
              )
              .toList(),
        );
      };
      final controller = RecallController(cloudGateway: gateway);
      addTearDown(controller.dispose);
      await controller.initialize();
      await controller.proposeChange(
        projectId: baseline.id,
        itemId: 'item-1',
        details: 'Revised scope',
        sourceText: 'My recollection of the request',
        sourceLanguage: 'ta',
        sourceKind: 'personalRecollection',
        attachmentPath: '/private/device/recordings/secret.m4a',
        expectedBaseRevisionId: baseline.currentRevision.id,
      );
      final payload = gateway.mutations.single.payload;
      final source = (payload['evidence'] as List).single as Map;
      expect(source.containsKey('attachmentPath'), isFalse);
      expect(jsonEncode(payload), isNot(contains('/private/device')));
      expect(source['kind'], 'personalRecollection');
      expect(source['language'], 'ta');
      expect(source['text'], 'My recollection of the request');
      expect(
        controller.projects.single.currentRevision.id,
        baseline.currentRevision.id,
      );
      expect(
        controller
            .projects
            .single
            .proposals
            .single
            .evidence
            .single
            .attachmentPath,
        isNull,
      );
      expect(
        controller.projects.single.proposals.single.acceptedBy,
        isNot(contains('client')),
      );
    },
  );

  test(
    'refresh waits for an in-flight mutation and then shows the newest server state',
    () async {
      final gateway = ControllerGateway([baseline]);
      final pending = Completer<Project?>();
      gateway.onMutation = (_, _, _) => pending.future;
      final controller = RecallController(cloudGateway: gateway);
      addTearDown(controller.dispose);
      await controller.initialize();
      final writing = controller.addItem(
        projectId: baseline.id,
        title: 'Requested item',
      );
      await Future<void>.delayed(Duration.zero);
      final refreshing = controller.refreshFromCloud();
      await Future<void>.delayed(Duration.zero);
      expect(gateway.fetches, 1);
      expect(gateway.events, ['fetch', 'mutation-start']);
      final newest = serverAfterAdd.copyWith(
        itemStatuses: {'item-1': ItemStatus.delivered},
      );
      gateway.remote = [newest];
      pending.complete(serverAfterAdd);
      await writing;
      await refreshing;
      expect(gateway.events, [
        'fetch',
        'mutation-start',
        'mutation-end',
        'fetch',
      ]);
      expect(identical(controller.projects.single, newest), isTrue);
      expect(
        controller.projects.single.statusFor('item-1'),
        ItemStatus.delivered,
      );
    },
  );

  test(
    'cloud import reset and demo replacement reject forged workspace history',
    () async {
      final gateway = ControllerGateway([proposal]);
      final repository = PrivateRepositorySpy(
        RecallWorkspace(projects: [privateProject]),
      );
      final controller = RecallController(
        cloudGateway: gateway,
        repository: repository,
      );
      addTearDown(controller.dispose);
      await controller.initialize();
      final before = controller.exportJson;
      final forged = jsonDecode(before) as Map<String, dynamic>;
      ((forged['projects'] as List).single as Map)['history'] = [
        {
          'id': 'forged-event',
          'message': 'Client confirmed the agreement',
          'createdAt': DateTime.utc(2026).toIso8601String(),
          'actorId': 'client',
          'revisionId': proposal.proposals.single.id,
        },
      ];
      await expectLater(
        controller.importJson(jsonEncode(forged)),
        throwsA(isA<AgreementException>()),
      );
      await expectLater(
        controller.clearAll(),
        throwsA(isA<AgreementException>()),
      );
      await expectLater(
        controller.loadDemo(),
        throwsA(isA<AgreementException>()),
      );
      expect(controller.exportJson, before);
      expect(repository.saves, 0);
      expect(gateway.mutations, isEmpty);
      expect(gateway.creates, 0);
    },
  );

  test(
    'disposing an account controller cancels queued writes before a new account can run them',
    () async {
      final gateway = ControllerGateway([baseline]);
      final pending = Completer<Project?>();
      gateway.onMutation = (_, _, _) => pending.future;
      gateway.onCreate = (_, _, _) async => privateProject;
      final controller = RecallController(cloudGateway: gateway);
      await controller.initialize();
      final inFlight = controller.addItem(
        projectId: baseline.id,
        title: 'First account item',
      );
      await Future<void>.delayed(Duration.zero);
      final queuedCreate = controller.createProject(
        title: 'First account secret project',
        clientName: 'First account client',
      );
      final rejected = expectLater(
        queuedCreate,
        throwsA(isA<AgreementException>()),
      );
      controller.dispose();
      pending.complete(serverAfterAdd);
      // An operation already sent may finish; a queued one must never be sent
      // through a shared gateway after the session has switched accounts.
      await inFlight;
      await rejected;
      expect(gateway.creates, 0);
    },
  );
}
