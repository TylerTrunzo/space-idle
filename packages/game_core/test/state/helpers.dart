import 'dart:convert';
import 'dart:io';

import 'package:game_core/game_core.dart';

/// The shipped content files from the repo root, decoded, keyed by file
/// name without `.json`.
Map<String, Object?> shippedBundle() => {
  for (final f in Directory('../../content').listSync().whereType<File>())
    if (f.path.endsWith('.json'))
      f.uri.pathSegments.last.replaceAll('.json', ''): jsonDecode(
        f.readAsStringSync(),
      ),
};

/// Loads the shipped content from the repo root.
Content shippedContent() =>
    (Content.fromBundle(shippedBundle()) as ContentOk).content;
