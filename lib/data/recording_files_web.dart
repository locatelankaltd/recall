import 'dart:typed_data';

import 'package:http/http.dart' as http;

Future<String> createRecordingPath() async =>
    'debrief-${DateTime.now().microsecondsSinceEpoch}.webm';

// Browser session blobs are not persistent files. They disappear with the page.
Future<void> discardRecording(String? path) async {}

Future<String> requireOwnedRecordingPath(String path) async => throw StateError(
  'Browser recordings are available only during their original session. Restoring JSON does not restore audio files.',
);

Future<Uint8List> readRecordingBytes(String path) async {
  final uri = Uri.parse(path);
  if (uri.scheme != 'blob') {
    throw StateError('The browser recording is not available.');
  }
  final response = await http.get(uri);
  if (response.statusCode != 200) {
    throw StateError('The browser recording could not be downloaded.');
  }
  return response.bodyBytes;
}
