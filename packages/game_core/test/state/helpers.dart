import 'dart:convert';
import 'dart:io';

import 'package:game_core/game_core.dart';

/// Loads the shipped content from the repo root.
Content shippedContent() {
  final bundle = {
    for (final f in Directory('../../content').listSync().whereType<File>())
      if (f.path.endsWith('.json'))
        f.uri.pathSegments.last.replaceAll('.json', ''): jsonDecode(
          f.readAsStringSync(),
        ),
  };
  return (Content.fromBundle(bundle) as ContentOk).content;
}
