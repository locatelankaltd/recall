import 'dart:collection';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:recall_next/platform/incoming_share_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('recall/incoming_share_test');
  const codec = StandardMethodCodec();
  final nativeQueue = Queue<Object>();
  late IncomingShareService service;
  var nativeReads = 0;

  Map<String, Object> text(String id, String value) => {
    'id': id,
    'status': 'text',
    'text': value,
  };

  Future<void> notifyNativeShare() async {
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
          channel.name,
          codec.encodeMethodCall(const MethodCall('onShareAvailable')),
          (_) {},
        );
  }

  setUp(() {
    nativeQueue.clear();
    nativeReads = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          expect(call.method, 'getInitialShare');
          nativeReads++;
          return nativeQueue.isEmpty ? null : nativeQueue.removeFirst();
        });
    service = IncomingShareService(channel: channel, platformSupported: true);
  });

  tearDown(() {
    service.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test(
    'cold start preserves multilingual source until explicitly taken',
    () async {
      const original =
          '  நாளை 16:00 · mañana · demain\nhttps://example.test/a  ';
      nativeQueue.add(text('cold', original));
      await service.start();
      expect(service.pending.value!.text, original);
      expect(service.pending.value!.hasText, isTrue);
      await service.start();
      expect(nativeReads, 2); // One payload and the native queue terminator.
      expect(service.take()!.text, original);
      expect(service.pending.value, isNull);
      expect(service.take(), isNull);
    },
  );

  test(
    'running shares queue, dedupe by delivery id, and clear individually',
    () async {
      await service.start();
      nativeQueue.addAll([
        text('live-1', 'First message'),
        text('live-1', 'A replay must never overwrite the first message'),
        text(
          'live-2',
          'First message',
        ), // A deliberate second share is allowed.
      ]);
      await notifyNativeShare();
      expect(service.pending.value!.id, 'live-1');
      service.clear();
      expect(service.pending.value!.id, 'live-2');
      expect(service.take()!.text, 'First message');
      expect(service.pending.value, isNull);
    },
  );

  test(
    'enforces the UTF-8 byte cap without truncating or returning text',
    () async {
      nativeQueue.addAll([
        text('boundary', 'a' * IncomingShareService.maxTextBytes),
        text('multibyte', 'é' * (IncomingShareService.maxTextBytes ~/ 2 + 1)),
        text('oversized', 'a' * (IncomingShareService.maxTextBytes + 1)),
      ]);
      await service.start();
      expect(service.take()!.text!.length, IncomingShareService.maxTextBytes);
      for (var index = 0; index < 2; index++) {
        final share = service.take()!;
        expect(share.issue, IncomingShareIssue.tooLarge);
        expect(share.text, isNull);
        expect(share.hasText, isFalse);
      }
    },
  );

  test(
    'unsupported files, empty text, and malformed extras are explicit issues',
    () async {
      nativeQueue.addAll([
        {'id': 'uri', 'status': 'unsupported'},
        text('blank', ' \n\t'),
        {'id': 'bad', 'status': 'text', 'text': 42},
        {'id': 'unknown', 'status': 'future-status'},
      ]);
      await service.start();
      expect(service.take()!.issue, IncomingShareIssue.unsupported);
      expect(service.take()!.issue, IncomingShareIssue.empty);
      expect(service.take()!.issue, IncomingShareIssue.invalidPayload);
      expect(service.take()!.issue, IncomingShareIssue.invalidPayload);
      expect(service.pending.value, isNull);
    },
  );

  test(
    'bounds inbox memory and reports overflow after existing shares',
    () async {
      nativeQueue.addAll(
        List.generate(20, (i) => text('share-$i', 'Message $i')),
      );
      await service.start();
      for (var i = 0; i < IncomingShareService.maxPendingShares; i++) {
        expect(service.take()!.text, 'Message $i');
      }
      expect(service.take()!.issue, IncomingShareIssue.queueFull);
      expect(service.take(), isNull);
      nativeQueue.add(text('after-overflow', 'Later message'));
      await notifyNativeShare();
      expect(service.take()!.text, 'Later message');
    },
  );

  test(
    'does not register or call a native receiver on unsupported platforms',
    () async {
      service.dispose();
      service = IncomingShareService(
        channel: channel,
        platformSupported: false,
      );
      await service.start();
      expect(service.isSupported, isFalse);
      expect(nativeReads, 0);
      expect(service.pending.value, isNull);
    },
  );

  test('native error details cannot become displayed source text', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async {
          throw PlatformException(
            code: 'invalid',
            message: 'Private sender text',
          );
        });
    await service.start();
    final share = service.take()!;
    expect(share.issue, IncomingShareIssue.invalidPayload);
    expect(share.text, isNull);
  });
}
