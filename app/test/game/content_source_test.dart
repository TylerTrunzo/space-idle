import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:game_core/game_core.dart';
import 'package:space_idle/game/content_source.dart';
import 'package:space_idle/generated/content_bundle.g.dart';

/// Every `content/*.json` at the repo root, by file stem, as raw text.
///
/// `flutter test` runs with `app/` as the working directory.
Map<String, String> _contentOnDisk() => {
  for (final f in Directory('../content').listSync().whereType<File>())
    if (f.path.endsWith('.json'))
      f.uri.pathSegments.last.replaceAll('.json', ''): f.readAsStringSync(),
};

void main() {
  test('contentJson matches content/*.json on disk '
      '(run `dart run tool/embed_content.dart` after editing content)', () {
    final disk = _contentOnDisk();
    expect(disk, isNotEmpty);
    expect(contentJson.keys.toSet(), disk.keys.toSet());
    for (final stem in disk.keys) {
      expect(contentJson[stem], disk[stem], reason: '$stem.json is stale');
    }
  });

  test('loadEmbeddedContent has every galaxy body, 5 of them visible', () {
    final content = loadEmbeddedContent();
    final galaxy =
        jsonDecode(_contentOnDisk()['galaxy']!) as Map<String, Object?>;
    final expectedIds = [
      for (final s in galaxy['systems']! as List<Object?>)
        for (final b
            in (s! as Map<String, Object?>)['bodies']! as List<Object?>)
          (b! as Map<String, Object?>)['id']! as String,
    ];
    final bodies = [for (final s in content.galaxy.systems) ...s.bodies];
    expect(bodies.map((b) => b.id), expectedIds);
    expect(bodies.where((b) => !b.hidden), hasLength(5));
    expect(bodies.where((b) => b.hidden), isNotEmpty);
  });

  test('loadEmbeddedContent throws StateError listing validator errors', () {
    final broken = Map<String, String>.of(contentJson)..['rules'] = '{}';
    expect(
      () => loadEmbeddedContent(source: broken),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          startsWith('Embedded content is invalid'),
        ),
      ),
    );
  });

  test('loadEmbeddedContent throws StateError on malformed JSON', () {
    final broken = Map<String, String>.of(contentJson)..['rules'] = '{';
    expect(
      () => loadEmbeddedContent(source: broken),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('rules.json is not valid JSON'),
        ),
      ),
    );
  });

  test('the shipped bundle is valid Content', () {
    expect(loadEmbeddedContent(), isA<Content>());
  });
}
