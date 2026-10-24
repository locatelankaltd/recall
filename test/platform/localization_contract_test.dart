import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:recall_next/l10n/strings.dart';

void main() {
  test(
    'English, Spanish and French expose the same nonempty interface keys',
    () {
      expect(strings.keys.toSet(), {'en', 'es', 'fr'});
      final englishKeys = strings['en']!.keys.toSet();
      for (final locale in strings.keys) {
        expect(strings[locale]!.keys.toSet(), englishKeys, reason: locale);
        expect(
          strings[locale]!.values.every((value) => value.trim().isNotEmpty),
          isTrue,
        );
      }
    },
  );

  test(
    'editor fallback labels and literal translation keys exist in every locale',
    () {
      final keyPattern = RegExp(r"(?:tr|trParams)\([^,]+,\s*'([^']+)'");
      final editorPattern = RegExp(r"_t\(\s*'([^']+)'");
      final usedKeys = <String>{};
      for (final file in Directory(
        'lib',
      ).listSync(recursive: true).whereType<File>()) {
        if (!file.path.endsWith('.dart') ||
            file.path.endsWith('strings.dart')) {
          continue;
        }
        final source = file.readAsStringSync();
        usedKeys.addAll(
          keyPattern.allMatches(source).map((match) => match.group(1)!),
        );
        usedKeys.addAll(
          editorPattern.allMatches(source).map((match) => match.group(1)!),
        );
      }
      for (final locale in strings.keys) {
        expect(
          usedKeys.difference(strings[locale]!.keys.toSet()),
          isEmpty,
          reason: locale,
        );
      }
    },
  );

  test('parameter placeholders match across supported interface languages', () {
    final placeholder = RegExp(r'\{[A-Za-z]+\}');
    for (final key in strings['en']!.keys) {
      final expected = placeholder
          .allMatches(strings['en']![key]!)
          .map((match) => match[0])
          .toSet();
      for (final locale in ['es', 'fr']) {
        expect(
          placeholder
              .allMatches(strings[locale]![key]!)
              .map((match) => match[0])
              .toSet(),
          expected,
          reason: '$locale:$key',
        );
      }
    }
  });
}
