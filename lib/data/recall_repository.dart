import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../domain/recall_models.dart';

abstract class RecallRepository {
  Future<RecallWorkspace?> load();
  Future<void> save(RecallWorkspace workspace);
}

/// Bounded local MVP storage using the platform secure-storage plugin.
/// This is not cloud synchronization or a recovery backup. Web security depends
/// on browser/origin storage and is not equivalent to a hardware-backed vault.
class SecureRecallRepository implements RecallRepository {
  SecureRecallRepository({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();
  static const storageKey = 'recall_next_workspace_v1';
  static const maxBytes = 1024 * 1024;
  final FlutterSecureStorage _storage;

  @override
  Future<RecallWorkspace?> load() async {
    final value = await _storage.read(key: storageKey);
    if (value == null) return null;
    return RecallWorkspace.fromJson(
      Map<String, dynamic>.from(jsonDecode(value) as Map),
    );
  }

  @override
  Future<void> save(RecallWorkspace workspace) async {
    final value = jsonEncode(workspace.toJson());
    if (utf8.encode(value).length > maxBytes) {
      throw StateError(
        'Local storage is full. Export your work before adding more sources.',
      );
    }
    await _storage.write(key: storageKey, value: value);
  }
}

class MemoryRecallRepository implements RecallRepository {
  RecallWorkspace? _value;
  @override
  Future<RecallWorkspace?> load() async => _value;
  @override
  Future<void> save(RecallWorkspace workspace) async {
    _value = workspace;
  }
}

typedef InMemoryRecallRepository = MemoryRecallRepository;
