import 'package:game_core/game_core.dart';
import 'package:test/test.dart';

import '../state/helpers.dart';

BigNum n(num v) => BigNum.from(v);

/// The shipped content with only [conditions] as milestones, ids `m0`, `m1`
/// and so on in order.
Content contentWith(List<Map<String, Object?>> conditions) {
  final b = shippedBundle();
  b['milestones'] = [
    for (final (i, c) in conditions.indexed)
      {'id': 'm$i', 'name': 'Milestone $i', 'condition': c},
  ];
  return (Content.fromBundle(b) as ContentOk).content;
}

/// Errors loading the shipped content with [conditions] as its milestones.
List<String> errorsFor(List<Map<String, Object?>> conditions) {
  final b = shippedBundle();
  b['milestones'] = [
    for (final (i, c) in conditions.indexed)
      {'id': 'm$i', 'name': 'Milestone $i', 'condition': c},
  ];
  return switch (Content.fromBundle(b)) {
    ContentOk() => const [],
    ContentInvalid(:final errors) => errors,
  };
}

void main() {
  /// Ids of [conditions] a new game reaches after [prepare] and [seconds] of
  /// 1 s ticks (`m0`, `m1` and so on).
  Set<String> reached(
    List<Map<String, Object?>> conditions, {
    void Function(GameState s)? prepare,
    int seconds = 1,
    double step = 1,
  }) {
    final e = GameEngine(contentWith(conditions));
    final s = e.newGame(1);
    prepare?.call(s);
    for (var i = 0; i < seconds; i++) {
      e.tick(s, step);
    }
    return s.faction('player').reachedMilestones;
  }

  group('productionRate', () {
    Map<String, Object?> rate(String per) => {
      'type': 'productionRate',
      'resource': 'copper_ore',
      'perSec': per,
    };

    test('compares the empire net rate a second with the target', () {
      // One mine makes 2 copper ore every 5 s: 0.4 a second.
      expect(reached([rate('0.3'), rate('0.5')], seconds: 61), {'m0'});
    });

    test('is checked once a game minute', () {
      final e = GameEngine(contentWith([rate('0.3')]));
      final s = e.newGame(1);
      e.tick(s, 30);
      expect(s.faction('player').reachedMilestones, isEmpty);
      e.tick(s, 30);
      expect(s.faction('player').reachedMilestones, {'m0'});
    });

    test('counts what buildings use against what they make', () {
      final c = {
        'type': 'productionRate',
        'resource': 'iron_ore',
        'perSec': '0.3',
      };
      // The smelter uses what the iron mine makes.
      expect(reached([c], seconds: 61), isEmpty);
    });

    test('rejects an unknown resource and a zero rate', () {
      expect(
        errorsFor([
          {'type': 'productionRate', 'resource': 'mud', 'perSec': '1'},
        ]),
        ['milestones.m0.condition.resource: unknown resource \'mud\''],
      );
      expect(errorsFor([rate('0')]), hasLength(1));
    });
  });

  group('buildingTypesBuilt', () {
    test('counts distinct types over all bodies', () {
      final conds = [
        {'type': 'buildingTypesBuilt', 'count': 2},
        {'type': 'buildingTypesBuilt', 'count': 3},
      ];
      expect(reached(conds), {'m0'});
      // A second mine adds no type; a wire mill does.
      final e = GameEngine(contentWith(conds));
      final s = e.newGame(1);
      s.faction('player').credits = n(1e6);
      for (final d in ['mine', 'mine']) {
        e.apply(
          s,
          BuildCommand('player', 'kora', d, depositResourceId: 'iron_ore'),
        );
      }
      e.tick(s, 1);
      expect(s.faction('player').reachedMilestones, {'m0'});
      e.apply(s, const BuildCommand('player', 'kora', 'wire_mill'));
      e.tick(s, 1);
      expect(s.faction('player').reachedMilestones, {'m0', 'm1'});
    });

    test('cannot ask for more types than exist', () {
      final all = shippedContent().buildings.length;
      expect(
        errorsFor([
          {'type': 'buildingTypesBuilt', 'count': all + 1},
        ]),
        ['milestones.m0.condition.count: above the $all building types'],
      );
    });
  });

  group('crewTotal', () {
    test('counts supported crew', () {
      final conds = [
        {'type': 'crewTotal', 'count': 20},
        {'type': 'crewTotal', 'count': 21},
      ];
      expect(reached(conds), {'m0'});
      expect(
        reached(conds, prepare: (s) => s.faction('player').baseCrew = 21),
        {'m0', 'm1'},
      );
    });
  });

  group('megaprojectLevel', () {
    test('compares a megaproject level', () {
      final conds = [
        {
          'type': 'megaprojectLevel',
          'megaproject': 'orbital_station',
          'level': 2,
        },
        {
          'type': 'megaprojectLevel',
          'megaproject': 'orbital_station',
          'level': 3,
        },
      ];
      expect(reached(conds), isEmpty);
      expect(
        reached(
          conds,
          prepare: (s) =>
              s.faction('player').megaprojectLevels['orbital_station'] = 2,
        ),
        {'m0'},
      );
    });

    test('rejects an unknown megaproject', () {
      expect(
        errorsFor([
          {'type': 'megaprojectLevel', 'megaproject': 'dyson', 'level': 1},
        ]),
        ["milestones.m0.condition.megaproject: unknown megaproject 'dyson'"],
      );
    });
  });

  group('bodiesSurveyed', () {
    test(
      'counts hidden bodies revealed, not the ones in sight at the start',
      () {
        final conds = [
          {'type': 'bodiesSurveyed', 'count': 1},
          {'type': 'bodiesSurveyed', 'count': 2},
        ];
        expect(reached(conds), isEmpty);
        expect(
          reached(conds, prepare: (s) => s.body('tessaly').surveyed = true),
          {'m0'},
        );
        expect(
          reached(
            conds,
            prepare: (s) {
              s.body('tessaly').surveyed = true;
              s.body('dusk_cairn').surveyed = true;
            },
          ),
          {'m0', 'm1'},
        );
      },
    );

    test('cannot ask for more than the hidden bodies', () {
      expect(
        errorsFor([
          {'type': 'bodiesSurveyed', 'count': 3},
        ]),
        ['milestones.m0.condition.count: above the 2 hidden bodies'],
      );
    });
  });

  group('zeroWasteFor', () {
    const cond = {'type': 'zeroWasteFor', 'seconds': 300};

    test('is reached after the time without waste', () {
      final e = GameEngine(contentWith([cond]));
      final s = e.newGame(1);
      for (var i = 0; i < 4; i++) {
        e.tick(s, 60);
      }
      expect(s.faction('player').reachedMilestones, isEmpty);
      e.tick(s, 60);
      expect(s.faction('player').reachedMilestones, {'m0'});
      expect(s.faction('player').wasteFreeSince, 0);
    });

    test('waste restarts the count', () {
      final c = contentWith([cond]);
      final e = GameEngine(c);
      final s = e.newGame(1);
      e.tick(s, 60);
      // A full store wastes what the mine makes.
      final kora = s.body('kora');
      kora.stock['copper_ore'] = storageCap(s, c, kora);
      e.tick(s, 60);
      expect(s.faction('player').wasteFreeSince, 120);
      kora.stock['copper_ore'] = n(0);
      for (var i = 0; i < 4; i++) {
        e.tick(s, 60);
      }
      expect(s.faction('player').reachedMilestones, isEmpty);
      e.tick(s, 60);
      expect(s.faction('player').reachedMilestones, {'m0'});
    });

    test('an empire with no buildings is not waste-free', () {
      final e = GameEngine(contentWith([cond]));
      final s = e.newGame(1);
      s.body('kora').buildings.clear();
      for (var i = 0; i < 10; i++) {
        e.tick(s, 60);
      }
      expect(s.faction('player').reachedMilestones, isEmpty);
      expect(s.faction('player').wasteFreeSince, 600);
    });

    test('rejects zero seconds', () {
      expect(
        errorsFor([
          {'type': 'zeroWasteFor', 'seconds': 0},
        ]),
        ['milestones.m0.condition.seconds: must be > 0'],
      );
    });
  });

  group('creditsEarned', () {
    test('thresholds past a billion', () {
      final conds = [
        {'type': 'creditsEarned', 'amount': '1e10'},
        {'type': 'creditsEarned', 'amount': '1e11'},
        {'type': 'creditsEarned', 'amount': '1e12'},
      ];
      expect(
        reached(
          conds,
          prepare: (s) => s.faction('player').lifetimeCredits = n(1e11),
        ),
        {'m0', 'm1'},
      );
      expect(
        reached(
          conds,
          prepare: (s) =>
              s.faction('player').lifetimeCredits = BigNum.parse('1e12'),
        ),
        {'m0', 'm1', 'm2'},
      );
    });
  });

  group('wasteFreeSince in saves', () {
    final content = shippedContent();
    final e = GameEngine(content);

    test('round-trips and copies', () {
      final s = e.newGame(1);
      e.tick(s, 10);
      s.faction('player').wasteFreeSince = 7;
      final back =
          (SaveCodec.decode(SaveCodec.encode(s), content) as SaveOk).state;
      expect(back.faction('player').wasteFreeSince, 7);
      expect(s.copy().faction('player').wasteFreeSince, 7);
    });
  });
}
