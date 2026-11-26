import 'dart:convert';
import 'dart:io';

/// Content file stems the validator knows; other files are ignored because
/// the validator rejects unknown bundle keys.
const List<String> contentStems = [
  'rules',
  'resources',
  'buildings',
  'body_types',
  'galaxy',
  'milestones',
  'megaprojects',
];

/// Reads the known content files from directory [path] into a bundle keyed
/// by file stem, for `Content.fromBundle`.
///
/// A missing file is left out of the bundle so the validator reports it
/// (`megaprojects` is optional: without it there are none).
/// Throws [FormatException] if a present file is not valid JSON.
Map<String, Object?> loadContentDir(String path) {
  final bundle = <String, Object?>{};
  for (final stem in contentStems) {
    final file = File('$path/$stem.json');
    if (!file.existsSync()) continue;
    try {
      bundle[stem] = jsonDecode(file.readAsStringSync());
    } on FormatException catch (e) {
      throw FormatException('$stem.json: ${e.message}');
    }
  }
  return bundle;
}
