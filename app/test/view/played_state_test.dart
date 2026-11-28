import 'package:flutter_test/flutter_test.dart';
import 'package:game_core/game_core.dart';
import 'package:space_idle/game/clock.dart';
import 'package:space_idle/game/content_source.dart';
import 'package:space_idle/game/game_controller.dart';
import 'package:space_idle/game/save_store.dart';
import 'package:space_idle/view/messages.dart';
import 'package:space_idle/view/project_views.dart';
import 'package:space_idle/view/view_models.dart';

final Content content = loadEmbeddedContent();
const _p = 'player';

/// A controller whose game has been played for [days]: every six hours a
/// simple player auto-sells what its bodies hold (keeping the claim and
/// survey goods), claims a body when it can afford one, buys a speed level
/// where it can, and leaves the rest to offline catch-up.
GameController _played(int days) {
  final c = GameController(
    content: content,
    store: MemorySaveStore(),
    clock: FakeClock(DateTime.utc(2026, 11, 27)),
    newGameSeed: 1,
  );
  const keep = {'outpost_kit', 'survey_drone', 'cargo_ship'};
  for (var turn = 0; turn < days * 4; turn++) {
    final s = c.state;
    for (final b in s.bodies.where((b) => b.ownerId == _p).toList()) {
      for (final id in b.stock.keys.toList()) {
        if (keep.contains(id)) continue;
        c.run(SetAutoSellCommand(_p, b.id, id, BigNum.zero()));
      }
      for (final bld in b.buildings.toList()) {
        c.run(UpgradeCommand(_p, bld.id, UpgradeTrack.speed));
      }
    }
    for (final b in s.bodies.where((b) => b.ownerId == null).toList()) {
      if (c.run(ClaimBodyCommand(_p, b.id, 'kora')) is CommandOk) break;
    }
    c.engine.catchUpOffline(s, 6 * 3600);
    c.tickSeconds(1); // rebuild the flow report
  }
  return c;
}

void _everyViewBuilds(GameController c) {
  final s = c.state;
  expect(topBar(c).credits, isNotEmpty);
  for (final b in s.bodies) {
    final view = bodyView(c, b.id);
    expect(view == null, !isVisible(s, b, _p), reason: b.id);
    for (final row in view?.buildings ?? const <BuildingRowView>[]) {
      expect(row.runFraction, inInclusiveRange(0, 1));
      expect(row.problem, anyOf(isNull, isNotEmpty));
    }
  }
  for (final n in [...c.flow.bottlenecks, ...c.flow.groupedBottlenecks]) {
    expect(bottleneckText(s, content, _p, n), isNotEmpty, reason: n.kind.name);
  }
  for (final p in projectViews(c)) {
    expect(p.progress, inInclusiveRange(0, 1));
  }
  expect(megaprojectViews(c), hasLength(content.megaprojects.length));
  contractViews(c);
  nextContract(c);
}

void main() {
  test('every view builds on a new game', () => _everyViewBuilds(_played(0)));

  test('every view builds after a day of play', () {
    final c = _played(1);
    expect(c.state.time, greaterThan(86400 - 1));
    _everyViewBuilds(c);
  });

  test('every view builds after 30 days of play', () {
    final c = _played(30);
    expect(
      c.state.bodies.where((b) => b.ownerId == _p).length,
      greaterThan(1),
      reason: 'the fixture should have claimed bodies',
    );
    _everyViewBuilds(c);
  }, timeout: const Timeout(Duration(minutes: 2)));
}
