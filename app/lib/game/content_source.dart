import 'dart:convert';

import 'package:game_core/game_core.dart';
import 'package:space_idle/generated/content_bundle.g.dart';

/// Decodes and validates the content bundle embedded in the app.
///
/// [source] maps each content file stem to its JSON text; it defaults to the
/// generated [contentJson] and is a parameter only so tests can feed a broken
/// bundle. Throws a [StateError] listing every problem when a file is not
/// valid JSON or the validator rejects the bundle: shipped content is a build
/// input, so a bad bundle is a bug, not a runtime condition to recover from.
Content loadEmbeddedContent({Map<String, String> source = contentJson}) {
  final bundle = <String, Object?>{};
  for (final MapEntry(key: stem, value: text) in source.entries) {
    try {
      bundle[stem] = jsonDecode(text);
    } on FormatException catch (e) {
      throw StateError('$stem.json is not valid JSON: ${e.message}');
    }
  }
  return switch (Content.fromBundle(bundle)) {
    ContentOk(:final content) => content,
    ContentInvalid(:final errors) => throw StateError(
      'Embedded content is invalid:\n${errors.join('\n')}',
    ),
  };
}
