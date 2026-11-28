import 'package:game_core/game_core.dart';
import 'package:test/test.dart';

import '../state/helpers.dart';

const _p = 'player';

void main() {
  late Content c;
  late GameEngine engine;
  late GameState s;

  setUp(() {
    c = shippedContent();
    engine = GameEngine(c);
    s = engine.newGame(1);
  });

  BuildingState building(String id) =>
      s.bodies.expand((b) => b.buildings).firstWhere((b) => b.id == id);

  /// A second iron mine on Kora: the starting smelter runs flat out on
  /// the first mine's 0.4 ore a second, so with only that one a faster
  /// smelter has no more ore to work, and gains nothing steady.
  void feedTheSmelter() {
    final credits = s.faction(_p).credits;
    s.faction(_p).credits = BigNum.from(1e6);
    expect(
      applyCommand(
        s,
        c,
        const BuildCommand(_p, 'kora', 'mine', depositResourceId: 'iron_ore'),
      ),
      isA<CommandOk>(),
    );
    s.faction(_p).credits = credits;
  }

  group('upgradePreview', () {
    test('speed on the starting smelter, fed, gains credits and pays back', () {
      feedTheSmelter();
      final p = upgradePreview(s, c, _p, 'b3', UpgradeTrack.speed)!;
      expect(
        p.cost,
        upgradeCost(c, building('b3'), UpgradeTrack.speed)['credits'],
      );
      expect(p.creditsDeltaPerSec > const BigNum.zero(), isTrue);
      expect(p.outputDeltaPerSec['steel']!.toDouble(), greaterThan(0));
      expect(p.paybackSeconds, isNotNull);
      expect(p.paybackSeconds!.isFinite, isTrue);
      expect(
        p.paybackSeconds,
        closeTo(p.cost.toDouble() / p.creditsDeltaPerSec.toDouble(), 1e-9),
      );
      expect(p.limitedElsewhere, isFalse);
    });

    test('previews a level the faction cannot afford yet', () {
      feedTheSmelter();
      s.faction(_p).credits = const BigNum.zero();
      final p = upgradePreview(s, c, _p, 'b3', UpgradeTrack.speed);
      expect(p, isNotNull);
      expect(p!.paybackSeconds, isNotNull);
    });

    test("the new game's smelter is held by its ore: limited elsewhere", () {
      final p = upgradePreview(s, c, _p, 'b3', UpgradeTrack.speed)!;
      expect(p.paybackSeconds, isNull);
      expect(p.limitedElsewhere, isTrue);
    });

    test('a smelter starved of ore is limited elsewhere: no payback', () {
      // The iron mine stops and the ore runs out.
      expect(
        applyCommand(s, c, const AssignCrewCommand(_p, 'b1', 0)),
        isA<CommandOk>(),
      );
      s.body('kora').stock['iron_ore'] = const BigNum.zero();
      engine.advance(s, 5);
      final p = upgradePreview(s, c, _p, 'b3', UpgradeTrack.speed)!;
      expect(p.creditsDeltaPerSec > const BigNum.zero(), isFalse);
      expect(p.paybackSeconds, isNull);
      expect(p.limitedElsewhere, isTrue);
    });

    test('a maxed track or a building it lacks previews nothing', () {
      final b3 = building('b3');
      var level = 0;
      while (upgradeMaxedReason(c, b3, UpgradeTrack.efficiency) == null) {
        b3.levels[UpgradeTrack.efficiency] = ++level;
      }
      expect(upgradePreview(s, c, _p, 'b3', UpgradeTrack.efficiency), isNull);
      expect(upgradePreview(s, c, _p, 'nope', UpgradeTrack.speed), isNull);
    });

    test('a given report of the state gives the same preview', () {
      final before = buildFlowReport(s, c, _p);
      final a = upgradePreview(s, c, _p, 'b3', UpgradeTrack.speed)!;
      final b = upgradePreview(
        s,
        c,
        _p,
        'b3',
        UpgradeTrack.speed,
        before: before,
      )!;
      expect(b.creditsDeltaPerSec, a.creditsDeltaPerSec);
      expect(b.paybackSeconds, a.paybackSeconds);
    });

    test('its gain matches a short real run, within 10%', () {
      // Selling everything shows what the extra output is worth: the
      // same state run 10 minutes with and without the level.
      GameState run({required bool upgraded}) {
        final x = s.copy();
        for (final id in c.resources.keys) {
          applyCommand(
            x,
            c,
            SetAutoSellCommand(_p, 'kora', id, const BigNum.zero()),
          );
        }
        if (upgraded) {
          x.faction(_p).credits = x.faction(_p).credits + BigNum.from(1e6);
          expect(
            applyCommand(
              x,
              c,
              const UpgradeCommand(_p, 'b3', UpgradeTrack.speed),
            ),
            isA<CommandOk>(),
          );
          x.faction(_p).credits = x.faction(_p).credits - BigNum.from(1e6);
        }
        return x;
      }

      feedTheSmelter();
      final plain = run(upgraded: false);
      final faster = run(upgraded: true);
      // The preview is of the state about to run, rules set.
      final p = upgradePreview(plain, c, _p, 'b3', UpgradeTrack.speed)!;
      const seconds = 600.0;
      engine.advance(plain, seconds);
      engine.advance(faster, seconds);
      // The faster run paid for its level out of the same start.
      final real =
          (faster.faction(_p).credits + p.cost - plain.faction(_p).credits)
              .toDouble() /
          seconds;
      expect(
        real,
        closeTo(
          p.creditsDeltaPerSec.toDouble(),
          0.1 * p.creditsDeltaPerSec.toDouble(),
        ),
      );
    });
  });

  group('bestUpgrades', () {
    test('affordable levels, soonest payback first, at most the limit', () {
      s.faction(_p).credits = BigNum.from(5000);
      final best = bestUpgrades(s, c, _p, limit: 5);
      expect(best, isNotEmpty);
      expect(best.length, lessThanOrEqualTo(5));
      for (var i = 1; i < best.length; i++) {
        expect(
          best[i].preview.paybackSeconds,
          greaterThanOrEqualTo(best[i - 1].preview.paybackSeconds!),
        );
      }
      for (final a in best) {
        expect(a.preview.cost <= BigNum.from(5000), isTrue);
        expect(a.bodyId, 'kora');
      }
      expect(bestUpgrades(s, c, _p), hasLength(lessThanOrEqualTo(3)));
    });

    test('none when nothing is affordable', () {
      s.faction(_p).credits = const BigNum.zero();
      expect(bestUpgrades(s, c, _p), isEmpty);
    });
  });

  group('makersOf', () {
    test('names the recipes and the extractors that make a resource', () {
      expect(makersOf(c, 'steel'), contains('smelter'));
      expect(makersOf(c, 'iron_ore'), contains('mine'));
      expect(makersOf(c, 'iron_ore'), isNot(contains('smelter')));
    });
  });

  group('hostsFor', () {
    test('leaves out bodies without the deposit', () {
      s.body('brine').ownerId = _p;
      s.faction(_p).credits = BigNum.from(1e9);
      expect(hostsFor(s, c, _p, 'mine', depositResourceId: 'copper_ore'), [
        'kora',
      ]);
      final brine = hostChecks(
        s,
        c,
        _p,
        'mine',
        depositResourceId: 'copper_ore',
      ).singleWhere((h) => h.bodyId == 'brine');
      expect(brine.block!.kind, BuildBlockKind.noDeposit);
      expect(brine.block!.resourceId, 'copper_ore');
    });

    test('matches BuildCommand on every type, deposit and body', () {
      final states = <String, GameState>{
        'new game': s.copy(),
        'no credits': s.copy()..faction(_p).credits = const BigNum.zero(),
        'rich, two bodies': s.copy()
          ..faction(_p).credits = BigNum.from(1e12)
          ..body('brine').ownerId = _p,
        'goods on hand': () {
          final x = s.copy()
            ..faction(_p).credits = BigNum.from(1e12)
            ..body('cinder').ownerId = _p;
          for (final id in c.resources.keys) {
            x.body('kora').stock[id] = BigNum.from(1e6);
          }
          return x;
        }(),
        'a full body': () {
          final x = s.copy()..faction(_p).credits = BigNum.from(1e12);
          final kora = x.body('kora');
          while (kora.buildings.length < buildSlots(c, kora)) {
            applyCommand(x, c, const BuildCommand(_p, 'kora', 'smelter'));
          }
          return x;
        }(),
      };
      var compared = 0;
      for (final MapEntry(key: name, value: x) in states.entries) {
        for (final def in c.buildings.values) {
          final deposits = def.kind == BuildingKind.extractor
              ? <String?>[null, ...def.extracts]
              : <String?>[null];
          for (final deposit in deposits) {
            final checks = hostChecks(
              x,
              c,
              _p,
              def.id,
              depositResourceId: deposit,
            );
            for (final h in checks) {
              final r = applyCommand(
                x.copy(),
                c,
                BuildCommand(_p, h.bodyId, def.id, depositResourceId: deposit),
              );
              final why = '$name: ${def.id} ($deposit) on ${h.bodyId}';
              compared++;
              if (h.block == null) {
                expect(r, isA<CommandOk>(), reason: why);
                continue;
              }
              expect(r, isA<CommandFailed>(), reason: why);
              expect((r as CommandFailed).error, switch (h.block!.kind) {
                BuildBlockKind.noFreeSlot => CommandError.noBuildSlot,
                BuildBlockKind.noDeposit => CommandError.depositMissing,
                BuildBlockKind.short => CommandError.cannotAfford,
              }, reason: why);
            }
          }
        }
      }
      expect(compared, greaterThan(100));
    });

    test('a short cost names what, how much and what there is', () {
      s.faction(_p).credits = BigNum.from(10);
      final b = hostChecks(s, c, _p, 'smelter').single.block!;
      expect(b.kind, BuildBlockKind.short);
      expect(b.resourceId, 'credits');
      expect(b.need, c.buildings['smelter']!.buildCost['credits']);
      expect(b.have, BigNum.from(10));
    });
  });

  group('crewForecast', () {
    test('housing, demand and the worth of one more crew', () {
      final f = crewForecast(s, c, _p);
      final t = crewTotals(s, c, _p);
      expect(f.housing, t.supported);
      var demand = 0;
      for (final b in s.body('kora').buildings) {
        demand += maxCrew(c.rules, c.buildings[b.defId]!, b);
      }
      expect(f.demand, demand);
      expect(f.secondsUntilShortage, isNull);
      expect(f.creditsPerExtraCrew >= const BigNum.zero(), isTrue);
    });

    test('already over-assigned: the shortage is now', () {
      s.faction(_p).baseCrew = 0;
      expect(crewTotals(s, c, _p).overAssigned, greaterThan(0));
      expect(crewForecast(s, c, _p).secondsUntilShortage, 0);
    });
  });

  test('none of them change the state', () {
    s.faction(_p).credits = BigNum.from(5000);
    s.body('brine').ownerId = _p;
    final before = SaveCodec.encode(s);
    upgradePreview(s, c, _p, 'b3', UpgradeTrack.speed);
    upgradePreview(s, c, _p, 'b3', UpgradeTrack.capacity);
    bestUpgrades(s, c, _p);
    makersOf(c, 'steel');
    hostsFor(s, c, _p, 'mine', depositResourceId: 'iron_ore');
    hostChecks(s, c, _p, 'smelter');
    crewForecast(s, c, _p);
    expect(SaveCodec.encode(s), before);
  });
}
