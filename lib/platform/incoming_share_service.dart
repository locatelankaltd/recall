import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

enum IncomingShareIssue {
  tooLarge,
  unsupported,
  empty,
  invalidPayload,
  queueFull,
}

/// Untrusted content chosen in another app's Android share sheet.
///
/// Receiving a share is not permission to save it, send it, or fetch any URL.
/// The caller must ask the user to choose a project and review the text first.
class IncomingShare {
  const IncomingShare({required this.id, this.text, this.issue});

  final String id;
  final String? text;
  final IncomingShareIssue? issue;

  bool get hasText => issue == null && text != null;
}

/// A volatile inbox for Android ACTION_SEND text/plain intents.
///
/// This service does no disk writes, URI reads, networking, or text logging.
/// [take] transfers the current share to a review flow; [clear] dismisses it.
/// Neither operation stores source content. iOS has no receiving extension yet.
class IncomingShareService {
  IncomingShareService({
    this.channel = const MethodChannel('recall/incoming_share'),
    bool? platformSupported,
  }) : _platformSupported =
           platformSupported ??
           (!kIsWeb && defaultTargetPlatform == TargetPlatform.android);

  static const maxTextBytes = 1024 * 1024;
  static const maxPendingShares = 4;

  final MethodChannel channel;
  final bool _platformSupported;
  final _queue = Queue<IncomingShare>();
  final _seenIds = <String>{};
  final _pending = ValueNotifier<IncomingShare?>(null);
  Future<void>? _starting;
  Future<void>? _draining;
  bool _drainAgain = false;
  bool _disposed = false;
  bool _overflowReported = false;
  int _localId = 0;

  bool get isSupported => _platformSupported;
  ValueListenable<IncomingShare?> get pending => _pending;

  /// Registers live delivery before draining the native launch-intent queue.
  /// Safe to call more than once; queued payloads are taken from native once.
  Future<void> start() {
    if (_disposed || !_platformSupported) return Future<void>.value();
    return _starting ??= _start();
  }

  Future<void> _start() async {
    channel.setMethodCallHandler((call) async {
      if (call.method == 'onShareAvailable' && !_disposed) await _drain();
    });
    await _drain();
  }

  Future<void> _drain() {
    if (_disposed) return Future<void>.value();
    if (_draining != null) {
      _drainAgain = true;
      return _draining!;
    }
    final completer = Completer<void>();
    _draining = completer.future;
    () async {
      try {
        do {
          _drainAgain = false;
          Object? payload;
          do {
            payload = await channel.invokeMethod<Object?>('getInitialShare');
            if (_disposed) break;
            if (payload != null) _receive(payload);
          } while (payload != null);
        } while (_drainAgain && !_disposed);
      } on MissingPluginException {
        // No receiving extension is installed on this build/platform.
        if (!_disposed) _receiveIssue(IncomingShareIssue.unsupported);
      } on PlatformException {
        // Exception details can contain sender data; never log or expose them.
        if (!_disposed) _receiveIssue(IncomingShareIssue.invalidPayload);
      } finally {
        _draining = null;
        completer.complete();
      }
    }();
    return completer.future;
  }

  void _receive(Object payload) {
    if (payload is! Map) {
      _receiveIssue(IncomingShareIssue.invalidPayload);
      return;
    }
    final id = payload['id'];
    if (id is! String || id.isEmpty || id.length > 128) {
      _receiveIssue(IncomingShareIssue.invalidPayload);
      return;
    }
    if (!_seenIds.add(id)) return;
    if (_seenIds.length > 256) _seenIds.remove(_seenIds.first);
    final status = payload['status'];
    if (status != 'text') {
      final issue = switch (status) {
        'tooLarge' => IncomingShareIssue.tooLarge,
        'unsupported' => IncomingShareIssue.unsupported,
        'empty' => IncomingShareIssue.empty,
        'queueFull' => IncomingShareIssue.queueFull,
        _ => IncomingShareIssue.invalidPayload,
      };
      _enqueue(IncomingShare(id: id, issue: issue));
      return;
    }
    final text = payload['text'];
    if (text is! String) {
      _enqueue(IncomingShare(id: id, issue: IncomingShareIssue.invalidPayload));
    } else if (text.length > maxTextBytes ||
        utf8.encode(text).length > maxTextBytes) {
      _enqueue(IncomingShare(id: id, issue: IncomingShareIssue.tooLarge));
    } else if (text.trim().isEmpty) {
      _enqueue(IncomingShare(id: id, issue: IncomingShareIssue.empty));
    } else {
      _enqueue(IncomingShare(id: id, text: text));
    }
  }

  void _receiveIssue(IncomingShareIssue issue) =>
      _enqueue(IncomingShare(id: 'local-${_localId++}', issue: issue));

  void _enqueue(IncomingShare share) {
    if (_queue.length >= maxPendingShares) {
      if (!_overflowReported) {
        _overflowReported = true;
        _queue.add(
          IncomingShare(
            id: 'overflow-${_localId++}',
            issue: IncomingShareIssue.queueFull,
          ),
        );
      }
      return;
    }
    _queue.add(share);
    _pending.value = _queue.first;
  }

  IncomingShare? take() {
    if (_disposed || _queue.isEmpty) return null;
    final share = _queue.removeFirst();
    _pending.value = _queue.isEmpty ? null : _queue.first;
    if (_queue.isEmpty) _overflowReported = false;
    return share;
  }

  void clear() => take();

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    if (_platformSupported) channel.setMethodCallHandler(null);
    _queue.clear();
    _seenIds.clear();
    _pending.dispose();
  }
}
