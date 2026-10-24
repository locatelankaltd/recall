import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:recall_next/domain/agreement_engine.dart';
import 'package:recall_next/data/demo_workspace.dart';
import 'package:recall_next/data/recall_controller.dart';

void main() {
  final now = DateTime(2026, 10, 24, 12);
  late AgreementEngine engine;
  late Project project;
  setUp(() {
    engine = AgreementEngine(clock: () => now);
    project = createDemoWorkspace(now: now).projects.first;
  });

  test('a proposed change keeps the original exact plan current', () {
    expect(project.currentRevision.items.first.amountMinor, 60000);
    expect(project.pendingProposals.single.items.first.amountMinor, 85000);
    expect(
      project.pendingProposals.single.baseRevisionId,
      project.currentRevision.id,
    );
  });

  test('both participants must accept the exact immutable revision', () {
    final proposal = project.pendingProposals.single;
    expect(proposal.acceptedBy, ['you']);
    final result = engine.acceptRevision(
      project,
      revisionId: proposal.id,
      participantId: 'client',
      expectedContentKey: proposal.contentKey,
    );
    expect(result.currentRevision.id, proposal.id);
    expect(result.currentRevision.acceptedBy, containsAll(['you', 'client']));
    expect(result.archivedRevisions.single.id, project.currentRevision.id);
    expect(project.currentRevision.items.first.amountMinor, 60000);
    expect(result.currentRevision.items.first.amountMinor, 85000);
  });

  test('a stale content key cannot accept changed content', () {
    final proposal = project.pendingProposals.single;
    expect(
      () => engine.acceptRevision(
        project,
        revisionId: proposal.id,
        participantId: 'client',
        expectedContentKey: 'old-content',
      ),
      throwsA(isA<AgreementException>()),
    );
    expect(project.currentRevision.items.first.amountMinor, 60000);
  });

  test('an unrelated actor cannot accept a proposal', () {
    final proposal = project.pendingProposals.single;
    expect(
      () => engine.acceptRevision(
        project,
        revisionId: proposal.id,
        participantId: 'stranger',
        expectedContentKey: proposal.contentKey,
      ),
      throwsA(isA<AgreementException>()),
    );
  });

  test('correction clears acceptance and cannot publish', () {
    final proposal = project.pendingProposals.single;
    final corrected = engine.requestCorrection(
      project,
      revisionId: proposal.id,
      participantId: 'client',
      note: 'Please keep the original delivery date.',
    );
    expect(corrected.pendingProposals.single.acceptedBy, isEmpty);
    expect(corrected.currentRevision.id, project.currentRevision.id);
    expect(
      () => engine.acceptRevision(
        corrected,
        revisionId: proposal.id,
        participantId: 'client',
        expectedContentKey: proposal.contentKey,
      ),
      throwsA(isA<AgreementException>()),
    );
  });

  test(
    'a proposal based on an old current plan cannot overwrite a newer plan',
    () {
      final first = project.pendingProposals.single;
      final withSecond = engine.proposeChange(
        project,
        items: project.items
            .map(
              (i) =>
                  i.id == 'sample-video' ? i.copyWith(title: 'Four videos') : i,
            )
            .toList(),
        authorId: 'you',
        evidence: first.evidence,
      );
      final second = withSecond.proposals.last;
      final published = engine.acceptRevision(
        withSecond,
        revisionId: first.id,
        participantId: 'client',
        expectedContentKey: first.contentKey,
      );
      expect(
        () => engine.acceptRevision(
          published,
          revisionId: second.id,
          participantId: 'client',
          expectedContentKey: second.contentKey,
        ),
        throwsA(isA<AgreementException>()),
      );
      expect(
        published.currentRevision.items.first.title,
        'Three launch videos',
      );
    },
  );

  test('repeated exact acceptance is idempotent', () {
    final proposal = project.pendingProposals.single;
    final once = engine.acceptRevision(
      project,
      revisionId: proposal.id,
      participantId: 'client',
      expectedContentKey: proposal.contentKey,
    );
    final twice = engine.acceptRevision(
      once,
      revisionId: proposal.id,
      participantId: 'client',
      expectedContentKey: proposal.contentKey,
    );
    expect(identical(once, twice), isTrue);
    expect(twice.archivedRevisions, hasLength(1));
  });

  test('delivery never mutates the agreed snapshot or records acceptance', () {
    final key = project.currentRevision.contentKey;
    final result = engine.setItemStatus(
      project,
      itemId: 'sample-video',
      status: ItemStatus.delivered,
      actorId: 'you',
    );
    expect(result.statusFor('sample-video'), ItemStatus.delivered);
    expect(result.currentRevision.contentKey, key);
    expect(
      () => engine.setItemStatus(
        result,
        itemId: 'sample-video',
        status: ItemStatus.accepted,
        actorId: 'you',
      ),
      throwsA(isA<AgreementException>()),
    );
    final accepted = engine.setItemStatus(
      result,
      itemId: 'sample-video',
      status: ItemStatus.accepted,
      actorId: 'client',
    );
    expect(accepted.statusFor('sample-video'), ItemStatus.accepted);
  });

  test('expanding an already delivered item resets its progress', () {
    final delivered = engine.setItemStatus(
      project,
      itemId: 'sample-video',
      status: ItemStatus.delivered,
      actorId: 'you',
    );
    final proposal = delivered.pendingProposals.single;
    final result = engine.acceptRevision(
      delivered,
      revisionId: proposal.id,
      participantId: 'client',
      expectedContentKey: proposal.contentKey,
    );
    expect(result.statusFor('sample-video'), ItemStatus.open);
  });

  test(
    'workspace round trip preserves evidence, currency, version and progress',
    () {
      final workspace = createDemoWorkspace(now: now);
      final source = jsonEncode(workspace.toJson());
      final restored = RecallWorkspace.fromJson(
        jsonDecode(source) as Map<String, dynamic>,
      );
      expect(jsonEncode(restored.toJson()), source);
      expect(
        restored.projects.first.proposals.first.contentKey,
        workspace.projects.first.proposals.first.contentKey,
      );
      expect(restored.projects.first.items.first.currency, 'EUR');
      expect(restored.isDemo, isTrue);
      expect(
        () => RecallWorkspace.fromJson({'version': 999}),
        throwsA(isA<FormatException>()),
      );
    },
  );

  test('snapshot lists cannot be altered after review', () {
    final proposal = project.pendingProposals.single;
    expect(() => proposal.items.clear(), throwsUnsupportedError);
    expect(() => proposal.acceptedBy.add('stranger'), throwsUnsupportedError);
  });

  test('real local projects cannot impersonate a client', () async {
    final controller = RecallController(repository: MemoryRecallRepository());
    await controller.initialize();
    final id = await controller.createProject(
      title: 'A real project',
      clientName: 'Client',
    );
    await controller.addItem(projectId: id, title: 'First deliverable');
    final item = controller.projectById(id)!.items.single;
    await controller.proposeChange(
      projectId: id,
      itemId: item.id,
      title: 'Changed deliverable',
      sourceText: 'My recollection of the request.',
    );
    final proposal = controller.projectById(id)!.pendingProposals.single;
    await expectLater(
      controller.confirmProposal(
        projectId: id,
        revisionId: proposal.id,
        participantId: 'client',
      ),
      throwsA(isA<AgreementException>()),
    );
    expect(controller.projectById(id)!.items.single.title, 'First deliverable');
    controller.dispose();
  });

  test(
    'concurrent saves serialize without dropping newly created projects',
    () async {
      final repo = MemoryRecallRepository();
      final controller = RecallController(repository: repo);
      await controller.initialize();
      await Future.wait([
        controller.createProject(title: 'First', clientName: 'A'),
        controller.createProject(title: 'Second', clientName: 'B'),
      ]);
      expect(controller.projects, hasLength(2));
      final reloaded = RecallController(repository: repo);
      await reloaded.initialize();
      expect(reloaded.projects.map((p) => p.title), ['First', 'Second']);
      controller.dispose();
      reloaded.dispose();
    },
  );

  test(
    'failed persistence rolls memory back and never reports success',
    () async {
      final controller = RecallController(repository: _FailingRepository());
      await controller.initialize();
      await expectLater(
        controller.createProject(title: 'Not saved', clientName: 'Client'),
        throwsStateError,
      );
      expect(controller.projects, isEmpty);
      expect(controller.selectedProjectId, isNull);
      expect(controller.error, isNotNull);
      controller.dispose();
    },
  );

  test('editor saves reject a changed current baseline', () async {
    final controller = RecallController(repository: MemoryRecallRepository());
    await controller.initialize();
    final id = await controller.createProject(
      title: 'Project',
      clientName: 'Client',
    );
    await controller.addItem(projectId: id, title: 'First');
    final original = controller.projectById(id)!;
    await controller.addItem(projectId: id, title: 'Added while editing');
    await expectLater(
      controller.proposeChange(
        projectId: id,
        itemId: original.items.first.id,
        title: 'Old editor values',
        sourceText: 'A written recollection.',
        expectedBaseRevisionId: original.currentRevision.id,
      ),
      throwsA(isA<AgreementException>()),
    );
    expect(controller.projectById(id)!.items, hasLength(2));
    expect(controller.projectById(id)!.proposals, isEmpty);
    controller.dispose();
  });

  test('reset removes audio referenced by an earlier queued save', () async {
    final removed = <String?>[];
    final controller = RecallController(
      repository: MemoryRecallRepository(),
      recordingRemover: (path) async => removed.add(path),
    );
    await controller.initialize();
    final id = await controller.createProject(
      title: 'Project',
      clientName: 'Client',
    );
    await controller.addItem(projectId: id, title: 'Item');
    final item = controller.projectById(id)!.items.first;
    final proposed = controller.proposeChange(
      projectId: id,
      itemId: item.id,
      title: 'Updated',
      sourceText: 'Written personal debrief.',
      attachmentPath: '/local/debrief.m4a',
    );
    final reset = controller.clearAll();
    await Future.wait([proposed, reset]);
    expect(removed, ['/local/debrief.m4a']);
    expect(controller.projects, isEmpty);
    controller.dispose();
  });

  test('a load retry waits for the in-flight save', () async {
    final repo = _DelayedRepository();
    final controller = RecallController(repository: repo);
    await controller.initialize();
    final creating = controller.createProject(
      title: 'Retained',
      clientName: 'Client',
    );
    await repo.saveStarted.future;
    final reloading = controller.initialize();
    repo.continueSave.complete();
    await Future.wait([creating, reloading]);
    expect(controller.projects.single.title, 'Retained');
    controller.dispose();
  });

  test(
    'failed reset after a load failure never unlocks unsafe writes',
    () async {
      final repo = _UnreadableRepository();
      final controller = RecallController(repository: repo);
      await controller.initialize();
      await expectLater(controller.clearAll(), throwsStateError);
      await expectLater(
        controller.createProject(
          title: 'Must not overwrite saved data',
          clientName: 'Client',
        ),
        throwsA(isA<AgreementException>()),
      );
      expect(repo.saveCount, 1);
      controller.dispose();
    },
  );

  test(
    'sources cannot claim unsupported extraction kinds or omit language',
    () {
      for (final source in [
        Evidence(
          id: 'bad-kind',
          text: 'Text',
          language: 'en',
          kind: 'verifiedImportedThread',
          createdAt: now,
        ),
        Evidence(
          id: 'no-language',
          text: 'Text',
          language: '',
          kind: 'originalText',
          createdAt: now,
        ),
      ]) {
        expect(
          () => engine.proposeChange(
            project,
            items: project.items,
            authorId: 'you',
            evidence: [source],
          ),
          throwsA(isA<AgreementException>()),
        );
      }
    },
  );
  test(
    'editable restores cannot establish real recipient confirmations',
    () async {
      final controller = RecallController(repository: MemoryRecallRepository());
      await controller.initialize();
      final id = await controller.createProject(
        title: 'Keep this work',
        clientName: 'Client',
      );
      final forged = createDemoWorkspace(now: now).toJson();
      final first = (forged['projects'] as List).first as Map<String, dynamic>;
      first['isDemo'] = false;
      forged['isDemo'] = false;
      await expectLater(
        controller.importJson(jsonEncode(forged)),
        throwsA(isA<AgreementException>()),
      );
      expect(controller.projects.single.id, id);
      expect(controller.error, contains('cannot verify'));
      controller.dispose();
    },
  );

  test(
    'an ordinary private project export restores without false client reviews',
    () async {
      final controller = RecallController(repository: MemoryRecallRepository());
      await controller.initialize();
      final id = await controller.createProject(
        title: 'Real local work',
        clientName: 'Client',
      );
      await controller.addItem(projectId: id, title: 'A private baseline');
      final backup = controller.exportJson;
      await controller.clearAll();
      await controller.importJson(backup);
      expect(
        controller.projects.single.items.single.title,
        'A private baseline',
      );
      expect(controller.projects.single.currentRevision.acceptedBy, ['you']);
      controller.dispose();
    },
  );

  test(
    'malformed backups cannot introduce duplicate identities or unknown owners',
    () {
      final duplicated = createDemoWorkspace(now: now).toJson();
      final entries = duplicated['projects'] as List;
      entries.add(entries.first);
      expect(() => RecallWorkspace.fromJson(duplicated), throwsFormatException);
      final foreignOwner = createDemoWorkspace(now: now).toJson();
      final first =
          (foreignOwner['projects'] as List).first as Map<String, dynamic>;
      ((first['currentRevision'] as Map)['items'] as List).first['ownerId'] =
          'unknown';
      expect(
        () => RecallWorkspace.fromJson(foreignOwner),
        throwsFormatException,
      );
    },
  );
}

class _FailingRepository implements RecallRepository {
  @override
  Future<RecallWorkspace?> load() async => null;
  @override
  Future<void> save(RecallWorkspace workspace) async =>
      throw StateError('Disk full');
}

class _DelayedRepository extends MemoryRecallRepository {
  final saveStarted = Completer<void>();
  final continueSave = Completer<void>();
  @override
  Future<void> save(RecallWorkspace workspace) async {
    saveStarted.complete();
    await continueSave.future;
    await super.save(workspace);
  }
}

class _UnreadableRepository implements RecallRepository {
  var saveCount = 0;
  @override
  Future<RecallWorkspace?> load() async =>
      throw StateError('Unreadable saved data');
  @override
  Future<void> save(RecallWorkspace workspace) async {
    saveCount++;
    throw StateError('Cannot save');
  }
}
