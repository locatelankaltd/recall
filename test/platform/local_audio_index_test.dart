import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:recall_next/domain/recall_models.dart';
import 'package:recall_next/platform/local_audio_index.dart';

class MemoryAudioStore implements LocalAudioIndexStore {
  final values = <String, String>{};
  bool failRead = false;
  bool failWrite = false;

  @override
  Future<String?> read(String key) async {
    if (failRead) throw StateError('A private native failure');
    return values[key];
  }

  @override
  Future<void> write(String key, String value) async {
    if (failWrite) throw StateError('A private native failure');
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async => values.remove(key);
}

Project serverProject({String? attachmentPath}) {
  final at = DateTime.utc(2026, 10, 24);
  final source = Evidence(
    id: 'source-a',
    text: 'Original source · தமிழ்',
    language: 'ta',
    kind: 'personalRecollection',
    createdAt: at,
    attachmentPath: attachmentPath,
  );
  PlanRevision revision(String id, int number, RevisionStatus status) =>
      PlanRevision(
        id: id,
        number: number,
        createdAt: at,
        authorId: 'you',
        baseRevisionId: number > 1 ? 'revision-1' : null,
        status: status,
        acceptedBy: ['you'],
        requiredParticipantIds: ['you'],
        items: const [PlanItem(id: 'item-a', title: 'A reviewed deliverable')],
        evidence: [source],
        correctionNote: 'Preserve this note',
      );
  return Project(
    id: 'project-a',
    title: 'A cloud project',
    clientName: 'A client',
    participants: const [Participant(id: 'you', name: 'You', role: 'owner')],
    currentRevision: revision('revision-2', 2, RevisionStatus.confirmed),
    proposals: [revision('revision-3', 3, RevisionStatus.proposed)],
    archivedRevisions: [revision('revision-1', 1, RevisionStatus.confirmed)],
    itemStatuses: const {'item-a': ItemStatus.delivered},
  );
}

void main() {
  const pathA = '/owned/audio/debrief-1.m4a';
  const pathB = '/owned/audio/debrief-2.m4a';

  test(
    'bounded codec round trips a single account and rejects a different account',
    () {
      final encoded = LocalAudioIndexCodec.encode({
        'source-a': pathA,
      }, userId: 'account-a');
      expect(LocalAudioIndexCodec.decode(encoded, userId: 'account-a'), {
        'source-a': pathA,
      });
      expect(
        () => LocalAudioIndexCodec.decode(encoded, userId: 'account-b'),
        throwsFormatException,
      );
      for (final corrupt in [
        'not-json',
        '[]',
        jsonEncode({
          'version': 1,
          'userId': 'account-a',
          'entries': {'source-a': 7},
        }),
        jsonEncode({'version': 2, 'userId': 'account-a', 'entries': {}}),
      ]) {
        expect(
          () => LocalAudioIndexCodec.decode(corrupt, userId: 'account-a'),
          throwsFormatException,
        );
      }
    },
  );

  test(
    'codec rejects entry and byte limits and sanitizes malformed JSON errors',
    () {
      expect(
        () => LocalAudioIndexCodec.encode({
          for (var i = 0; i <= LocalAudioIndexCodec.maxEntries; i++)
            'source-$i': pathA,
        }, userId: 'account-a'),
        throwsStateError,
      );
      expect(
        () => LocalAudioIndexCodec.decode(
          'a' * (LocalAudioIndexCodec.maxBytes + 1),
          userId: 'account-a',
        ),
        throwsFormatException,
      );
      try {
        LocalAudioIndexCodec.decode(
          '{"private":"/private/sensitive.m4a"',
          userId: 'account-a',
        );
        fail('Malformed JSON was accepted');
      } on FormatException catch (problem) {
        expect(problem.source, isNull);
        expect(problem.toString(), isNot(contains('/private/sensitive')));
      }
    },
  );

  test('remember requires an owned path before storing anything', () async {
    final store = MemoryAudioStore();
    final index = LocalAudioIndex(
      userId: 'account-a',
      storage: store,
      pathValidator: (_) async => throw StateError('Recording unavailable'),
    );
    await expectLater(
      index.remember('source-a', '/outside/file.m4a'),
      throwsStateError,
    );
    expect(store.values, isEmpty);
  });

  test(
    'accounts use separate namespaces even for identical source IDs',
    () async {
      final store = MemoryAudioStore();
      Future<String> validator(String path) async => path;
      final a = LocalAudioIndex(
        userId: 'account-a',
        storage: store,
        pathValidator: validator,
      );
      final b = LocalAudioIndex(
        userId: 'account-b',
        storage: store,
        pathValidator: validator,
      );
      await a.remember('source-a', pathA);
      await b.remember('source-a', pathB);
      expect(a.storageKey, isNot(b.storageKey));
      expect(
        (await a.decorate(
          serverProject(),
        )).currentRevision.evidence.single.attachmentPath,
        pathA,
      );
      expect(
        (await b.decorate(
          serverProject(),
        )).currentRevision.evidence.single.attachmentPath,
        pathB,
      );
      await a.clear();
      expect(store.values.containsKey(a.storageKey), isFalse);
      expect(store.values.containsKey(b.storageKey), isTrue);
    },
  );

  test(
    'decoration rebuilds every revision without mutating the server snapshot',
    () async {
      final index = LocalAudioIndex(
        userId: 'account-a',
        storage: MemoryAudioStore(),
        pathValidator: (path) async => path,
      );
      await index.remember('source-a', pathA);
      final server = serverProject(attachmentPath: '/untrusted/server-path');
      final decorated = await index.decorate(server);
      for (final revision in [
        decorated.currentRevision,
        ...decorated.proposals,
        ...decorated.archivedRevisions,
      ]) {
        expect(revision.evidence.single.attachmentPath, pathA);
        expect(revision.evidence.single.text, 'Original source · தமிழ்');
        expect(revision.evidence.single.language, 'ta');
        expect(revision.acceptedBy, ['you']);
        expect(revision.correctionNote, 'Preserve this note');
      }
      expect(decorated.currentRevision.status, RevisionStatus.confirmed);
      expect(decorated.itemStatuses, server.itemStatuses);
      expect(
        server.currentRevision.evidence.single.attachmentPath,
        '/untrusted/server-path',
      );
    },
  );

  test(
    'unindexed or missing paths never inherit server-provided file paths',
    () async {
      final store = MemoryAudioStore();
      var fileExists = true;
      final index = LocalAudioIndex(
        userId: 'account-a',
        storage: store,
        pathValidator: (path) async {
          if (!fileExists) throw StateError('File missing');
          return path;
        },
      );
      final server = serverProject(attachmentPath: '/untrusted/server-path');
      expect(
        (await index.decorate(
          server,
        )).currentRevision.evidence.single.attachmentPath,
        isNull,
      );
      await index.remember('source-a', pathA);
      fileExists = false;
      expect(
        (await index.decorate(
          server,
        )).currentRevision.evidence.single.attachmentPath,
        isNull,
      );
      expect(index.unavailableSourceIds, {'source-a'});
    },
  );

  test(
    'concurrent remembers serialize without overwriting other source mappings',
    () async {
      final store = MemoryAudioStore();
      final index = LocalAudioIndex(
        userId: 'account-a',
        storage: store,
        pathValidator: (path) async => path,
      );
      await Future.wait([
        index.remember('source-a', pathA),
        index.remember('source-b', pathB),
      ]);
      expect(
        LocalAudioIndexCodec.decode(
          store.values[index.storageKey]!,
          userId: 'account-a',
        ),
        {'source-a': pathA, 'source-b': pathB},
      );
    },
  );

  test(
    'corrupt, wrong-account, and inaccessible storage fail without another namespace fallback',
    () async {
      final store = MemoryAudioStore();
      final index = LocalAudioIndex(
        userId: 'account-a',
        storage: store,
        pathValidator: (path) async => path,
      );
      store.values[index.storageKey] = LocalAudioIndexCodec.encode({
        'source-a': pathB,
      }, userId: 'account-b');
      await expectLater(index.decorate(serverProject()), throwsFormatException);
      store.values.clear();
      store.failRead = true;
      await expectLater(index.decorate(serverProject()), throwsStateError);
      store.failRead = false;
      store.failWrite = true;
      await expectLater(index.remember('source-a', pathA), throwsStateError);
      expect(store.values, isEmpty);
    },
  );

  test(
    'forgetSources removes only selected metadata and never deletes audio',
    () async {
      final store = MemoryAudioStore();
      final deleted = <String?>[];
      final index = LocalAudioIndex(
        userId: 'account-a',
        storage: store,
        pathValidator: (path) async => path,
        recordingDiscarder: (path) async => deleted.add(path),
      );
      await index.remember('source-a', pathA);
      await index.remember('source-b', pathB);
      await index.forgetSources({'source-a'});
      expect(
        LocalAudioIndexCodec.decode(
          store.values[index.storageKey]!,
          userId: 'account-a',
        ),
        {'source-b': pathB},
      );
      expect(deleted, isEmpty);
    },
  );

  test(
    'account cleanup deletes only validated owned files and deduplicates paths',
    () async {
      final store = MemoryAudioStore();
      final deleted = <String?>[];
      var rejectB = false;
      final index = LocalAudioIndex(
        userId: 'account-a',
        storage: store,
        pathValidator: (path) async {
          if (path == pathB && rejectB) throw StateError('No longer owned');
          return path;
        },
        recordingDiscarder: (path) async => deleted.add(path),
      );
      await index.remember('source-a', pathA);
      await index.remember('source-a2', pathA);
      await index.remember('source-b', pathB);
      rejectB = true;
      await index.clear(deleteRecordings: true);
      expect(deleted, [pathA]);
      expect(store.values.containsKey(index.storageKey), isFalse);
    },
  );

  test('failed audio deletion keeps its account index retryable', () async {
    final store = MemoryAudioStore();
    var failDelete = true;
    final index = LocalAudioIndex(
      userId: 'account-a',
      storage: store,
      pathValidator: (path) async => path,
      recordingDiscarder: (_) async {
        if (failDelete) throw StateError('File permission failure');
      },
    );
    await index.remember('source-a', pathA);
    await expectLater(index.clear(deleteRecordings: true), throwsStateError);
    expect(store.values.containsKey(index.storageKey), isTrue);
    failDelete = false;
    await index.clear(deleteRecordings: true);
    expect(store.values.containsKey(index.storageKey), isFalse);
  });
}
