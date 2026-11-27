import 'dart:convert';
import 'dart:math' as math;

import 'package:game_core/game_core.dart';
import 'package:test/test.dart';

import '../state/helpers.dart';

BigNum n(num v) => BigNum.from(v);

String encode(GameState s) => jsonEncode(s.toJson());

/// The shipped content with [edit] applied to its decoded bundle.
Content contentWith(void Function(Map<String, Object?> bundle) edit) {
  final b = shippedBundle();
  edit(b);
  return switch (Content.fromBundle(b)) {
    ContentOk(:final content) => content,
    ContentInvalid(:final errors) => throw StateError('$errors'),
  };
}

/// The errors loading the shipped content with [edit] applied gives.
List<String> errorsWith(void Function(Map<String, Object?> bundle) edit) {
  final b = shippedBundle();
  edit(b);
  return switch (Content.fromBundle(b)) {
    ContentOk() => const [],
    ContentInvalid(:final errors) => errors,
  };
}

void main() {
  final content = shippedContent();
  final e = GameEngine(content);
  final refill = content.rules.contractRefillSeconds;

  FactionState player(GameState s) => s.faction('player');

  String? ok(GameState s, Command cmd) {
    final r = e.apply(s, cmd);
    expect(r, isA<CommandOk>(), reason: r is CommandFailed ? r.message : '');
    return (r as CommandOk).createdId;
  }

  /// Applies [cmd], expects [error] and no change to [s], and returns the
  /// failure's message.
  String fails(GameState s, Command cmd, CommandError error) {
    final before = encode(s);
    final r = e.apply(s, cmd);
    expect(r, isA<CommandFailed>().having((f) => f.error, 'error', error));
    expect(encode(s), before);
    return (r as CommandFailed).message;
  }

  /// A new game with a full board, every refill used.
  GameState fullBoard([int seed = 1]) {
    final s = e.newGame(seed);
    e.advance(s, refill * 2 + 60);
    expect(player(s).contracts, hasLength(RulesDef.contractSlots));
    expect(player(s).contractRefillAt, isEmpty);
    return s;
  }

  /// Puts a contract for [quantity] of [resourceId] on the player's board
  /// in place of its last one, as if just posted.
  ContractState postOn(
    GameState s,
    String resourceId,
    num quantity, {
    num reward = 1000,
  }) {
    final f = player(s);
    if (f.contracts.length + f.contractRefillAt.length >=
        RulesDef.contractSlots) {
      if (f.contractRefillAt.isNotEmpty) {
        f.contractRefillAt.removeLast();
      } else {
        f.contracts.removeLast();
      }
    }
    final k = ContractState(
      id: s.newId('c'),
      templateId: content.contractTemplates.keys.first,
      resourceId: resourceId,
      quantity: n(quantity),
      rewardCredits: n(reward),
      postedAt: s.time,
    );
    f.contracts.add(k);
    return k;
  }

  group('the shipped contract templates', () {
    test('come from the Veyra Exchange, tiers 0 to 3 covered', () {
      expect(content.contractTemplates, isNotEmpty);
      final tiers = <int>{};
      for (final t in content.contractTemplates.values) {
        expect(t.issuer, 'Veyra Exchange');
        // 1 to 3 h of production, longer for higher tiers.
        expect(t.quantitySeconds, inInclusiveRange(3600, 10800));
        expect(t.rewardMultiplier, 3);
        expect(t.rewardIncomeSeconds, 1200);
        expect(t.rewardCapIncomeSeconds, 3600);
        expect(t.lifeSupportWeight, 0.25);
        expect(t.minRewardCredits > const BigNum.zero(), isTrue);
        expect(
          t.firstContractMinReward! >= content.rules.claimBaseCredits,
          isTrue,
        );
        for (var i = t.minTier; i <= t.maxTier; i++) {
          tiers.add(i);
        }
      }
      expect(tiers, containsAll([0, 1, 2, 3]));
    });

    test('refill after 4 hours', () {
      expect(refill, 14400);
    });
  });

  group('content validation', () {
    Map<String, Object?> template(Map<String, Object?> b) =>
        ((b['contracts']! as List).first as Map).cast<String, Object?>();

    test('defaults apply when a template leaves them out', () {
      final c = contentWith(
        (b) => b['contracts'] = [
          {
            'id': 'plain',
            'issuer': 'Veyra Exchange',
            'minTier': 0,
            'maxTier': 1,
          },
        ],
      );
      final t = c.contractTemplates['plain']!;
      expect(t.quantitySeconds, ContractTemplateDef.defaultQuantitySeconds);
      expect(t.quantitySeconds, 14400);
      expect(t.rewardMultiplier, 2.5);
      expect(t.minQuantity, n(ContractTemplateDef.defaultMinQuantity));
      expect(t.maxQuantity, isNull);
      expect(t.rewardIncomeSeconds, 0);
      expect(t.rewardCapIncomeSeconds, isNull);
      expect(t.lifeSupportWeight, 1);
      expect(t.minRewardCredits, const BigNum.zero());
      expect(t.firstContractMinReward, isNull);
    });

    test('a reward cap of at least the floor loads', () {
      final c = contentWith((b) {
        final t = template(b)
          ..['rewardIncomeSeconds'] = 600
          ..['rewardCapIncomeSeconds'] = 600;
        expect(t, isNotEmpty);
      });
      final t = c.contractTemplates.values.first;
      expect(t.rewardIncomeSeconds, 600);
      expect(t.rewardCapIncomeSeconds, 600);
    });

    test('content without contracts posts none', () {
      final c = contentWith((b) => b.remove('contracts'));
      expect(c.contractTemplates, isEmpty);
      final s = GameEngine(c).newGame(1);
      GameEngine(c).advance(s, refill * 3);
      expect(player(s).contracts, isEmpty);
    });

    test('the refill time defaults to 4 hours and must be above 0', () {
      expect(
        contentWith(
          (b) => (b['rules']! as Map).remove('contractRefillSeconds'),
        ).rules.contractRefillSeconds,
        14400,
      );
      expect(
        errorsWith((b) => (b['rules']! as Map)['contractRefillSeconds'] = 0),
        ['rules.contractRefillSeconds: must be > 0'],
      );
    });

    final bad = <String, (void Function(Map<String, Object?>), String)>{
      'tiers out of order': (
        (t) => t
          ..['minTier'] = 2
          ..['maxTier'] = 1,
        'maxTier: must be >= minTier (2)',
      ),
      'a tier above 4': ((t) => t['maxTier'] = 5, 'maxTier: must be <= 4'),
      'a negative tier': ((t) => t['minTier'] = -1, 'minTier: must be >= 0'),
      'no issuer': ((t) => t.remove('issuer'), 'issuer: missing'),
      'zero quantity seconds': (
        (t) => t['quantitySeconds'] = 0,
        'quantitySeconds: must be > 0',
      ),
      'zero reward multiplier': (
        (t) => t['rewardMultiplier'] = 0,
        'rewardMultiplier: must be > 0',
      ),
      'zero minimum quantity': (
        (t) => t['minQuantity'] = '0',
        'minQuantity: must be > 0',
      ),
      'zero maximum quantity': (
        (t) => t['maxQuantity'] = '0',
        'maxQuantity: must be > 0',
      ),
      'a maximum below the minimum': (
        (t) => t
          ..['minQuantity'] = '50'
          ..['maxQuantity'] = '40',
        'maxQuantity: must be >= minQuantity (50)',
      ),
      'negative reward income seconds': (
        (t) => t['rewardIncomeSeconds'] = -1,
        'rewardIncomeSeconds: must be >= 0',
      ),
      'a reward cap below the floor': (
        (t) => t
          ..['rewardIncomeSeconds'] = 600
          ..['rewardCapIncomeSeconds'] = 599,
        'rewardCapIncomeSeconds: must be >= rewardIncomeSeconds (600)',
      ),
      'a zero reward cap': (
        (t) => t
          ..['rewardIncomeSeconds'] = 0
          ..['rewardCapIncomeSeconds'] = 0,
        'rewardCapIncomeSeconds: must be > 0',
      ),
      'a negative minimum reward': (
        (t) => t['minRewardCredits'] = '-1',
        'minRewardCredits: must be >= 0',
      ),
      'a first-contract minimum below the first claim': (
        (t) => t['firstContractMinReward'] = '4999',
        "firstContractMinReward: must be >= the first claim's credits (5K)",
      ),
      'a zero life-support weight': (
        (t) => t['lifeSupportWeight'] = 0,
        'lifeSupportWeight: must be > 0',
      ),
      'a life-support weight above 1': (
        (t) => t['lifeSupportWeight'] = 1.5,
        'lifeSupportWeight: must be <= 1',
      ),
      'an unknown field': (
        (t) => t['expires'] = 3600,
        'expires: unknown field',
      ),
    };
    for (final MapEntry(key: name, value: (edit, message)) in bad.entries) {
      test('rejects $name', () {
        final errors = errorsWith((b) => edit(template(b)));
        final id = template(shippedBundle())['id'];
        expect(errors, ['contracts.$id.$message']);
      });
    }

    test('a contractsCompleted milestone needs a count of at least 1', () {
      expect(
        errorsWith(
          (b) => (b['milestones']! as List).add({
            'id': 'orders',
            'name': 'Orders',
            'condition': {'type': 'contractsCompleted', 'count': 0},
          }),
        ),
        ['milestones.orders.condition.count: must be >= 1'],
      );
    });
  });

  group('twoSignificantFigures', () {
    test('rounds to two significant figures', () {
      expect(twoSignificantFigures(n(2876)), n(2900));
      expect(twoSignificantFigures(n(2824)), n(2800));
      expect(twoSignificantFigures(n(9960)), n(10000));
      expect(twoSignificantFigures(n(0.01234)), n(0.012));
      expect(twoSignificantFigures(n(7)), n(7));
      expect(twoSignificantFigures(n(100)), n(100));
      expect(twoSignificantFigures(BigNum.parse('3.456e40')), n(3.5e40));
    });
  });

  group('generation', () {
    test('3 contracts appear after refills on a game with production', () {
      final s = e.newGame(1);
      expect(player(s).contracts, isEmpty);
      expect(player(s).contractRefillAt, [0, refill, refill * 2]);

      e.advance(s, 60);
      expect(player(s).contracts, hasLength(1));
      expect(player(s).contractRefillAt, [refill, refill * 2]);

      e.advance(s, refill - 120);
      expect(player(s).contracts, hasLength(1));
      e.advance(s, 60);
      expect(player(s).contracts, hasLength(2));

      e.advance(s, refill);
      expect(player(s).contracts, hasLength(3));
      expect(player(s).contractRefillAt, isEmpty);

      e.advance(s, refill * 3);
      expect(player(s).contracts, hasLength(3), reason: 'at most 3');
      expect({for (final k in player(s).contracts) k.id}, hasLength(3));
    });

    test('each contract follows its template', () {
      for (final seed in [1, 2, 3, 4, 5, 6]) {
        final s = fullBoard(seed);
        final f = player(s);
        final resources = <String>{};
        for (final k in f.contracts) {
          final t = content.contractTemplates[k.templateId]!;
          final r = content.resources[k.resourceId]!;
          expect(r.tier, inInclusiveRange(t.minTier, t.maxTier));
          expect(resources.add(r.id), isTrue, reason: 'one per resource');
          final made = f.lifetimeProduced[r.id] ?? const BigNum.zero();
          expect(made > const BigNum.zero(), isTrue);
          expect(k.quantity, twoSignificantFigures(k.quantity));
          expect(k.quantity >= t.minQuantity, isTrue);
          if (t.maxQuantity case final most?) {
            expect(k.quantity <= most, isTrue);
          }
          expect(k.rewardCredits > const BigNum.zero(), isTrue);
          expect(k.delivered, const BigNum.zero());
          expect(k.postedAt, lessThanOrEqualTo(s.time));
        }
      }
    });

    test('the quantity is hours of gross production, not net', () {
      final s = e.newGame(1);
      final f = player(s);
      // A plate press uses most of the smelter's steel, so steel's net rate
      // is far below what is made.
      s
          .body('kora')
          .buildings
          .add(BuildingState(id: s.newId('b'), defId: 'plate_press', crew: 1));
      // Only steel is eligible.
      f.lifetimeProduced
        ..clear()
        ..['steel'] = n(1);
      f.contractRefillAt
        ..clear()
        ..add(0);
      final report = buildFlowReport(s, content, f.id);
      final gross = report.steadyProducedPerSec('steel');
      expect(gross > const BigNum.zero(), isTrue);
      expect(gross, report.producedPerSec('steel'), reason: 'steadily fed');
      expect(report.netProducedPerSec('steel') < gross.mulDouble(0.5), isTrue);
      stepContracts(s, content, 0);
      final k = f.contracts.single;
      expect(k.resourceId, 'steel');
      final t = content.contractTemplates[k.templateId]!;
      expect(
        k.quantity,
        twoSignificantFigures(gross.mulDouble(t.quantitySeconds)),
      );
    });

    test('the bug-1 shape: a good made before but at a trickle now gets no '
        'order, nor one fed from a stockpile', () {
      final s = e.newGame(1);
      final f = player(s);
      final kora = s.body('kora');
      kora.buildings.add(
        BuildingState(id: s.newId('b'), defId: 'drone_works', crew: 2),
      );
      // Drones were made once; the works now stands idle, short of inputs.
      f.lifetimeProduced
        ..clear()
        ..['survey_drone'] = n(2);
      f.contractRefillAt
        ..clear()
        ..add(0);
      final rng = s.rngState;
      stepContracts(s, content, 0);
      expect(f.contracts, isEmpty, reason: 'no order of 2 drones');
      expect(f.contractRefillAt, [0], reason: 'the refill waits');
      expect(s.rngState, rng);

      // A stockpile runs the works today, but nothing refills it.
      kora.stock
        ..['magnet'] = n(400)
        ..['circuit'] = n(400)
        ..['fuel'] = n(600);
      final report = buildFlowReport(s, content, f.id);
      expect(
        report.producedPerSec('survey_drone') > const BigNum.zero(),
        isTrue,
      );
      expect(report.steadyProducedPerSec('survey_drone'), const BigNum.zero());
      stepContracts(s, content, 0);
      expect(f.contracts, isEmpty);
    });

    test('hours of what a steadily fed maker makes are asked for', () {
      // The smelter feeds a plate press about half what it could use.
      final s = e.newGame(1);
      s
          .body('kora')
          .buildings
          .add(BuildingState(id: s.newId('b'), defId: 'plate_press', crew: 1));
      final f = player(s);
      f.lifetimeProduced
        ..clear()
        ..['hull_plate'] = n(1);
      f.contractRefillAt
        ..clear()
        ..add(0);
      final gross = buildFlowReport(
        s,
        content,
        f.id,
      ).steadyProducedPerSec('hull_plate');
      expect(gross.toDouble(), closeTo(0.2 / 3, 1e-6));
      stepContracts(s, content, 0);
      final k = f.contracts.single;
      final t = content.contractTemplates[k.templateId]!;
      expect(
        k.quantity,
        twoSignificantFigures(gross.mulDouble(t.quantitySeconds)),
      );
    });

    test('a refill waiting on a starved maker is checked again only at '
        'each whole minute of game time, whatever the step', () {
      // A plate press made plates once; with the mines and smelter
      // unstaffed it stands idle, until they are staffed again.
      GameState starved() {
        final s = e.newGame(1);
        final kora = s.body('kora');
        for (final b in kora.buildings) {
          b.crew = 0;
        }
        kora.buildings.add(
          BuildingState(id: s.newId('b'), defId: 'plate_press', crew: 1),
        );
        player(s).lifetimeProduced
          ..clear()
          ..['hull_plate'] = n(2);
        player(s).contractRefillAt
          ..clear()
          ..add(0);
        return s;
      }

      void feed(GameState s) {
        for (final b in s.body('kora').buildings) {
          b.crew = 1;
        }
      }

      // 1 s steps: fed at 30 s, it is asked for at the next minute.
      final live = starved();
      e.advance(live, 30, maxStep: 1);
      expect(player(live).contracts, isEmpty);
      feed(live);
      e.advance(live, 1, maxStep: 1);
      expect(player(live).contracts, isEmpty, reason: 'not before 60 s');
      e.advance(live, 29, maxStep: 1);
      expect(player(live).contracts.single.postedAt, 60);

      // 60 s steps post it at the same time.
      final away = starved();
      feed(away);
      e.advance(away, 60);
      expect(player(away).contracts.single.postedAt, 60);
      expect(
        player(away).contracts.single.resourceId,
        player(live).contracts.single.resourceId,
      );
    });

    group('a stockpile nothing refills', () {
      /// Seed 1, an hour of selling everything Kora makes, then a crewed
      /// drone works, fed from a stockpile of its inputs when [stocked];
      /// a refill is due and only goods in [made] count as made.
      GameState played({required bool stocked, required List<String> made}) {
        final s = e.newGame(1);
        e.advance(s, 60);
        for (final id in ['iron_ore', 'copper_ore', 'steel']) {
          ok(s, SetAutoSellCommand('player', 'kora', id, n(0)));
        }
        e.advance(s, 3600);
        final kora = s.body('kora');
        kora.buildings.add(
          BuildingState(id: s.newId('b'), defId: 'drone_works', crew: 2),
        );
        if (stocked) {
          kora.stock
            ..['magnet'] = n(400)
            ..['circuit'] = n(400)
            ..['fuel'] = n(600);
        }
        final f = player(s);
        f.contracts.clear();
        f.contractRefillAt
          ..clear()
          ..addAll([s.time, s.time + 1e7, s.time + 2e7]);
        f.lifetimeProduced
          ..clear()
          ..addAll({for (final id in made) id: n(1)});
        return s;
      }

      test('does not raise the income basis, nor so a reward', () {
        // Review probe: 1.646 against 5.646 a second, and a steel order of
        // 5,925 against 12,960 credits.
        (BigNum, BigNum) post(bool stocked) {
          final s = played(stocked: stocked, made: ['steel']);
          final basis = incomeBasis(
            s,
            content,
            buildFlowReport(s, content, 'player'),
          );
          stepContracts(s, content, s.time);
          return (basis, player(s).contracts.single.rewardCredits);
        }

        final (plainBasis, plainReward) = post(false);
        final (stockBasis, stockReward) = post(true);
        expect(
          stockBasis.toDouble(),
          closeTo(plainBasis.toDouble(), plainBasis.toDouble() * 0.01),
        );
        expect(
          stockReward.toDouble(),
          closeTo(plainReward.toDouble(), plainReward.toDouble() * 0.01),
        );
      });

      test("does not make its maker's output eligible", () {
        final s = played(stocked: true, made: ['survey_drone']);
        stepContracts(s, content, s.time);
        expect(player(s).contracts, isEmpty, reason: 'no drone order');
      });

      test('does not change the quantity of what is made steadily', () {
        // A plate press fed by the smelter, and in one game also from a
        // stock of steel.
        ContractState plates(bool stocked) {
          final s = e.newGame(1);
          s
              .body('kora')
              .buildings
              .add(
                BuildingState(id: s.newId('b'), defId: 'plate_press', crew: 1),
              );
          if (stocked) s.body('kora').stock['steel'] = n(900);
          final f = player(s);
          f.lifetimeProduced
            ..clear()
            ..['hull_plate'] = n(1);
          f.contractRefillAt
            ..clear()
            ..add(0);
          stepContracts(s, content, 0);
          return f.contracts.single;
        }

        expect(plates(true).quantity, plates(false).quantity);
      });
    });

    test('a good made below minQuantity / quantitySeconds is not asked '
        'for', () {
      GameState steelAt(String minQuantity) {
        final c = contentWith((b) {
          for (final t
              in (b['contracts']! as List).cast<Map<String, Object?>>()) {
            t
              ..['minQuantity'] = minQuantity
              ..remove('maxQuantity');
          }
        });
        final s = GameEngine(c).newGame(1);
        final f = player(s);
        f.lifetimeProduced
          ..clear()
          ..['steel'] = n(1);
        f.contractRefillAt
          ..clear()
          ..add(0);
        stepContracts(s, c, 0);
        return s;
      }

      final s = e.newGame(1);
      final gross = buildFlowReport(
        s,
        content,
        'player',
      ).producedPerSec('steel');
      final t = content.contractTemplates.values.firstWhere(
        (t) => t.minTier <= 1 && t.maxTier >= 1,
      );
      final atRate = gross.mulDouble(t.quantitySeconds).toDouble();
      expect(player(steelAt('${atRate * 1.05}')).contracts, isEmpty);
      final k = player(steelAt('${atRate * 0.95}')).contracts.single;
      expect(k.resourceId, 'steel');
      expect(
        k.quantity,
        twoSignificantFigures(gross.mulDouble(t.quantitySeconds)),
      );
    });

    /// A game whose only eligible resource is steel, made fast enough that
    /// 4 h of it is far more than Kora can store, with one refill due.
    GameState steelFlood(Content c) {
      final s = GameEngine(c).newGame(1);
      final f = player(s);
      f.lifetimeProduced
        ..clear()
        ..['steel'] = n(1);
      f.contractRefillAt
        ..clear()
        ..add(0);
      for (final b in s.body('kora').buildings) {
        if (b.defId == 'smelter' || b.defId == 'mine') {
          b.levels[UpgradeTrack.speed] = 40;
        }
      }
      final sell = SetAutoSellCommand('player', 'kora', 'steel', n(0));
      expect(GameEngine(c).apply(s, sell), isA<CommandOk>());
      return s;
    }

    /// Only steel, with [edit] applied to every template.
    Content steelOnly(void Function(Map<String, Object?> t) edit) =>
        contentWith((b) {
          for (final t
              in (b['contracts']! as List).cast<Map<String, Object?>>()) {
            edit(t);
          }
        });

    ContractState postSteel(GameState s, Content c) {
      for (var i = 0; i < 40; i++) {
        final x = s.copy();
        stepContracts(x, c, 0);
        if (player(x).contracts.single.resourceId == 'steel') {
          return player(x).contracts.single;
        }
        // Draw again: another state of the RNG.
        s.rngState = Rng.fromState(s.rngState).state ^ (i + 1);
      }
      throw StateError('steel never drawn');
    }

    test('the quantity is at most what one owned body can store', () {
      final s = steelFlood(content);
      final rate = buildFlowReport(
        s,
        content,
        'player',
      ).netProducedPerSec('steel');
      final cap = storageCap(s, content, s.body('kora'));
      expect(rate.mulDouble(14400) > cap.mulDouble(10), isTrue);
      final k = postSteel(s, content);
      expect(k.quantity <= cap, isTrue, reason: '${k.quantity} vs $cap');
      expect(k.quantity >= cap.mulDouble(0.9), isTrue);
      expect(k.quantity, twoSignificantFigures(k.quantity));
    });

    test("a template's maximum quantity caps it", () {
      final c = steelOnly((t) => t['maxQuantity'] = '120');
      final k = postSteel(steelFlood(c), c);
      expect(k.quantity, n(120));
    });

    test('the maximum quantity grows with the levels of megaprojects that '
        'scale contracts', () {
      final c = steelOnly((t) => t['maxQuantity'] = '120');
      final s = steelFlood(c);
      player(s).megaprojectLevels
        ..['orbital_station'] = 2
        // The Mass Driver's levels do not scale orders.
        ..['mass_driver'] = 5;
      expect(c.megaprojects['orbital_station']!.scalesContracts, isTrue);
      expect(c.megaprojects['mass_driver']!.scalesContracts, isFalse);
      expect(storageCap(s, c, s.body('kora')) > n(360 * 3), isTrue);
      // 1 + 2 station levels.
      expect(postSteel(s, c).quantity, n(360));
    });

    /// What [s]'s player is paid for by the second: the larger of its
    /// steady auto-sale income and the value of what its buildings make
    /// beyond what they use, at the current prices.
    BigNum basis(GameState s, Content c) {
      final r = buildFlowReport(s, c, 'player');
      var made = const BigNum.zero();
      for (final id in c.resources.keys) {
        final net = r.netProducedPerSec(id);
        if (net > const BigNum.zero()) made = made + net * price(s, c, id);
      }
      return r.creditsPerSec.max(made);
    }

    test('the reward is at least rewardIncomeSeconds of the income basis', () {
      final c = steelOnly(
        (t) => t
          ..['rewardIncomeSeconds'] = 600
          ..['maxQuantity'] = '10'
          ..['minQuantity'] = '10',
      );
      final s = steelFlood(c);
      player(s).contractsPosted = 1;
      final income = basis(s, c);
      expect(income > n(10), isTrue);
      final k = postSteel(s, c);
      expect(k.quantity, n(10));
      expect(k.rewardCredits, income.mulDouble(600));
      // Between the floor and the cap, the reward is by quantity.
      final plain = steelOnly(
        (t) => t
          ..['rewardIncomeSeconds'] = 1
          ..['rewardCapIncomeSeconds'] = 1e9
          ..['maxQuantity'] = '1000',
      );
      final big = postSteel(steelFlood(plain), plain);
      expect(
        big.rewardCredits,
        big.quantity * c.resources['steel']!.basePrice.mulDouble(3),
      );
    });

    /// Only steel, paying a million times its price, capped at 1 h of
    /// income, at least 500 credits.
    Content lavish() => steelOnly(
      (t) => t
        ..['rewardMultiplier'] = 1e6
        ..['rewardIncomeSeconds'] = 600
        ..['rewardCapIncomeSeconds'] = 3600
        ..['minRewardCredits'] = '500',
    );

    test('the reward is at most rewardCapIncomeSeconds of the income '
        'basis', () {
      final c = lavish();
      final s = steelFlood(c);
      player(s).contractsPosted = 1;
      final income = basis(s, c);
      expect(income > const BigNum.zero(), isTrue);
      final k = postSteel(s, c);
      expect(
        k.quantity * c.resources['steel']!.basePrice.mulDouble(1e6) >
            income.mulDouble(3600),
        isTrue,
      );
      expect(k.rewardCredits, income.mulDouble(3600));
    });

    test('the first contract a faction is ever offered is exempt from the '
        'cap', () {
      final c = lavish();
      final s = steelFlood(c);
      expect(player(s).contractsPosted, 0);
      final income = basis(s, c);
      final k = postSteel(s, c);
      expect(
        k.rewardCredits,
        k.quantity * c.resources['steel']!.basePrice.mulDouble(1e6),
      );
      expect(k.rewardCredits > income.mulDouble(3600), isTrue);
    });

    test("a new game's first contract pays at least firstContractMinReward, "
        'more than the first claim, on seeds 1 to 3', () {
      for (final seed in [1, 2, 3]) {
        final s = e.newGame(seed);
        final f = player(s);
        expect(f.contractsPosted, 0);
        e.advance(s, 60);
        final first = f.contracts.single;
        expect(f.contractsPosted, 1);
        final t = content.contractTemplates[first.templateId]!;
        final byQuantity =
            first.quantity *
            content.resources[first.resourceId]!.basePrice.mulDouble(
              t.rewardMultiplier,
            );
        expect(t.firstContractMinReward, isNotNull);
        expect(
          first.rewardCredits,
          byQuantity.max(t.firstContractMinReward!),
          reason: 'seed $seed: the floor is less early on',
        );
        // It pays for the first claim, with a margin.
        final claim = claimCost(s, content, 'player')['credits']!;
        expect(first.rewardCredits >= claim.mulDouble(1.4), isTrue);
      }
    });

    test('the next contracts keep within the floor and cap', () {
      final s = e.newGame(1);
      e.advance(s, 60);
      for (final id in ['iron_ore', 'copper_ore', 'steel']) {
        ok(s, SetAutoSellCommand('player', 'kora', id, n(0)));
      }
      e.advance(s, refill - 120);
      final income = basis(s, content);
      e.advance(s, 120);
      expect(player(s).contractsPosted, 2);
      final second = player(s).contracts.last;
      expect(second.rewardCredits <= income.mulDouble(3600 * 1.01), isTrue);
      expect(second.rewardCredits >= income.mulDouble(600 * 0.99), isTrue);
    });

    group('the reward does not depend on which goods auto-sell', () {
      /// The second contract of a new game (seed 1) whose player sets
      /// auto-sell rules for [sold] on Kora after the first.
      ContractState second(List<String> sold) {
        final s = e.newGame(1);
        e.advance(s, 60);
        for (final id in sold) {
          ok(s, SetAutoSellCommand('player', 'kora', id, n(0)));
        }
        e.advance(s, refill);
        return player(s).contracts[1];
      }

      test('none, one or all goods sold give about the same reward', () {
        // Review probe: 12,960, 1,591 and 5,909 credits for steel.
        final rewards = [
          for (final sold in [
            <String>[],
            ['copper_ore'],
            ['iron_ore', 'copper_ore', 'steel'],
          ])
            second(sold),
        ];
        expect({for (final k in rewards) k.resourceId}, hasLength(1));
        final values = [for (final k in rewards) k.rewardCredits.toDouble()];
        final most = values.reduce(math.max);
        final least = values.reduce(math.min);
        expect(most / least, lessThan(1.5), reason: '$values');
      });

      test('turning auto-sell off right before a refill gains nothing', () {
        final c = lavish();
        final s = steelFlood(c);
        player(s).contractsPosted = 1;
        GameEngine(c).advance(s, 3600);
        final f = player(s);
        f.contracts.clear();
        f.contractRefillAt
          ..clear()
          ..addAll([s.time, s.time + 1e6, s.time + 2e6]);
        final selling = s.copy();
        final off = s.copy();
        player(off).autoSell.clear();
        stepContracts(selling, c, s.time);
        stepContracts(off, c, s.time);
        final (a, b) = (
          player(selling).contracts.single,
          player(off).contracts.single,
        );
        expect(b.resourceId, a.resourceId);
        expect(b.rewardCredits <= a.rewardCredits.mulDouble(1.001), isTrue);
      });

      group('a habitat fed partly from stock', () {
        /// Brine's 2 ice drills and melters, electrolyzer, protein vat
        /// and habitat, with [unstaffed] left without crew, and food and
        /// oxygen in stock.
        GameState brine(String? unstaffed) {
          final s = e.newGame(1);
          final brine = s.body('brine')..ownerId = 'player';
          for (final (def, dep) in [
            ('ice_drill', 'water_ice'),
            ('ice_drill', 'water_ice'),
            ('ice_melter', null),
            ('ice_melter', null),
            ('electrolyzer', null),
            ('protein_vat', null),
            ('habitat', null),
          ]) {
            brine.buildings.add(
              BuildingState(
                id: s.newId('b'),
                defId: def,
                depositResourceId: dep,
                crew: def == unstaffed ? 0 : content.buildings[def]!.crewSlots,
              ),
            );
          }
          brine.stock
            ..['food'] = n(700)
            ..['oxygen'] = n(700);
          return s;
        }

        test('still counts all it draws', () {
          // With no electrolyzer, the habitat breathes stocked oxygen and
          // the vat, short of hydrogen, stands idle: of the melters' 1.0
          // water a second, the habitat's 0.1 is not left over.
          final s = brine('electrolyzer');
          final r = buildFlowReport(s, content, 'player');
          expect(r.steadySurplusPerSec('water').toDouble(), closeTo(0.9, 1e-9));
        });

        test('unstaffing the food maker it eats from does not raise the '
            'basis', () {
          // Review probe: 4.787 against 4.233 a second.
          BigNum basis(String? unstaffed) {
            final s = brine(unstaffed);
            return incomeBasis(
              s,
              content,
              buildFlowReport(s, content, 'player'),
            );
          }

          expect(basis('protein_vat') <= basis(null), isTrue);
        });
      });

      test('a tiny income pays minRewardCredits, never nothing', () {
        final c = lavish();
        final s = e.newGame(1);
        final f = player(s);
        f.contractsPosted = 1;
        f.lifetimeProduced
          ..clear()
          ..['steel'] = n(1);
        f.contractRefillAt
          ..clear()
          ..add(0);
        ok(s, SetAutoSellCommand('player', 'kora', 'steel', n(0)));
        // Every market at its floor: steel sells for next to nothing.
        for (final id in c.resources.keys) {
          s.market.saturation[id] = marketFloorOf(c, id);
        }
        final income = basis(s, c);
        expect(income > const BigNum.zero(), isTrue);
        expect(income.mulDouble(3600) < n(500), isTrue, reason: '$income');
        stepContracts(s, c, 0);
        expect(f.contracts.single.rewardCredits, n(500));
      });
    });

    test('asks only for goods being made now', () {
      final picked = <String>{};
      for (var seed = 1; seed <= 40; seed++) {
        final s = e.newGame(seed);
        final f = player(s);
        f.lifetimeProduced
          ..clear()
          ..['copper_ore'] = n(1);
        f.contractRefillAt
          ..clear()
          ..add(0);
        stepContracts(s, content, 0);
        picked.add(f.contracts.single.resourceId);
      }
      // Copper wire could be made from copper ore, but is not made.
      expect(picked, {'copper_ore'});
    });

    group('life-support goods', () {
      /// The share of [draws] contracts on [s]'s board, each from another
      /// RNG state, that ask for a life-support good.
      double lifeSupportShare(GameState s, int draws) {
        var hits = 0;
        for (var i = 0; i < draws; i++) {
          final x = s.copy()..rngState = i * 7919 + 1;
          stepContracts(x, content, x.time);
          final id = player(x).contracts.single.resourceId;
          if (const {'water', 'food', 'oxygen'}.contains(id)) hits++;
        }
        return hits / draws;
      }

      /// A new game whose only goods made are [made]; Brine, owned too,
      /// drills ice and melts it into water, and Kora presses plates from
      /// its smelter's steel.
      GameState makes(List<String> made) {
        final s = e.newGame(1);
        s.body('brine')
          ..ownerId = 'player'
          ..buildings.addAll([
            BuildingState(
              id: s.newId('b'),
              defId: 'ice_drill',
              depositResourceId: 'water_ice',
              crew: 1,
            ),
            BuildingState(id: s.newId('b'), defId: 'ice_melter', crew: 1),
          ]);
        s
            .body('kora')
            .buildings
            .add(
              BuildingState(id: s.newId('b'), defId: 'plate_press', crew: 1),
            );
        final f = player(s);
        f.lifetimeProduced
          ..clear()
          ..addAll({for (final id in made) id: n(1)});
        f.contractRefillAt
          ..clear()
          ..add(0);
        return s;
      }

      test('weigh a quarter beside another good of the template', () {
        // Steel and water both come from the bulk template: water is drawn
        // 0.25 / 1.25 of the time, not half.
        final share = lifeSupportShare(makes(['steel', 'water']), 400);
        expect(share, closeTo(0.2, 0.05));
      });

      test('weigh a template down when they are all it could ask for', () {
        // Water is all the bulk template has; hull plates are the parts
        // template's.
        final share = lifeSupportShare(makes(['water', 'hull_plate']), 400);
        expect(share, closeTo(0.2, 0.05));
      });

      test("weigh what their template's lifeSupportWeight says", () {
        final c = contentWith((b) {
          for (final t
              in (b['contracts']! as List).cast<Map<String, Object?>>()) {
            t['lifeSupportWeight'] = 1;
          }
        });
        final s = makes(['steel', 'water']);
        var hits = 0;
        for (var i = 0; i < 400; i++) {
          final x = s.copy()..rngState = i * 7919 + 1;
          stepContracts(x, c, x.time);
          if (player(x).contracts.single.resourceId == 'water') hits++;
        }
        // Unweighted, water and steel are drawn alike.
        expect(hits / 400, closeTo(0.5, 0.07));
      });

      test('are still asked for when nothing else is made', () {
        expect(lifeSupportShare(makes(['water']), 10), 1);
      });
    });

    test('a refill waits while nothing is made, and RNG is not used', () {
      final s = e.newGame(1);
      for (final b in s.body('kora').buildings) {
        b.crew = 0;
      }
      final rng = s.rngState;
      e.advance(s, refill * 3);
      expect(player(s).contracts, isEmpty);
      expect(player(s).contractRefillAt, hasLength(3));
      expect(s.rngState, rng);

      for (final b in s.body('kora').buildings) {
        b.crew = 1;
      }
      e.advance(s, 120);
      expect(
        player(s).contracts,
        hasLength(3),
        reason: 'every banked refill is due',
      );
      expect(s.rngState, isNot(rng));
    });

    test('a refill left waiting posts as soon as something is made, however '
        'often it was checked before', () {
      final s = e.newGame(1);
      final f = player(s);
      f.lifetimeProduced.clear();
      f.contractRefillAt
        ..clear()
        ..add(0);
      for (var i = 0; i < 5; i++) {
        stepContracts(s, content, i * 60.0);
      }
      expect(f.contracts, isEmpty);
      f.lifetimeProduced['copper_ore'] = n(1);
      stepContracts(s, content, 300);
      expect(f.contracts.single.resourceId, 'copper_ore');
      expect(f.contractRefillAt, isEmpty);
    });

    test('is deterministic for the same seed and state', () {
      final a = e.newGame(7);
      final b = e.newGame(7);
      e.advance(a, refill * 2 + 60);
      e.advance(b, refill * 2 + 60);
      expect(encode(a), encode(b));
      expect(player(a).contracts, hasLength(3));

      final x = a.copy();
      final y = a.copy();
      player(x).contracts.clear();
      player(x).contractRefillAt.addAll([0, 0, 0]);
      player(y).contracts.clear();
      player(y).contractRefillAt.addAll([0, 0, 0]);
      stepContracts(x, content, x.time);
      stepContracts(y, content, y.time);
      expect(encode(x), encode(y));
    });

    test('draws the RNG only when posting a contract', () {
      final s = fullBoard();
      final rng = s.rngState;
      e.advance(s, refill * 2);
      expect(s.rngState, rng, reason: 'the board is full');
    });

    test('other factions have no board', () {
      final s = e.newGame(1);
      s.factions.add(
        FactionState(
          id: 'rival',
          name: 'Rival',
          isPlayer: false,
          credits: n(0),
          baseCrew: 0,
        ),
      );
      e.advance(s, refill * 3);
      expect(s.faction('rival').contracts, isEmpty);
      expect(s.faction('rival').contractRefillAt, isEmpty);
    });
  });

  group('delivery', () {
    test('partial and full delivery; the reward is paid once', () {
      final s = fullBoard();
      final k = postOn(s, 'steel', 100, reward: 5000);
      final kora = s.body('kora');
      kora.stock['steel'] = n(60);
      final credits = player(s).credits;

      ok(s, DeliverContractCommand('player', k.id, 'kora', n(40)));
      expect(k.delivered, n(40));
      expect(kora.stock['steel'], n(20));
      expect(player(s).credits, credits, reason: 'not paid until complete');
      expect(player(s).contracts, contains(k));

      // More than the stock held: delivers what there is.
      ok(s, DeliverContractCommand('player', k.id, 'kora', n(1000)));
      expect(k.delivered, n(60));
      expect(kora.stock['steel'], n(0));
      expect(player(s).credits, credits);

      kora.stock['steel'] = n(500);
      // More than is still wanted: delivers only that.
      ok(s, DeliverContractCommand('player', k.id, 'kora', n(1000)));
      expect(kora.stock['steel'], n(460));
      expect(player(s).credits, credits + n(5000));
      expect(player(s).contracts, isNot(contains(k)));
      expect(player(s).contractsCompleted, 1);
      expect(player(s).contractRefillAt, [s.time + refill]);

      fails(
        s,
        DeliverContractCommand('player', k.id, 'kora', n(10)),
        CommandError.unknownContract,
      );
      expect(player(s).credits, credits + n(5000), reason: 'paid once');
      expect(player(s).contractsCompleted, 1);
    });

    test('deliveries move whole units, so delivering what is shown left '
        'completes it', () {
      final s = fullBoard();
      final k = postOn(s, 'steel', 100, reward: 5000);
      final kora = s.body('kora')..stock['steel'] = n(40.7);
      final credits = player(s).credits;
      ok(s, DeliverContractCommand('player', k.id, 'kora', n(1000)));
      expect(k.delivered, n(40));
      expect(kora.stock['steel']!.toDouble(), closeTo(0.7, 1e-9));
      expect(k.remaining, n(60));
      kora.stock['steel'] = kora.stock['steel']! + k.remaining;
      ok(s, DeliverContractCommand('player', k.id, 'kora', n(60)));
      expect(player(s).credits, credits + n(5000));
      expect(kora.stock['steel']!.toDouble(), closeTo(0.7, 1e-9));
    });

    test('an amount asked for is cut to whole units', () {
      final s = fullBoard();
      final k = postOn(s, 'steel', 100);
      s.body('kora').stock['steel'] = n(50);
      ok(s, DeliverContractCommand('player', k.id, 'kora', n(12.5)));
      expect(k.delivered, n(12));
      final msg = fails(
        s,
        DeliverContractCommand('player', k.id, 'kora', n(0.5)),
        CommandError.invalidAmount,
      );
      expect(msg, 'Deliver at least 1 unit: deliveries move whole units');
      s.body('kora').stock['steel'] = n(0.9);
      expect(
        fails(
          s,
          DeliverContractCommand('player', k.id, 'kora', n(5)),
          CommandError.invalidAmount,
        ),
        'Kora has less than one whole Steel to deliver',
      );
    });

    test('what is left shows whole units even after a fractional delivery '
        'from an older save', () {
      final s = fullBoard();
      final k = postOn(s, 'steel', 100)..delivered = n(3.4);
      expect(k.remaining, n(97));
      s.body('kora').stock['steel'] = n(97);
      final credits = player(s).credits;
      ok(s, DeliverContractCommand('player', k.id, 'kora', k.remaining));
      expect(player(s).credits, greaterThan(credits));
    });

    test('a delivery that completes it exactly pays it', () {
      final s = fullBoard();
      final k = postOn(s, 'iron_ore', 30, reward: 75);
      s.body('kora').stock['iron_ore'] = n(30);
      final credits = player(s).credits;
      ok(s, DeliverContractCommand('player', k.id, 'kora', n(30)));
      expect(player(s).credits, credits + n(75));
      expect(player(s).contractsCompleted, 1);
    });

    test('reward credits count as lifetime earnings', () {
      final s = fullBoard();
      final k = postOn(s, 'iron_ore', 30, reward: 75);
      s.body('kora').stock['iron_ore'] = n(30);
      final earned = player(s).lifetimeCredits;
      ok(s, DeliverContractCommand('player', k.id, 'kora', n(30)));
      expect(player(s).lifetimeCredits, earned + n(75));
    });

    test('invalid deliveries change nothing', () {
      final s = fullBoard();
      final k = postOn(s, 'steel', 100);
      s.body('kora').stock['steel'] = n(50);
      fails(
        s,
        DeliverContractCommand('player', 'c999', 'kora', n(1)),
        CommandError.unknownContract,
      );
      fails(
        s,
        DeliverContractCommand('player', k.id, 'nowhere', n(1)),
        CommandError.unknownBody,
      );
      fails(
        s,
        DeliverContractCommand('player', k.id, 'brine', n(1)),
        CommandError.notOwner,
      );
      fails(
        s,
        DeliverContractCommand('player', k.id, 'kora', n(0)),
        CommandError.invalidAmount,
      );
      fails(
        s,
        DeliverContractCommand('player', k.id, 'kora', n(-5)),
        CommandError.invalidAmount,
      );
      s.body('kora').stock['steel'] = n(0);
      fails(
        s,
        DeliverContractCommand('player', k.id, 'kora', n(1)),
        CommandError.invalidAmount,
      );
      fails(
        s,
        DeliverContractCommand('ghost', k.id, 'kora', n(1)),
        CommandError.unknownFaction,
      );
    });

    test("another faction cannot deliver to or discard the player's", () {
      final s = fullBoard();
      s.factions.add(
        FactionState(
          id: 'rival',
          name: 'Rival',
          isPlayer: false,
          credits: n(0),
          baseCrew: 0,
        ),
      );
      s.body('brine').ownerId = 'rival';
      s.body('brine').stock['steel'] = n(100);
      final k = postOn(s, 'steel', 10);
      fails(
        s,
        DeliverContractCommand('rival', k.id, 'brine', n(10)),
        CommandError.unknownContract,
      );
      fails(
        s,
        DiscardContractCommand('rival', k.id),
        CommandError.unknownContract,
      );
    });

    test('commands round trip through JSON', () {
      for (final cmd in <Command>[
        DeliverContractCommand('player', 'c7', 'kora', n(12.5)),
        const DiscardContractCommand('player', 'c7'),
      ]) {
        final back = Command.fromJson(cmd.toJson());
        expect(back.toJson(), cmd.toJson());
        expect(back.runtimeType, cmd.runtimeType);
      }
      expect(
        DeliverContractCommand('p', 'c1', 'kora', n(1)).toJson()['cmd'],
        'deliverContract',
      );
      expect(
        const DiscardContractCommand('p', 'c1').toJson()['cmd'],
        'discardContract',
      );
    });
  });

  group('discard and refills', () {
    test('discard has no penalty and the slot refills after 4 h', () {
      final s = fullBoard();
      final f = player(s);
      final k = f.contracts.first;
      final credits = f.credits;
      final stock = jsonEncode(s.body('kora').toJson());
      final at = s.time;

      ok(s, DiscardContractCommand('player', k.id));
      expect(f.contracts, hasLength(2));
      expect(f.contracts, isNot(contains(k)));
      expect(f.credits, credits);
      expect(jsonEncode(s.body('kora').toJson()), stock);
      expect(f.contractsCompleted, 0);
      expect(f.contractRefillAt, [at + refill]);

      e.advance(s, refill - 60);
      expect(f.contracts, hasLength(2));
      e.advance(s, 60);
      expect(f.contracts, hasLength(3));
      expect(f.contracts.last.postedAt, at + refill);
      expect(f.contractRefillAt, isEmpty);
    });

    test('refills bank while away: 3 empty slots after 12 h are all '
        'refilled on return', () {
      final s = fullBoard();
      final f = player(s);
      final at = s.time;
      for (final k in List.of(f.contracts)) {
        ok(s, DiscardContractCommand('player', k.id));
      }
      expect(f.contracts, isEmpty);
      expect(f.contractRefillAt, [
        at + refill,
        at + refill * 2,
        at + refill * 3,
      ]);

      final away = e.catchUpOffline(s, 12 * 3600);
      expect(away.secondsSimulated, 43200);
      expect(f.contracts, hasLength(3));
      expect(f.contractRefillAt, isEmpty);
      expect(
        [for (final k in f.contracts) k.postedAt],
        [at + refill, at + refill * 2, at + refill * 3],
      );
      expect(away.contractsPosted, [for (final k in f.contracts) k.id]);
      expect(e.catchUpOffline(s, 3600).contractsPosted, isEmpty);
    });

    test('a refill queued behind others waits its turn', () {
      final s = fullBoard();
      final f = player(s);
      final at = s.time;
      ok(s, DiscardContractCommand('player', f.contracts.first.id));
      e.advance(s, 600);
      ok(s, DiscardContractCommand('player', f.contracts.first.id));
      // Banked after the first, not 4 h from now.
      expect(f.contractRefillAt, [at + refill, at + refill * 2]);
    });

    test('never more than 3 refills banked', () {
      final s = fullBoard();
      final f = player(s);
      f.contractRefillAt.addAll([1e9, 1e9, 1e9]);
      ok(s, DiscardContractCommand('player', f.contracts.first.id));
      expect(f.contractRefillAt, hasLength(3));
    });

    test('a contract on a resource no longer made blocks nothing and can '
        'be discarded', () {
      final s = fullBoard();
      final f = player(s);
      // Nobody makes reactor cores, and Kora holds none.
      final k = postOn(s, 'reactor_core', 50);
      final steel = f.lifetimeProduced['steel']!;

      // Commands and time carry on around it.
      ok(s, SetAutoSellCommand('player', 'kora', 'iron_ore', n(0)));
      e.advance(s, refill * 2);
      expect(f.contracts, contains(k));
      expect(f.lifetimeProduced['steel']! > steel, isTrue);
      fails(
        s,
        DeliverContractCommand('player', k.id, 'kora', n(1)),
        CommandError.invalidAmount,
      );

      ok(s, DiscardContractCommand('player', k.id));
      expect(f.contracts, isNot(contains(k)));
      e.advance(s, refill + 60);
      expect(f.contracts, hasLength(3), reason: 'its slot refilled');
      expect(
        f.contracts.where((x) => x.resourceId == 'reactor_core'),
        isEmpty,
        reason: 'reactor cores are neither made nor made from what is made',
      );
    });

    test('a contract whose producers were demolished can be discarded', () {
      final s = fullBoard();
      final f = player(s);
      final k = postOn(s, 'steel', 1e6);
      final smelter = s
          .body('kora')
          .buildings
          .firstWhere((b) => b.defId == 'smelter');
      ok(s, DemolishCommand('player', smelter.id));
      e.advance(s, refill);
      expect(f.contracts, contains(k));
      ok(s, DiscardContractCommand('player', k.id));
      expect(f.contracts, isNot(contains(k)));
    });
  });

  group('milestones', () {
    test('contractsCompleted counts completed contracts', () {
      final c = contentWith(
        (b) => (b['milestones']! as List).add({
          'id': 'first_order',
          'name': 'First Order Filled',
          'condition': {'type': 'contractsCompleted', 'count': 1},
        }),
      );
      final ce = GameEngine(c);
      final s = ce.newGame(1);
      ce.advance(s, refill * 2 + 60);
      final f = player(s);
      expect(f.reachedMilestones, isNot(contains('first_order')));
      final k = f.contracts.first;
      ok(s, DiscardContractCommand('player', k.id));
      ce.advance(s, 60);
      expect(
        f.reachedMilestones,
        isNot(contains('first_order')),
        reason: 'a discard is not a completion',
      );
      final next = f.contracts.first;
      s.body('kora').stock[next.resourceId] = next.quantity;
      ok(s, DeliverContractCommand('player', next.id, 'kora', next.quantity));
      ce.advance(s, 60);
      expect(f.reachedMilestones, contains('first_order'));
    });
  });

  group('saves', () {
    test('contracts survive save/load and copy()', () {
      final s = fullBoard();
      final f = player(s);
      ok(s, DiscardContractCommand('player', f.contracts.first.id));
      final k = f.contracts.first;
      s.body('kora').stock[k.resourceId] = n(1);
      ok(s, DeliverContractCommand('player', k.id, 'kora', n(1)));
      final text = SaveCodec.encode(s);
      final back = (SaveCodec.decode(text, content) as SaveOk).state;
      expect(SaveCodec.encode(back), text);
      expect(SaveCodec.encode(s.copy()), text);
      expect(player(back).contracts.first.delivered, n(1));
      expect(player(back).contractRefillAt, f.contractRefillAt);

      // A copy is independent.
      final copy = s.copy();
      player(copy).contracts.first.delivered = n(0);
      player(copy).contractRefillAt.clear();
      expect(SaveCodec.encode(s), text);
    });

    test('a save from before contracts loads with a board due to refill', () {
      final m = jsonDecode(encode(fullBoard())) as Map<String, Object?>;
      for (final f in (m['factions']! as List).cast<Map<String, Object?>>()) {
        f
          ..remove('contracts')
          ..remove('contractRefillAt')
          ..remove('contractsCompleted');
      }
      final r = SaveCodec.decode(jsonEncode(m), content);
      expect(r, isA<SaveOk>());
      final s = (r as SaveOk).state;
      expect(player(s).contracts, isEmpty);
      expect(player(s).contractsCompleted, 0);
      expect(player(s).contractRefillAt, [0, 0, 0]);
      e.advance(s, 60);
      expect(player(s).contracts, hasLength(3));
    });

    test('a save from before posts were counted counts every open and '
        'completed contract as posted', () {
      final s = fullBoard();
      final k = player(s).contracts.first;
      s.body('kora').stock[k.resourceId] = k.quantity;
      ok(s, DeliverContractCommand('player', k.id, 'kora', k.quantity));
      expect(player(s).contractsPosted, 3);
      final m = jsonDecode(encode(s)) as Map<String, Object?>;
      final f = (m['factions']! as List).cast<Map<String, Object?>>().first;
      expect(f['contractsPosted'], 3);
      f.remove('contractsPosted');
      final back = (SaveCodec.decode(jsonEncode(m), content) as SaveOk).state;
      // 2 open and 1 completed.
      expect(player(back).contractsPosted, 3);
      expect(player(back.copy()).contractsPosted, 3);
    });

    group('integrity:', () {
      List<Map<String, Object?>> list(Object? v) =>
          (v! as List).cast<Map<String, Object?>>();
      Map<String, Object?> me(Map<String, Object?> m) =>
          list(m['factions']).first;
      Map<String, Object?> first(Map<String, Object?> m) =>
          list(me(m)['contracts']).first;

      Map<String, Object?> board() =>
          jsonDecode(encode(fullBoard())) as Map<String, Object?>;

      final unknown = <String, void Function(Map<String, Object?>)>{
        'a contract for an unknown resource': (m) =>
            first(m)['resourceId'] = 'unobtainium',
        'a contract from an unknown template': (m) =>
            first(m)['templateId'] = 'nope',
      };
      for (final MapEntry(key: name, value: corrupt) in unknown.entries) {
        test(name, () {
          final m = board();
          corrupt(m);
          final r = SaveCodec.decode(jsonEncode(m), content);
          expect(r, isA<SaveError>());
          expect((r as SaveError).kind, SaveErrorKind.unknownContentId);
        });
      }

      final invalid = <String, void Function(Map<String, Object?>)>{
        'a negative quantity': (m) => first(m)['quantity'] = '-1',
        'a negative delivery': (m) => first(m)['delivered'] = '-1',
        'more delivered than asked for': (m) => first(m)
          ..['quantity'] = '10'
          ..['delivered'] = '11',
        'a negative reward': (m) => first(m)['rewardCredits'] = '-1',
        'posted after the save time': (m) =>
            first(m)['postedAt'] = (m['time']! as num) + 1,
        'posted at a negative time': (m) => first(m)['postedAt'] = -1,
        'four contracts': (m) {
          final ks = list(me(m)['contracts']);
          ks.add({...ks.first, 'id': 'c9000'});
          m['nextId'] = 9001;
        },
        'four refills': (m) => me(m)['contractRefillAt'] = [1, 2, 3, 4],
        'refills out of order': (m) => me(m)['contractRefillAt'] = [100, 50],
        'contracts and refills over 3 together': (m) {
          final ks = list(me(m)['contracts']);
          me(m)['contracts'] = ks.take(2).toList();
          me(m)['contractRefillAt'] = [1, 2];
        },
        'contracts and refills under 3 together': (m) {
          final ks = list(me(m)['contracts']);
          me(m)['contracts'] = ks.take(1).toList();
          me(m)['contractRefillAt'] = [1];
        },
        'a refill with no contracts': (m) {
          me(m)['contracts'] = <Object?>[];
          me(m)['contractRefillAt'] = [1];
        },
        'a negative refill time': (m) => me(m)['contractRefillAt'] = [-1],
        'a duplicate contract id': (m) {
          final ks = list(me(m)['contracts']);
          ks[1]['id'] = ks[0]['id'];
        },
        'nextId not above a contract id': (m) =>
            first(m)['id'] = 'c${m['nextId']}',
        'contract id suffix too large for an int': (m) =>
            first(m)['id'] = 'c99999999999999999999999',
        'negative contracts completed': (m) => me(m)['contractsCompleted'] = -1,
        'negative contracts posted': (m) => me(m)['contractsPosted'] = -1,
        'fewer posted than open and completed': (m) => me(m)
          ..['contractsCompleted'] = 2
          ..['contractsPosted'] = 4,
      };
      for (final MapEntry(key: name, value: corrupt) in invalid.entries) {
        test(name, () {
          final m = board();
          corrupt(m);
          final r = SaveCodec.decode(jsonEncode(m), content);
          expect(r, isA<SaveError>(), reason: name);
          expect((r as SaveError).kind, SaveErrorKind.invalidValue);
          expect(r.message, isNotEmpty);
        });
      }

      test('refills at the same time, or ascending, load', () {
        final m = board();
        me(m)['contracts'] = list(me(m)['contracts']).take(1).toList();
        me(m)['contractRefillAt'] = [5, 5];
        expect(SaveCodec.decode(jsonEncode(m), content), isA<SaveOk>());
        // A faction with no board has neither.
        me(m)['contracts'] = <Object?>[];
        me(m)['contractRefillAt'] = <Object?>[];
        expect(SaveCodec.decode(jsonEncode(m), content), isA<SaveOk>());
      });

      test('a fully delivered quantity of exactly the ask loads', () {
        final m = board();
        first(m)
          ..['quantity'] = '10'
          ..['delivered'] = '10';
        expect(SaveCodec.decode(jsonEncode(m), content), isA<SaveOk>());
      });
    });
  });
}
