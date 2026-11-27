import '../commands/apply.dart';
import '../commands/command.dart';
import '../commands/outcome.dart';
import '../content/content.dart';
import '../num/big_num.dart';
import '../state/game_state.dart';
import 'market.dart';
import 'megaprojects.dart';
import 'production.dart';

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
/// It delivers in full in a step that reaches a whole multiple of
/// [autoDeliverySeconds] of game time, so at the same game times for any
/// step size, a catch-up included. Between those times auto-sell holds
/// back what the megaprojects still need ([autoSellKeep]'s megaproject
/// hold), so short steps leave as much for it as long ones, up to a
/// body's storage cap; what a body holds of such a good above its cap,
/// which auto-sell would sell or the cap waste, goes in at once, in any
/// step. So a body that makes more than it can store in a minute feeds
/// as much in short steps as in long ones.
///
/// Factions run in list order, their megaprojects in content order, while
/// each takes deliveries ([megaprojectTakesDeliveries]). With goods on,
/// each owned body, in body order, hands over the whole units it holds of
/// what the stage still needs above what it keeps ([autoDeliveryKeeps]:
/// its local use, the auto-sell rule's `keepAtLeast` and open contract
/// needs, taken once at the start of the faction's turn). With a credit
/// reserve, the whole credits above the reserve go in at the minute; with
/// none, no credits do. Each delivery is a [DeliverToMegaprojectCommand],
/// so the rules of deliveries hold: a stage paid in full starts, or waits
/// for the one under way, and deliveries go on to the stage after it.
///
/// Deliveries are made as at the first whole minute the step reaches, or
/// between minutes as at the step's end, so a stage they start runs from
/// then whatever the step. The engine runs it after production and cargo,
/// before the market.
AutoDeliveries stepMegaprojectAuto(GameState s, Content c, double dt) {
  final out = <String, Map<String, Map<String, BigNum>>>{};
  final from = (s.time / autoDeliverySeconds).floor();
  final onMinute = ((s.time + dt) / autoDeliverySeconds).floor() > from;
  final now = s.time;
  s.time = onMinute ? (from + 1) * autoDeliverySeconds : now + dt;
  try {
    _deliverAll(s, c, dt, out, overCapOnly: !onMinute);
  } finally {
    s.time = now;
  }
  return out;
}

/// [stepMegaprojectAuto]'s deliveries, at `s.time`, into [out]; with
/// [overCapOnly], only of goods held above a body's storage cap, and no
/// credits.
void _deliverAll(
  GameState s,
  Content c,
  double dt,
  Map<String, Map<String, Map<String, BigNum>>> out, {
  required bool overCapOnly,
}) {
  for (final f in s.factions) {
    if (f.megaprojectAuto.isEmpty) continue;
    final owned = [
      for (final b in s.bodies)
        if (b.ownerId == f.id) b,
    ];
    if (owned.isEmpty) continue;
    final caps = overCapOnly ? _overCap(s, c, f, owned) : null;
    if (caps != null && caps.isEmpty) continue;
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

      if (overCapOnly && !auto.goods) continue;
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
              var keep = keeps[body.id]![id]!;
              if (caps != null) keep = keep.max(caps[body.id]!);
              final spare = ((body.stock[id] ?? const BigNum.zero()) - keep)
                  .floor();
              if (spare >= _oneUnit) amounts[id] = spare.min(need);
            }
            if (amounts.isNotEmpty) deliver(body, amounts);
          }
        }
        if (auto.creditReserve case final reserve?
            when !overCapOnly && megaprojectTakesDeliveries(s, c, f.id, m)) {
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

/// Body id to storage cap, for [f]'s [owned] bodies that hold a good it
/// feeds to a megaproject on its own above their cap; empty when none
/// does.
Map<String, BigNum> _overCap(
  GameState s,
  Content c,
  FactionState f,
  List<BodyState> owned,
) {
  final goods = _fedGoods(c, f);
  if (goods.isEmpty) return const {};
  final caps = <String, BigNum>{};
  for (final b in owned) {
    final cap = storageCap(s, c, b);
    if (goods.any((id) => (b.stock[id] ?? const BigNum.zero()) > cap)) {
      caps[b.id] = cap;
    }
  }
  if (caps.isEmpty) return const {};
  return {for (final b in owned) b.id: caps[b.id] ?? storageCap(s, c, b)};
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
