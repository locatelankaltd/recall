import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:recall_next/data/recording_files_native.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  late Directory documents;
  setUp(() async {
    documents = await Directory.systemTemp.createTemp('recall-audio-test-');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'getApplicationDocumentsDirectory') {
            return documents.path;
          }
          return null;
        });
  });
  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    await documents.delete(recursive: true);
  });

  test('only an existing nonempty owned recording can be exported', () async {
    final path = await createRecordingPath();
    await File(path).writeAsBytes([0, 1, 2]);
    expect(await requireOwnedRecordingPath(path), path);
    expect(await readRecordingBytes(path), [0, 1, 2]);
    await discardRecording(path);
    await expectLater(requireOwnedRecordingPath(path), throwsStateError);
  });

  test(
    'portable, traversal and empty paths cannot authorize file export',
    () async {
      final outside = File('${documents.path}/debrief-123.m4a');
      await outside.writeAsBytes([1]);
      for (final path in [
        outside.path,
        '${documents.path}/recall-audio/../debrief-123.m4a',
        '${documents.path}/recall-audio/debrief-123.m4a',
        '/another-device/recall-audio/debrief-123.m4a',
      ]) {
        await expectLater(requireOwnedRecordingPath(path), throwsStateError);
      }
      final empty = await createRecordingPath();
      await File(empty).writeAsBytes([]);
      await expectLater(requireOwnedRecordingPath(empty), throwsStateError);
      await discardRecording(outside.path);
      expect(await outside.exists(), isTrue);
    },
  );

  test(
    'symlink files and symlink audio directories cannot grant file access',
    () async {
      final outside = File('${documents.path}/outside.m4a');
      await outside.writeAsBytes([1]);
      final directory = Directory('${documents.path}/recall-audio');
      await directory.create();
      final linkedFile = Link('${directory.path}/debrief-123.m4a');
      await linkedFile.create(outside.path);
      await expectLater(
        requireOwnedRecordingPath(linkedFile.path),
        throwsStateError,
      );
      await linkedFile.delete();
      await directory.delete();
      final other = Directory('${documents.path}/other-audio');
      await other.create();
      await File('${other.path}/debrief-456.m4a').writeAsBytes([1]);
      await Link(directory.path).create(other.path);
      await expectLater(
        requireOwnedRecordingPath('${directory.path}/debrief-456.m4a'),
        throwsStateError,
      );
      await discardRecording('${directory.path}/debrief-456.m4a');
      expect(await File('${other.path}/debrief-456.m4a').exists(), isTrue);
    },
  );
}
