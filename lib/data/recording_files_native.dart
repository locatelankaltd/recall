import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

Future<String> createRecordingPath() async {
  final documents = await getApplicationDocumentsDirectory();
  final directory = Directory('${documents.path}/recall-audio');
  await directory.create(recursive: true);
  return '${directory.path}/debrief-${DateTime.now().microsecondsSinceEpoch}.m4a';
}

Future<void> discardRecording(String? path) async {
  if (path == null) return;
  final documents = await getApplicationDocumentsDirectory();
  final prefix = '${documents.path}/recall-audio/';
  if (!path.startsWith(prefix) ||
      !RegExp(r'^debrief-\d+\.m4a$').hasMatch(path.substring(prefix.length))) {
    return;
  }
  final directory = Directory('${documents.path}/recall-audio');
  if (await FileSystemEntity.type(directory.path, followLinks: false) !=
          FileSystemEntityType.directory ||
      await directory.resolveSymbolicLinks() !=
          '${await documents.resolveSymbolicLinks()}/recall-audio' ||
      await FileSystemEntity.type(path, followLinks: false) !=
          FileSystemEntityType.file) {
    return;
  }
  final file = File(path);
  if (await file.exists()) await file.delete();
}

/// Rejects portable backup paths, symlinks and files outside this app's audio
/// folder before a native share flow receives a path. JSON is not a file grant.
Future<String> requireOwnedRecordingPath(String path) async {
  final documents = await getApplicationDocumentsDirectory();
  final directory = Directory('${documents.path}/recall-audio');
  final prefix = '${directory.path}/';
  if (!path.startsWith(prefix) ||
      !RegExp(r'^debrief-\d+\.m4a$').hasMatch(path.substring(prefix.length))) {
    throw StateError(
      'This recording is not available on this device. Restoring JSON does not restore audio files.',
    );
  }
  final file = File(path);
  if (await FileSystemEntity.type(path, followLinks: false) !=
      FileSystemEntityType.file) {
    throw StateError(
      'This recording is missing or was moved. Restoring JSON does not restore audio files.',
    );
  }
  try {
    // Permit OS ancestor aliases such as /var -> /private/var while checking
    // the app's own audio folder has not been replaced with a symlink.
    final expectedDirectory =
        '${await documents.resolveSymbolicLinks()}/recall-audio';
    final filename = path.substring(prefix.length);
    if (await FileSystemEntity.type(directory.path, followLinks: false) !=
            FileSystemEntityType.directory ||
        await directory.resolveSymbolicLinks() != expectedDirectory ||
        await file.resolveSymbolicLinks() != '$expectedDirectory/$filename') {
      throw const FileSystemException('Audio path is not owned');
    }
    final handle = await file.open();
    try {
      if (await handle.length() <= 0) {
        throw const FileSystemException('Audio file is empty');
      }
      await handle.read(1);
    } finally {
      await handle.close();
    }
  } on FileSystemException {
    throw StateError('This recording could not be opened on this device.');
  }
  return file.path;
}

Future<Uint8List> readRecordingBytes(String path) async =>
    File(await requireOwnedRecordingPath(path)).readAsBytes();
