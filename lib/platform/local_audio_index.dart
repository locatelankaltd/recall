import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../data/recording_files.dart';
import '../domain/recall_models.dart';

abstract interface class LocalAudioIndexStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class SecureLocalAudioIndexStore implements LocalAudioIndexStore {
  const SecureLocalAudioIndexStore({
    this.storage = const FlutterSecureStorage(),
  });
  final FlutterSecureStorage storage;

  @override
  Future<String?> read(String key) => storage.read(key: key);
  @override
  Future<void> write(String key, String value) =>
      storage.write(key: key, value: value);
  @override
  Future<void> delete(String key) => storage.delete(key: key);
}

/// Bounded codec with an account binding inside the value as well as its key.
/// Paths decoded here remain untrusted until the owned-file validator runs.
abstract final class LocalAudioIndexCodec {
  static const maxEntries = 256;
  static const maxBytes = 256 * 1024;
  static const maxPathCharacters = 4096;

  static void validateId(String id) {
    if (!RegExp(r'^[A-Za-z0-9_-]{1,128}$').hasMatch(id)) {
      throw const FormatException(
        'The local recording index contains an invalid identifier.',
      );
    }
  }

  static Map<String, String> decode(String value, {required String userId}) {
    validateId(userId);
    try {
      if (value.length > maxBytes || utf8.encode(value).length > maxBytes) {
        throw const FormatException();
      }
      final decoded = jsonDecode(value);
      if (decoded is! Map ||
          decoded['version'] != 1 ||
          decoded['userId'] != userId) {
        throw const FormatException();
      }
      final entries = decoded['entries'];
      if (entries is! Map || entries.length > maxEntries) {
        throw const FormatException();
      }
      final result = <String, String>{};
      for (final entry in entries.entries) {
        if (entry.key is! String || entry.value is! String) {
          throw const FormatException();
        }
        validateId(entry.key as String);
        final path = entry.value as String;
        _validatePathShape(path);
        result[entry.key as String] = path;
      }
      return result;
    } on FormatException {
      // jsonDecode's original exception may contain raw private file paths.
      throw const FormatException(
        'The local recording index could not be read for this account.',
      );
    }
  }

  static String encode(Map<String, String> entries, {required String userId}) {
    validateId(userId);
    if (entries.length > maxEntries) {
      throw StateError(
        'The local recording index is full. Export recordings before adding more.',
      );
    }
    for (final entry in entries.entries) {
      validateId(entry.key);
      _validatePathShape(entry.value);
    }
    final result = jsonEncode({
      'version': 1,
      'userId': userId,
      'entries': entries,
    });
    if (utf8.encode(result).length > maxBytes) {
      throw StateError(
        'The local recording index is full. Export recordings before adding more.',
      );
    }
    return result;
  }

  static void _validatePathShape(String path) {
    if (path.isEmpty ||
        path.length > maxPathCharacters ||
        path.contains('\u0000')) {
      throw const FormatException(
        'The local recording index contains an invalid recording path.',
      );
    }
  }
}

/// Reattaches this account's on-device audio to matching cloud source IDs.
///
/// The index contains only source IDs and owned local paths; it never uploads
/// audio or modifies a cloud snapshot. Never serialize a decorated Project into
/// an RPC: the cloud gateway must omit every attachmentPath field.
class LocalAudioIndex {
  LocalAudioIndex({
    required this.userId,
    LocalAudioIndexStore? storage,
    Future<String> Function(String)? pathValidator,
    Future<void> Function(String?)? recordingDiscarder,
  }) : _storage = storage ?? const SecureLocalAudioIndexStore(),
       _pathValidator = pathValidator ?? requireOwnedRecordingPath,
       _recordingDiscarder = recordingDiscarder ?? discardRecording {
    LocalAudioIndexCodec.validateId(userId);
  }

  final String userId;
  final LocalAudioIndexStore _storage;
  final Future<String> Function(String) _pathValidator;
  final Future<void> Function(String?) _recordingDiscarder;
  Future<void> _tail = Future<void>.value();
  final _unavailableSourceIds = <String>{};

  String get storageKey =>
      'recall_local_audio_v1_${base64Url.encode(utf8.encode(userId))}';
  Set<String> get unavailableSourceIds =>
      Set.unmodifiable(_unavailableSourceIds);

  Future<Map<String, String>> _read() async {
    String? value;
    try {
      value = await _storage.read(storageKey);
    } catch (_) {
      throw StateError(
        'The local recording index could not be accessed on this device.',
      );
    }
    return value == null
        ? {}
        : LocalAudioIndexCodec.decode(value, userId: userId);
  }

  Future<T> _serial<T>(Future<T> Function() operation) {
    final result = Completer<T>();
    _tail = _tail.then((_) async {
      try {
        result.complete(await operation());
      } catch (problem, stack) {
        result.completeError(problem, stack);
      }
    });
    return result.future;
  }

  Future<void> remember(String sourceId, String path) => _serial(() async {
    LocalAudioIndexCodec.validateId(sourceId);
    LocalAudioIndexCodec._validatePathShape(path);
    final ownedPath = await _pathValidator(path);
    final entries = await _read();
    entries[sourceId] = ownedPath;
    final encoded = LocalAudioIndexCodec.encode(entries, userId: userId);
    try {
      await _storage.write(storageKey, encoded);
    } catch (_) {
      throw StateError(
        'The local recording index could not be saved on this device.',
      );
    }
    _unavailableSourceIds.remove(sourceId);
  });

  Future<Project> decorate(Project server) => _serial(() async {
    final entries = await _read();
    final validPaths = <String, String>{};
    final sources =
        [
              server.currentRevision,
              ...server.proposals,
              ...server.archivedRevisions,
            ]
            .expand((revision) => revision.evidence)
            .map((evidence) => evidence.id)
            .toSet();
    for (final sourceId in sources) {
      final path = entries[sourceId];
      if (path == null) continue;
      try {
        validPaths[sourceId] = await _pathValidator(path);
        _unavailableSourceIds.remove(sourceId);
      } catch (_) {
        _unavailableSourceIds.add(sourceId);
      }
    }
    PlanRevision decorateRevision(PlanRevision revision) => PlanRevision(
      id: revision.id,
      number: revision.number,
      createdAt: revision.createdAt,
      authorId: revision.authorId,
      items: revision.items,
      requiredParticipantIds: revision.requiredParticipantIds,
      baseRevisionId: revision.baseRevisionId,
      status: revision.status,
      acceptedBy: revision.acceptedBy,
      correctionNote: revision.correctionNote,
      evidence: revision.evidence
          .map(
            (source) => Evidence(
              id: source.id,
              text: source.text,
              language: source.language,
              kind: source.kind,
              createdAt: source.createdAt,
              attachmentPath: validPaths[source.id],
            ),
          )
          .toList(),
    );
    return server.copyWith(
      currentRevision: decorateRevision(server.currentRevision),
      proposals: server.proposals.map(decorateRevision).toList(),
      archivedRevisions: server.archivedRevisions
          .map(decorateRevision)
          .toList(),
    );
  });

  /// Removes mappings for an explicitly deleted project's source IDs. The
  /// caller can separately delete its owned recording files when requested.
  Future<void> forgetSources(Set<String> sourceIds) => _serial(() async {
    for (final sourceId in sourceIds) {
      LocalAudioIndexCodec.validateId(sourceId);
    }
    final entries = await _read();
    for (final sourceId in sourceIds) {
      entries.remove(sourceId);
    }
    final encoded = LocalAudioIndexCodec.encode(entries, userId: userId);
    try {
      await _storage.write(storageKey, encoded);
    } catch (_) {
      throw StateError(
        'The local recording index could not be saved on this device.',
      );
    }
    _unavailableSourceIds.removeAll(sourceIds);
  });

  /// Clears only this account's index. With [deleteRecordings], first deletes
  /// its available owned recordings. Sign-out must not call this cleanup.
  Future<void> clear({bool deleteRecordings = false}) => _serial(() async {
    if (deleteRecordings) {
      final entries = await _read();
      for (final path in entries.values.toSet()) {
        String ownedPath;
        try {
          ownedPath = await _pathValidator(path);
        } catch (_) {
          // Missing, moved, or unowned paths are never passed to file deletion.
          continue;
        }
        try {
          await _recordingDiscarder(ownedPath);
        } catch (_) {
          // Preserve the index to make an unsuccessful file cleanup retryable.
          throw StateError(
            'Some local recordings could not be removed. Try again.',
          );
        }
      }
    }
    try {
      await _storage.delete(storageKey);
    } catch (_) {
      throw StateError(
        'The local recording index could not be cleared on this device.',
      );
    }
    _unavailableSourceIds.clear();
  });
}
