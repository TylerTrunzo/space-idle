import 'dart:io';

import 'package:game_core/game_core.dart';
import 'package:test/test.dart';

import '../state/helpers.dart';

/// Contracts beside the megaprojects a faction feeds goods on its own: a
/// contract is an optional side job and never silently starves a stage the
/// player is feeding.
void main() {
  final c = shippedContent();
  final e = GameEngine(c);

  /// The casual bot's state at its 144 h check-in, seed 1 (see
  /// report_vs_away_test.dart): the Orbital Station is fed near ready, its
  /// stage owes only survey drones, and contract c122 asks for 26,000 of
  /// them, holding every drone the bodies have.
  GameState fixture() =>
      (SaveCodec.decode(
                File('test/fixtures/casual_s1_144h.json').readAsStringSync(),
                c,
              )
              as SaveOk)
          .state;

  FactionState player(GameState s) => s.faction('player');

  /// The goods the megaprojects [f] feeds on its own owe now.
  Set<String> owedGoods(GameState s, FactionState f) => {
    for (final m in c.megaprojects.values)
      if (megaprojectGoodsFed(s, f, m) &&
          megaprojectTakesDeliveries(s, c, f.id, m))
        for (final id in megaprojectRemaining(s, c, f.id, m).keys)
          if (id != 'credits') id,
  };

  /// Resource ids of the contracts posted on a cleared board of [s] with
  /// every slot due, for each of [seeds], three rounds each (the board
  /// cleared between them).
  List<String> posted(GameState s, Iterable<int> seeds) => [
    for (final seed in seeds)
      ...() {
        final g = s.copy()..rngState = Rng(seed).state;
        final f = player(g);
        final ids = <String>[];
        for (var round = 0; round < 3; round++) {
          f.contracts.clear();
          f.contractRefillAt
            ..clear()
            ..addAll(List.filled(RulesDef.contractSlots, g.time));
          stepContracts(g, c, g.time);
          ids.addAll([for (final k in f.contracts) k.resourceId]);
        }
        return ids;
      }(),
  ];

  group('a contract never asks for a good a fed megaproject still owes', () {
    test('with the station fed and owing drones, none of 360 orders over '
        '40 seeds asks for drones', () {
      final s = fixture();
      expect(owedGoods(s, player(s)), {'survey_drone'});
      final ids = posted(s, Iterable<int>.generate(40, (i) => i + 1));
      expect(ids, hasLength(360));
      expect(ids, isNot(contains('survey_drone')));
    });

    test('with its goods not fed, the same seeds do ask for drones', () {
      // So the test above tells the rule apart from luck.
      final s = fixture();
      final f = player(s);
      // Near ready with no stage being fed: nothing is fed.
      f.megaprojectAuto['orbital_station'] = f
          .megaprojectAuto['orbital_station']!
          .feeding(null);
      expect(owedGoods(s, f), isEmpty);
      final ids = posted(s, Iterable<int>.generate(40, (i) => i + 1));
      expect(ids, contains('survey_drone'));
    });
  });

  group('a contract holding goods a fed megaproject owes', () {
    test('is reported, with the contract and what it holds', () {
      final s = fixture();
      final k = player(s).contracts.singleWhere((k) => k.id == 'c122');
      final blocks = buildFlowReport(s, c, 'player').contractBlocks;
      expect(blocks, hasLength(1));
      final b = blocks.single;
      expect(b.kind, BottleneckKind.contractBlocksDelivery);
      expect(b.contractId, k.id);
      expect(b.resourceId, 'survey_drone');
      expect(b.megaprojectId, 'orbital_station');
      expect(b.bodyId, isNull, reason: 'a contract holds on every body');
      // Every drone the bodies hold, as whole units, up to what is owed.
      var stock = const BigNum.zero();
      for (final body in s.bodies) {
        if (body.ownerId == 'player') {
          stock = stock + (body.stock['survey_drone'] ?? const BigNum.zero());
        }
      }
      final owed = megaprojectRemaining(
        s,
        c,
        'player',
        c.megaprojects['orbital_station']!,
      )['survey_drone']!;
      expect(b.heldForContract!.toDouble(), greaterThan(1000));
      expect(b.heldForContract! <= stock.floor().min(owed), isTrue);
      expect(b.firstSeenAt, s.time, reason: 'not seen before');
    });

    group('on a new game owing 469 reactor cores, with an order for 500', () {
      /// A new game whose station, fed goods always, owes 469 reactor
      /// cores, with Kora holding [stock] of them and the board one order
      /// for 500.
      GameState shape(num stock) {
        final s = e.newGame(1);
        final f = player(s)..contractRefillAt.clear();
        final station = c.megaprojects['orbital_station']!;
        f.megaprojectProgress['orbital_station'] = {
          'reactor_core':
              megaprojectCost(c, station, 0)['reactor_core']! -
              BigNum.from(469),
        };
        f.megaprojectAuto['orbital_station'] = const MegaprojectAuto(
          goods: GoodsFeedMode.always,
        );
        f.contracts.add(
          ContractState(
            id: s.newId('c'),
            templateId: c.contractTemplates.keys.first,
            resourceId: 'reactor_core',
            quantity: BigNum.from(500),
            rewardCredits: BigNum.from(1000),
            postedAt: 0,
          ),
        );
        s.body('kora').stock['reactor_core'] = BigNum.from(stock);
        return s;
      }

      test('600 held: the order keeps 369 of what is owed from the '
          'station', () {
        final b = buildFlowReport(shape(600), c, 'player').contractBlocks;
        expect(b.single.heldForContract, BigNum.from(369));
      });

      test('1,000 held: what is spare covers the station, so nothing is '
          'reported', () {
        expect(
          buildFlowReport(shape(1000), c, 'player').contractBlocks,
          isEmpty,
        );
      });
    });

    test('is among the grouped bottlenecks', () {
      final s = fixture();
      expect(
        buildFlowReport(s, c, 'player').groupedBottlenecks.where(
          (b) => b.kind == BottleneckKind.contractBlocksDelivery,
        ),
        hasLength(1),
      );
    });

    test('is not reported once the contract is discarded, or with the '
        "megaproject's goods not fed", () {
      final s = fixture();
      expect(
        e.apply(s, const DiscardContractCommand('player', 'c122')),
        isA<CommandOk>(),
      );
      expect(buildFlowReport(s, c, 'player').contractBlocks, isEmpty);
      final t = fixture();
      final f = player(t);
      // Near ready with no stage being fed: nothing is fed.
      f.megaprojectAuto['orbital_station'] = f
          .megaprojectAuto['orbital_station']!
          .feeding(null);
      expect(buildFlowReport(t, c, 'player').contractBlocks, isEmpty);
    });

    test('is tracked over time: it keeps the time it was first seen, and '
        'saves', () {
      final s = fixture();
      final start = s.time;
      e.advance(s, 3600);
      final b = buildFlowReport(s, c, 'player').contractBlocks.single;
      expect(b.contractId, 'c122');
      expect(b.firstSeenAt, start);
      final loaded = SaveCodec.decode(SaveCodec.encode(s), c);
      expect(loaded, isA<SaveOk>());
      expect(
        buildFlowReport(
          (loaded as SaveOk).state,
          c,
          'player',
        ).contractBlocks.single.firstSeenAt,
        start,
      );
    });
  });
}
