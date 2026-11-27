import 'dart:io';
import 'dart:math' as math;

import 'package:game_core/game_core.dart';
import 'package:game_core/src/report/steady_revenue.dart'
    show measuredSaleRevenue, takeMegaprojectsFrom;
import 'package:test/test.dart';

import 'report_vs_away_test.dart' show withDriverFactor;

void main() {
  test('a re-run that takes the dry run\'s megaproject standing holds '
      'none of the goods they took', () {
    // At ×1.2 the Mass Driver finishes taking hull plates 13 minutes into
    // the run (stage 1.7 task 3, fix round 2): the plates it took must
    // leave the bodies' stock as they enter its progress.
    final c = withDriverFactor(1.2);
    final s =
        (SaveCodec.decode(
                  File(
                    'test/fixtures/balanced_d7_md12.json',
                  ).readAsStringSync(),
                  c,
                )
                as SaveOk)
            .state;
    final dry = s.copy();
    measuredSaleRevenue(dry, c, 'player');
    final to = s.copy();
    takeMegaprojectsFrom(dry, to, c, 'player');
    var moved = 0;
    final goods = {
      for (final m in c.megaprojects.values)
        for (final id in m.baseCost.keys)
          if (id != creditsKey) id,
    };
    for (final id in goods) {
      // What the dry run paid in leaves the stock, as far as the stock
      // the state held goes (the rest was made during the run).
      double paid(GameState x) =>
          c.megaprojects.values.fold(0.0, (t, m) => t + _paidIn(x, c, m, id));
      final took = paid(to) - paid(s);
      if (took > 0) moved++;
      final want = math.max(0.0, _held(s, id) - took);
      expect(
        _held(to, id),
        closeTo(want, 1e-6 * _held(s, id) + 1e-6),
        reason: id,
      );
    }
    expect(moved, greaterThan(0));
  });
}

/// Units of [id] [s]'s player has paid into [m]: the stages below its
/// delivery level in full, plus its progress toward that one.
double _paidIn(GameState s, Content c, MegaprojectDef m, String id) {
  final level = megaprojectDeliveryLevel(s, 'player', m);
  var total = 0.0;
  for (var l = 0; l < level; l++) {
    total += megaprojectCost(c, m, l)[id]?.toDouble() ?? 0;
  }
  return total +
      (s.faction('player').megaprojectProgress[m.id]?[id]?.toDouble() ?? 0);
}

/// Units of [id] on the player's bodies.
double _held(GameState s, String id) => s.bodies
    .where((b) => b.ownerId == 'player')
    .fold(0.0, (t, b) => t + (b.stock[id]?.toDouble() ?? 0));
