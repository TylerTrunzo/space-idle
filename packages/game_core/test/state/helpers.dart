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

/// [shippedBundle] as the saved fixtures under `test/fixtures` were played
/// with, before stage 1.7 task 4's retune: the Orbital Station's 5e6
/// credits ×2.5 a level, the Mass Driver's 2e6 ×2.3, and habitat capacity
/// ×1.2 a level. A save holds megaproject progress only up to its stage's
/// cost, so those states load, and play as they did, only with these.
Map<String, Object?> fixtureBundle() {
  final b = shippedBundle();
  for (final m in (b['megaprojects']! as List).cast<Map<String, Object?>>()) {
    final (credits, growth) = switch (m['id']) {
      'orbital_station' => ('5e6', 2.5),
      'mass_driver' => ('2e6', 2.3),
      _ => (null, null),
    };
    if (credits == null) continue;
    (m['baseCost']! as Map<String, Object?>)['credits'] = credits;
    m['costGrowth'] = growth;
  }
  for (final d in (b['buildings']! as List).cast<Map<String, Object?>>()) {
    if (d['id'] != 'habitat') continue;
    final ups = d['upgrades']! as Map<String, Object?>;
    (ups['capacity']! as Map<String, Object?>)['growth'] = 1.2;
  }
  return b;
}

/// [fixtureBundle], loaded.
Content fixtureContent() =>
    (Content.fromBundle(fixtureBundle()) as ContentOk).content;
