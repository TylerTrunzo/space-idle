import 'dart:convert';

import 'package:game_core/game_core.dart';
import 'package:test/test.dart';

import '../state/helpers.dart';

BigNum n(num v) => BigNum.from(v);

void main() {
  final content = shippedContent();
  final e = GameEngine(content);

  /// A new game with [credits], Hollow Reach the player's too.
  GameState game({num credits = 1e4}) {
    final s = e.newGame(1)..faction('player').credits = n(credits);
    s.body('hollow_reach').ownerId = 'player';
    return s;
  }

  String encode(GameState s) => jsonEncode(s.toJson());

  /// The shipped content with the mine's speed and capacity levels
  /// starting at [speed] and [capacity] credits.
  Content withMineUpgrades({required num speed, required num capacity}) {
    final bundle = shippedBundle();
    final buildings = [
      for (final d in bundle['buildings']! as List)
        Map<String, Object?>.of(d as Map<String, Object?>),
    ];
    buildings.firstWhere((d) => d['id'] == 'mine')['upgrades'] = {
      'speed': {'baseCredits': '$speed', 'growth': 1.17},
      'capacity': {'baseCredits': '$capacity', 'growth': 1.17},
    };
    bundle['buildings'] = buildings;
    return (Content.fromBundle(bundle) as ContentOk).content;
  }

  /// Applies [cmd], expects success, and returns its [UpgradesBought].
  UpgradesBought bought(GameState s, BuyUpgradesCommand cmd, {Content? c}) {
    final r = applyCommand(s, c ?? content, cmd);
    expect(r, isA<CommandOk>(), reason: r is CommandFailed ? r.message : '');
    final o = (r as CommandOk).outcome;
    expect(o, isA<UpgradesBought>());
    return o! as UpgradesBought;
  }

  /// The reference: single [UpgradeCommand]s, each the cheapest level any
  /// owned building can still take (ties by building id, then track
  /// order), while the total stays within [budget]; at most [max].
  /// Returns the commands applied, in order.
  List<UpgradeCommand> oneByOne(
    GameState s,
    BigNum budget, {
    int max = 2000,
    Content? c,
  }) {
    final cc = c ?? content;
    final done = <UpgradeCommand>[];
    var spent = const BigNum.zero();
    final limit = budget.min(s.faction('player').credits);
    while (done.length < max) {
      (BigNum, String, UpgradeTrack)? best;
      for (final body in s.bodies.where((b) => b.ownerId == 'player')) {
        for (final b in body.buildings) {
          for (final t in UpgradeTrack.values) {
            if (!cc.buildings[b.defId]!.upgrades.containsKey(t)) continue;
            if (upgradeMaxedReason(cc, b, t) != null) continue;
            final cost = upgradeCost(cc, b, t)['credits']!;
            final key = (cost, b.id, t);
            if (best == null ||
                cost < best.$1 ||
                (cost == best.$1 &&
                    (b.id.compareTo(best.$2) < 0 ||
                        (b.id == best.$2 && t.index < best.$3.index)))) {
              best = key;
            }
          }
        }
      }
      if (best == null || spent + best.$1 > limit) break;
      final cmd = UpgradeCommand('player', best.$2, best.$3);
      final r = applyCommand(s, cc, cmd);
      expect(r, isA<CommandOk>());
      spent = spent + best.$1;
      done.add(cmd);
    }
    return done;
  }

  group('buyUpgrades', () {
    test('a budget below the cheapest upgrade buys nothing, and says what '
        'the next one costs', () {
      final s = game();
      final before = encode(s);
      // The cheapest level in a new game is a mine's first speed level.
      final o = bought(s, BuyUpgradesCommand('player', n(49)));
      expect(o.purchases, isEmpty);
      expect(o.levels, 0);
      expect(o.total, const BigNum.zero());
      expect(o.spent, isEmpty);
      expect(o.stop, UpgradeBuyStop.budget);
      expect(o.nextCost, n(50));
      expect(o.bodyId, isNull);
      expect(encode(s), before);
    });

    test('a budget of zero buys nothing', () {
      final s = game();
      final o = bought(s, BuyUpgradesCommand('player', n(0)));
      expect(o.purchases, isEmpty);
      expect(o.stop, UpgradeBuyStop.budget);
    });

    test('buys cheapest first, as a loop of single upgrades would', () {
      for (final budget in [50, 51, 125, 2000, 9999]) {
        final a = game();
        final b = game();
        final o = bought(a, BuyUpgradesCommand('player', n(budget)));
        final ref = oneByOne(b, n(budget));
        expect(encode(a), encode(b), reason: 'budget $budget');
        expect(o.levels, ref.length);
        expect(o.levels, greaterThan(0));
        expect(o.purchases.fold(0, (t, p) => t + p.levels), ref.length);
        // Grouped by building and track, in the order first bought.
        final groups = <(String, UpgradeTrack), int>{};
        for (final c in ref) {
          groups.update(
            (c.buildingId, c.track),
            (v) => v + 1,
            ifAbsent: () => 1,
          );
        }
        expect(
          [for (final p in o.purchases) ((p.buildingId, p.track), p.levels)],
          [for (final g in groups.entries) (g.key, g.value)],
        );
        expect(o.stop, UpgradeBuyStop.budget);
      }
    });

    test('matches the loop on a played mid-game state', () {
      final s = game(credits: 1e3);
      e.advance(s, 3600);
      // Buildings and habitats to choose between, with free crew to move
      // into new capacity slots.
      for (final def in ['smelter', 'wire_mill', 'mine', 'habitat']) {
        s.body('kora').stock['habitat_module'] = n(5);
        s.faction('player').credits = n(1e5);
        applyCommand(
          s,
          content,
          BuildCommand(
            'player',
            'kora',
            def,
            depositResourceId: def == 'mine' ? 'iron_ore' : null,
          ),
        );
      }
      s.faction('player')
        ..baseCrew = 40
        ..credits = n(5e6);
      final a = s.copy();
      final b = s.copy();
      final o = bought(a, BuyUpgradesCommand('player', n(3e6)));
      oneByOne(b, n(3e6));
      expect(encode(a), encode(b));
      // Habitats' capacity; on a building with speed too, capacity shares
      // speed's counter at a higher base, so speed always comes first.
      expect(
        o.purchases.where((p) => p.track == UpgradeTrack.capacity),
        isNotEmpty,
      );
    });

    test('a capacity level fills its new slot from free crew, as a single '
        'upgrade does', () {
      final c = withMineUpgrades(speed: 50, capacity: 40);
      final a = newGameState(c, 1)..faction('player').credits = n(1e4);
      final b = a.copy();
      final o = bought(a, BuyUpgradesCommand('player', n(500)), c: c);
      oneByOne(b, n(500), c: c);
      expect(encode(a), encode(b));
      expect(o.purchases.first.track, UpgradeTrack.capacity);
      expect(o.purchases.first.crewAdded, o.purchases.first.levels);
      expect(o.purchases.first.crewAdded, greaterThan(0));
    });

    test('never spends above the budget or the credits held', () {
      for (final (credits, budget) in [
        (1e4, 3e3),
        (2e3, 1e9),
        (777.5, 777.5),
      ]) {
        final s = game(credits: credits);
        final o = bought(s, BuyUpgradesCommand('player', n(budget)));
        final limit = n(budget).min(n(credits));
        expect(o.total, lessThanOrEqualTo(limit));
        expect(o.total, greaterThan(const BigNum.zero()));
        expect(o.spent, {'credits': o.total});
        expect(
          o.purchases.fold(const BigNum.zero(), (t, p) => t + p.cost),
          o.total,
        );
        final left = s.faction('player').credits;
        expect(left, greaterThanOrEqualTo(const BigNum.zero()));
        expect((n(credits) - o.total - left).toDouble().abs(), lessThan(1e-6));
        // Stopped because the next level would not fit.
        expect(o.stop, UpgradeBuyStop.budget);
        expect(o.total + o.nextCost!, greaterThan(limit));
      }
    });

    test('a huge budget stops at maxPurchases', () {
      final s = game(credits: 1e300);
      final o = bought(
        s,
        BuyUpgradesCommand('player', BigNum.parse('1e300'), maxPurchases: 25),
      );
      expect(o.levels, 25);
      expect(o.stop, UpgradeBuyStop.maxPurchases);
      expect(o.nextCost, isNotNull);
      final all = bought(
        game(credits: 1e300),
        BuyUpgradesCommand('player', BigNum.parse('1e300')),
      );
      expect(all.levels, BuyUpgradesCommand.defaultMaxPurchases);
      expect(all.stop, UpgradeBuyStop.maxPurchases);
    });

    test('is deterministic', () {
      final a = game(credits: 1e7);
      final b = game(credits: 1e7);
      final oa = bought(a, BuyUpgradesCommand('player', n(5e6)));
      final ob = bought(b, BuyUpgradesCommand('player', n(5e6)));
      expect(encode(a), encode(b));
      expect(
        [for (final p in oa.purchases) (p.buildingId, p.track, p.levels)],
        [for (final p in ob.purchases) (p.buildingId, p.track, p.levels)],
      );
    });

    test('ties go by building id, then track', () {
      // A mine whose capacity level costs what its speed level does.
      final c = withMineUpgrades(speed: 50, capacity: 50);
      final s = newGameState(c, 1)..faction('player').credits = n(1e4);
      final mines = [
        for (final b in s.body('kora').buildings)
          if (b.defId == 'mine') b.id,
      ]..sort();
      expect(mines.length, greaterThanOrEqualTo(1));
      final o = bought(s, BuyUpgradesCommand('player', n(50)), c: c);
      expect(o.purchases.single.buildingId, mines.first);
      expect(o.purchases.single.track, UpgradeTrack.speed);
    });

    test('skips maxed tracks and buildings on bodies the faction does not '
        'own', () {
      final s = game(credits: 1e30);
      final smelter = s.bodies
          .expand((b) => b.buildings)
          .firstWhere((b) => b.defId == 'smelter');
      // At the efficiency floor: maxed.
      smelter.levels[UpgradeTrack.efficiency] = 28;
      expect(
        upgradeMaxedReason(content, smelter, UpgradeTrack.efficiency),
        isNotNull,
      );
      final r = applyCommand(
        s,
        content,
        BuildCommand(
          'player',
          'hollow_reach',
          'mine',
          depositResourceId: 'nickel',
        ),
      );
      expect(r, isA<CommandOk>());
      s.body('hollow_reach').ownerId = 'rival';
      final rivalIds = {for (final b in s.body('hollow_reach').buildings) b.id};
      expect(rivalIds, isNotEmpty);
      final o = bought(
        s,
        BuyUpgradesCommand('player', n(1e30), maxPurchases: 300),
      );
      for (final p in o.purchases) {
        expect(rivalIds, isNot(contains(p.buildingId)));
        expect(
          p.buildingId == smelter.id && p.track == UpgradeTrack.efficiency,
          isFalse,
        );
      }
    });

    test('with nothing left to upgrade it says so', () {
      final s = game(credits: 1e30);
      for (final body in s.bodies) {
        body.ownerId = body.ownerId == 'player' ? 'rival' : body.ownerId;
      }
      final o = bought(s, BuyUpgradesCommand('player', n(1e9)));
      expect(o.purchases, isEmpty);
      expect(o.stop, UpgradeBuyStop.nothingToBuy);
      expect(o.nextCost, isNull);
    });

    test('a negative budget or a purchase cap out of range is refused', () {
      for (final cmd in [
        BuyUpgradesCommand('player', n(-1)),
        BuyUpgradesCommand('player', n(100), maxPurchases: 0),
        BuyUpgradesCommand(
          'player',
          n(100),
          maxPurchases: BuyUpgradesCommand.defaultMaxPurchases + 1,
        ),
      ]) {
        final s = game();
        final before = encode(s);
        final r = applyCommand(s, content, cmd);
        expect(
          r,
          isA<CommandFailed>().having(
            (f) => f.error,
            'error',
            CommandError.invalidAmount,
          ),
        );
        expect(encode(s), before);
      }
      final r = applyCommand(game(), content, BuyUpgradesCommand('x', n(1)));
      expect(
        r,
        isA<CommandFailed>().having(
          (f) => f.error,
          'error',
          CommandError.unknownFaction,
        ),
      );
    });

    test('round-trips through JSON; maxPurchases defaults when absent', () {
      final cmd = BuyUpgradesCommand('player', n(1.5e9), maxPurchases: 40);
      final json = jsonDecode(jsonEncode(cmd.toJson())) as Map<String, Object?>;
      expect(json['cmd'], 'buyUpgrades');
      final back = Command.fromJson(json) as BuyUpgradesCommand;
      expect(back.toJson(), cmd.toJson());
      final plain =
          Command.fromJson({
                'cmd': 'buyUpgrades',
                'factionId': 'player',
                'budget': '100',
              })
              as BuyUpgradesCommand;
      expect(plain.maxPurchases, BuyUpgradesCommand.defaultMaxPurchases);
      expect(plain.budget, n(100));
    });
  });
}
