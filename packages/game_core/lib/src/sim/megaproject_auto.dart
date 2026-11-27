import '../commands/apply.dart';
import '../commands/command.dart';
import '../commands/outcome.dart';
import '../content/content.dart';
import '../num/big_num.dart';
import '../state/game_state.dart';
import 'market.dart';
import 'megaprojects.dart';

/// Game seconds between auto-deliveries: they run in a step that reaches
/// a whole multiple of it.
const double autoDeliverySeconds = 60;

/// Passes over a megaproject in one auto-delivery at most: the stage paid
/// for starts and the next is paid for, which then waits, so a third pass
/// finds nothing to do.
const int _maxPasses = 3;

/// What auto-delivery handed over in one step: faction id to megaproject
/// id to cost key (`credits` or a resource id) to the amount, in the
/// order delivered; empty when nothing was.
typedef AutoDeliveries = Map<String, Map<String, Map<String, BigNum>>>;

/// Feeds every faction's megaprojects that it set to feed on their own
/// (`FactionState.megaprojectAuto`), in a step of [dt] seconds from
/// `s.time`, and returns what went in.
///
/// It runs only in a step that reaches a whole multiple of
/// [autoDeliverySeconds] of game time, so it runs at the same game times
/// for any step size, a catch-up included; between those times auto-sell
/// holds back what the megaprojects still need ([autoSellKeep]'s
/// megaproject hold), so short steps leave as much for it as long ones.
///
/// Factions run in list order, their megaprojects in content order, while
/// each takes deliveries ([megaprojectTakesDeliveries]). With goods on,
/// each owned body, in body order, hands over the whole units it holds of
/// what the stage still needs above what it keeps ([autoDeliveryKeeps]:
/// its local use, the auto-sell rule's `keepAtLeast` and open contract
/// needs, taken once at the start of the faction's turn). With a credit
/// reserve, the whole credits above the reserve go in; with none, no
/// credits do. Each delivery is a [DeliverToMegaprojectCommand], so the
/// rules of deliveries hold: a stage paid in full starts, or waits for the
/// one under way, and deliveries go on to the stage after it.
///
/// Deliveries are made as at that first whole minute, so a stage they
/// start runs from it whatever the step. The engine runs it after
/// production and cargo, before the market.
AutoDeliveries stepMegaprojectAuto(GameState s, Content c, double dt) {
  final out = <String, Map<String, Map<String, BigNum>>>{};
  final from = (s.time / autoDeliverySeconds).floor();
  if (((s.time + dt) / autoDeliverySeconds).floor() <= from) return out;
  // Deliveries happen at the first whole minute the step reaches, so a
  // stage they start runs from it, as with any step size.
  final now = s.time;
  s.time = (from + 1) * autoDeliverySeconds;
  try {
    _deliverAll(s, c, dt, out);
  } finally {
    s.time = now;
  }
  return out;
}

/// [stepMegaprojectAuto]'s deliveries, at `s.time`, into [out].
void _deliverAll(
  GameState s,
  Content c,
  double dt,
  Map<String, Map<String, Map<String, BigNum>>> out,
) {
  for (final f in s.factions) {
    if (f.megaprojectAuto.isEmpty) continue;
    final owned = [
      for (final b in s.bodies)
        if (b.ownerId == f.id) b,
    ];
    if (owned.isEmpty) continue;
    Map<String, Map<String, BigNum>>? keeps;
    for (final m in c.megaprojects.values) {
      final auto = f.megaprojectAuto[m.id];
      if (auto == null) continue;
      final got = <String, BigNum>{};
      var deliveries = 0;
      void deliver(BodyState body, Map<String, BigNum> amounts) {
        final r = applyCommand(
          s,
          c,
          DeliverToMegaprojectCommand(f.id, m.id, body.id, amounts),
        );
        if (r case CommandOk(outcome: MegaprojectDelivered(:final delivered))) {
          deliveries++;
          for (final MapEntry(key: id, value: v) in delivered.entries) {
            got[id] = (got[id] ?? const BigNum.zero()) + v;
          }
        }
      }

      for (var pass = 0; pass < _maxPasses; pass++) {
        if (!megaprojectTakesDeliveries(s, c, f.id, m)) break;
        final level = megaprojectDeliveryLevel(s, f.id, m);
        final before = deliveries;
        if (auto.goods) {
          keeps ??= autoDeliveryKeeps(s, c, f, _fedGoods(c, f), dt);
          for (final body in owned) {
            if (!megaprojectTakesDeliveries(s, c, f.id, m)) break;
            final amounts = <String, BigNum>{};
            for (final MapEntry(key: id, value: need) in megaprojectRemaining(
              s,
              c,
              f.id,
              m,
            ).entries) {
              if (id == _credits) continue;
              final spare =
                  ((body.stock[id] ?? const BigNum.zero()) -
                          keeps[body.id]![id]!)
                      .floor();
              if (spare >= _oneUnit) amounts[id] = spare.min(need);
            }
            if (amounts.isNotEmpty) deliver(body, amounts);
          }
        }
        if (auto.creditReserve case final reserve?
            when megaprojectTakesDeliveries(s, c, f.id, m)) {
          final owed = megaprojectRemaining(s, c, f.id, m)[_credits];
          final spare = (f.credits - reserve).floor();
          if (owed != null && spare >= _oneUnit) {
            deliver(owned.first, {_credits: spare.min(owed)});
          }
        }
        // Another pass only once a stage was paid for in full.
        if (deliveries == before ||
            megaprojectDeliveryLevel(s, f.id, m) == level) {
          break;
        }
      }
      if (got.isNotEmpty) (out[f.id] ??= {})[m.id] = got;
    }
  }
}

/// The goods of every megaproject [f] feeds goods to on its own, in
/// content order, each once.
List<String> _fedGoods(Content c, FactionState f) => {
  for (final m in c.megaprojects.values)
    if (f.megaprojectAuto[m.id]?.goods ?? false)
      for (final id in m.baseCost.keys)
        if (id != _credits) id,
}.toList();

const _credits = 'credits';

final _oneUnit = BigNum.from(1);
