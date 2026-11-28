import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:game_core/game_core.dart';
import 'package:space_idle/game/clock.dart';
import 'package:space_idle/game/content_source.dart';
import 'package:space_idle/game/game_controller.dart';
import 'package:space_idle/game/guide.dart';
import 'package:space_idle/game/save_store.dart';
import 'package:space_idle/game/settings_store.dart';
import 'package:space_idle/view/onboarding.dart';

final Content content = loadEmbeddedContent();
const _p = 'player';

void main() {
  late List<VoidCallback> fills;

  GameController controller() => GameController(
    content: content,
    store: MemorySaveStore(),
    clock: FakeClock(DateTime.utc(2026, 11, 27)),
    newGameSeed: 1,
    scheduleFill: fills.add,
  );

  setUp(() => fills = []);

  void sellSteel(GameController c) {
    c.state.body('kora').stock['steel'] = BigNum.from(10);
    c.run(SellCommand(_p, 'kora', 'steel', BigNum.from(10)));
  }

  group('Guide', () {
    test('passes a step as the game does it, and says so once', () async {
      final c = controller();
      final g = Guide(controller: c, store: MemorySettingsStore());
      await g.load();
      expect(g.step, 0);
      final done = <String?>[];
      g.lastDone.addListener(() => done.add(g.lastDone.value));
      sellSteel(c);
      expect(g.step, 1);
      expect(done, [onboardingSteps[0].title]);
      c.tickSeconds(1);
      expect(done, hasLength(1), reason: 'once');
    });

    test('steps done before it loads pass quietly', () async {
      final c = controller();
      sellSteel(c);
      final g = Guide(controller: c, store: MemorySettingsStore());
      await g.load();
      expect(g.step, 1);
      expect(g.lastDone.value, isNull);
    });

    test('its place survives a restart, in the settings', () async {
      final store = MemorySettingsStore();
      final first = controller();
      final g = Guide(controller: first, store: store);
      await g.load();
      sellSteel(first);
      await Future<void>.delayed(Duration.zero);
      expect(store.values[Guide.key], contains('"reached":1'));
      // A new session of a game that has not sold Steel since: the guide
      // does not ask again.
      final again = Guide(controller: controller(), store: store);
      await again.load();
      expect(again.step, 1);
    });

    test('Skip ends it, and the fold is kept', () async {
      final store = MemorySettingsStore();
      final g = Guide(controller: controller(), store: store);
      await g.load();
      await g.setCollapsed(true);
      await g.skip();
      expect(g.ended, isTrue);
      expect(g.step, isNull);
      final again = Guide(controller: controller(), store: store);
      await again.load();
      expect(again.collapsed, isTrue);
      expect(again.step, isNull);
    });

    test('a broken settings entry starts the guide over', () async {
      final g = Guide(
        controller: controller(),
        store: MemorySettingsStore({Guide.key: 'not json'}),
      );
      await g.load();
      expect(g.step, 0);
    });
  });

  group('bestUpgradeNow', () {
    void fillAll() {
      while (fills.isNotEmpty) {
        fills.removeAt(0)();
      }
    }

    test('searched in fills, never at the ask; it agrees with the core', () {
      final c = controller();
      c.state.faction(_p).credits = BigNum.from(5000);
      final asked = c.bestUpgradeNow();
      expect(asked.ready, isFalse);
      expect(fills, hasLength(1));
      final before = c.previewsWorkedOut;
      fillAll();
      expect(c.previewsWorkedOut, before, reason: 'its own search');
      final r = c.bestUpgradeNow();
      expect(r.ready, isTrue);
      final core = bestUpgrades(c.state, content, _p, limit: 1).firstOrNull;
      expect(r.best?.buildingId, core?.buildingId);
      expect(r.best?.track, core?.track);
      expect(r.best?.preview.paybackSeconds, core?.preview.paybackSeconds);
    });

    test('a command starts a new search; the old answer shows meanwhile', () {
      final c = controller();
      c.state.faction(_p).credits = BigNum.from(5000);
      c.bestUpgradeNow();
      fillAll();
      final old = c.bestUpgradeNow().best;
      c.run(const AssignCrewCommand(_p, 'b2', 0));
      final during = c.bestUpgradeNow();
      expect(during.ready, isTrue);
      expect(identical(during.best, old), isTrue);
      expect(fills, isNotEmpty, reason: 'a new search');
      fillAll();
      expect(identical(c.bestUpgradeNow().best, old), isFalse);
    });
  });
}
