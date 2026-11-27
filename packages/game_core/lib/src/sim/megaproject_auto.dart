import '../commands/apply.dart';
import '../commands/command.dart';
import '../commands/outcome.dart';
import '../content/content.dart';
import '../num/big_num.dart';
import '../state/game_state.dart';
import 'market.dart';
import 'megaprojects.dart';
import 'projects.dart';
import 'step_cache.dart';

/// Game seconds between auto-deliveries: they run in a step that reaches
/// a whole multiple of it.
const double autoDeliverySeconds = 60;

/// Passes over a megaproject in one auto-delivery at most: the stage paid
/// for starts and the next is paid for, which then waits, so a third pass
/// finds nothing to do.
const int _maxPasses = 3;

/// What auto-delivery handed over in one step: faction id to megaproject
/// id to cost key ([creditsKey] or a resource id) to the amount, in the
/// order delivered; empty when nothing was.
typedef AutoDeliveries = Map<String, Map<String, Map<String, BigNum>>>;

/// Adds [more], megaproject id to cost key to amount, into [into], in the
/// order given.
void addDeliveries(
  Map<String, Map<String, BigNum>> into,
  Map<String, Map<String, BigNum>> more,
) {
  for (final MapEntry(key: m, value: got) in more.entries) {
    _addAmounts(into[m] ??= {}, got);
  }
}

/// [a] and [b], two [AutoDeliveries], together: [a]'s order, then what
/// only [b] has.
AutoDeliveries mergeDeliveries(AutoDeliveries a, AutoDeliveries b) {
  if (b.isEmpty) return a;
  if (a.isEmpty) return b;
  final out = <String, Map<String, Map<String, BigNum>>>{};
  for (final from in [a, b]) {
    for (final MapEntry(key: f, value: got) in from.entries) {
      addDeliveries(out[f] ??= {}, got);
    }
  }
  return out;
}

/// Feeds every faction's megaprojects the goods it set them to take on
/// their own (`FactionState.megaprojectAuto`), in a step of [dt] seconds
/// from `s.time`, and returns what went in. Credits go in later in the
/// step ([stepMegaprojectCredits]).
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
/// At the minute, the stages of megaprojects a faction feeds that are due
/// by then complete first ([stepProjects]), so a stage that ended within
/// a long step is done when the next is paid for, as it is in short
/// steps, and the next one starts at the same time either way.
///
/// Factions run in list order, their megaprojects in content order, while
/// each takes deliveries ([megaprojectTakesDeliveries]). Each owned body,
/// in body order, hands over the whole units it holds of what the stage
/// still needs above what it keeps ([autoDeliveryKeeps]: its local use,
/// the auto-sell rule's `keepAtLeast` and open contract needs, taken once
/// at the start of the faction's turn). Each delivery is a
/// [DeliverToMegaprojectCommand], so the rules of deliveries hold: a
/// stage paid in full starts, or waits for the one under way, and
/// deliveries go on to the stage after it.
///
/// Deliveries are made as at the first whole minute the step reaches, or
/// between minutes as at the step's end, so a stage they start runs from
/// then whatever the step. The engine runs it after production and cargo,
/// before the market; [cache] is the step's [StepCache] (one is made
/// otherwise).
AutoDeliveries stepMegaprojectAuto(
  GameState s,
  Content c,
  double dt, {
  StepCache? cache,
}) {
  if (!s.factions.any((f) => f.megaprojectAuto.isNotEmpty)) return const {};
  final out = <String, Map<String, Map<String, BigNum>>>{};
  _atMinute(s, dt, (onMinute) {
    if (onMinute) _completeFedStages(s, c);
    _deliverGoods(s, cache ?? StepCache(s, c), dt, out, overCapOnly: !onMinute);
  });
  return out;
}

/// Pays every faction's megaprojects set to take credits on their own
/// (`FactionState.megaprojectAuto` with a credit reserve) the whole
/// credits it holds above the reserve, in a step of [dt] seconds from
/// `s.time` that reaches a whole multiple of [autoDeliverySeconds]; a
/// step that reaches none pays nothing. Returns what went in.
///
/// The engine runs it after the market, so a step pays in what was earned
/// up to the minute, whatever its length. Payments are made as at the
/// minute, factions in list order, megaprojects in content order, each a
/// [DeliverToMegaprojectCommand]; a stage paid in full starts (or waits)
/// and the credits left go on to the one after it.
AutoDeliveries stepMegaprojectCredits(GameState s, Content c, double dt) {
  if (!s.factions.any(
    (f) => f.megaprojectAuto.values.any((a) => a.creditReserve != null),
  )) {
    return const {};
  }
  final out = <String, Map<String, Map<String, BigNum>>>{};
  _atMinute(s, dt, (onMinute) {
    if (onMinute) _payCredits(s, c, out);
  });
  return out;
}

/// Runs [run] with `s.time` at the first whole minute a step of [dt] from
/// `s.time` reaches (`onMinute`), or else at the step's end, then puts
/// the time back.
void _atMinute(GameState s, double dt, void Function(bool onMinute) run) {
  final from = (s.time / autoDeliverySeconds).floor();
  final onMinute = ((s.time + dt) / autoDeliverySeconds).floor() > from;
  final now = s.time;
  s.time = onMinute ? (from + 1) * autoDeliverySeconds : now + dt;
  try {
    run(onMinute);
  } finally {
    s.time = now;
  }
}

/// Completes the megaproject stages due by `s.time` of the megaprojects
/// their factions feed on their own.
void _completeFedStages(GameState s, Content c) {
  bool fed(ProjectState p) =>
      p.kind == ProjectKind.megaprojectStage &&
      s.faction(p.factionId).megaprojectAuto.containsKey(p.targetId);
  if (!s.projects.any((p) => p.finishAt <= s.time && fed(p))) return;
  stepProjects(s, c, only: fed);
}

/// Delivers [amounts] from [body] to [m] for [f] through
/// [DeliverToMegaprojectCommand], adding what went in to [got]; whether
/// anything did.
bool _deliver(
  GameState s,
  Content c,
  FactionState f,
  MegaprojectDef m,
  BodyState body,
  Map<String, BigNum> amounts,
  Map<String, BigNum> got,
) {
  final r = applyCommand(
    s,
    c,
    DeliverToMegaprojectCommand(f.id, m.id, body.id, amounts),
  );
  if (r case CommandOk(outcome: MegaprojectDelivered(:final delivered))) {
    _addAmounts(got, delivered);
    return true;
  }
  return false;
}

/// [stepMegaprojectAuto]'s deliveries of goods, at `s.time`, into [out];
/// with [overCapOnly], only of goods held above a body's storage cap.
void _deliverGoods(
  GameState s,
  StepCache cache,
  double dt,
  Map<String, Map<String, Map<String, BigNum>>> out, {
  required bool overCapOnly,
}) {
  final c = cache.c;
  for (final f in s.factions) {
    final goods = _fedGoods(c, f);
    if (goods.isEmpty) continue;
    final owned = [
      for (final b in s.bodies)
        if (b.ownerId == f.id) b,
    ];
    if (owned.isEmpty) continue;
    // Between minutes, only bodies holding a fed good above their cap.
    final over = overCapOnly ? _overCap(cache, goods, owned) : owned;
    if (over.isEmpty) continue;
    DeliveryKeeps? keeps;
    for (final m in c.megaprojects.values) {
      if (!(f.megaprojectAuto[m.id]?.goods ?? false)) continue;
      final got = <String, BigNum>{};
      for (var pass = 0; pass < _maxPasses; pass++) {
        if (!megaprojectTakesDeliveries(s, c, f.id, m)) break;
        final level = megaprojectDeliveryLevel(s, f.id, m);
        var delivered = false;
        keeps ??= autoDeliveryKeeps(s, cache, f, goods, dt);
        for (final body in over) {
          if (!megaprojectTakesDeliveries(s, c, f.id, m)) break;
          final amounts = <String, BigNum>{};
          for (final MapEntry(key: id, value: need) in megaprojectRemaining(
            s,
            c,
            f.id,
            m,
          ).entries) {
            if (id == creditsKey) continue;
            final spare = keeps.spare(
              body,
              id,
              atLeast: overCapOnly ? cache.cap(body) : null,
            );
            if (spare >= _oneUnit) amounts[id] = spare.min(need);
          }
          if (amounts.isNotEmpty && _deliver(s, c, f, m, body, amounts, got)) {
            delivered = true;
          }
        }
        // Another pass only once a stage was paid for in full.
        if (!delivered || megaprojectDeliveryLevel(s, f.id, m) == level) {
          break;
        }
      }
      if (got.isNotEmpty) (out[f.id] ??= {})[m.id] = got;
    }
  }
}

/// [stepMegaprojectCredits]'s payments, at `s.time`, into [out].
void _payCredits(
  GameState s,
  Content c,
  Map<String, Map<String, Map<String, BigNum>>> out,
) {
  for (final f in s.factions) {
    if (f.megaprojectAuto.isEmpty) continue;
    final payer = s.bodies.where((b) => b.ownerId == f.id).firstOrNull;
    if (payer == null) continue;
    for (final m in c.megaprojects.values) {
      final reserve = f.megaprojectAuto[m.id]?.creditReserve;
      if (reserve == null) continue;
      final got = <String, BigNum>{};
      for (var pass = 0; pass < _maxPasses; pass++) {
        if (!megaprojectTakesDeliveries(s, c, f.id, m)) break;
        final owed = megaprojectRemaining(s, c, f.id, m)[creditsKey];
        final spare = (f.credits - reserve).floor();
        if (owed == null || spare < _oneUnit) break;
        final level = megaprojectDeliveryLevel(s, f.id, m);
        if (!_deliver(s, c, f, m, payer, {creditsKey: spare.min(owed)}, got) ||
            megaprojectDeliveryLevel(s, f.id, m) == level) {
          break;
        }
      }
      if (got.isNotEmpty) (out[f.id] ??= {})[m.id] = got;
    }
  }
}

/// [owned] bodies that hold one of [goods] above their storage cap, in
/// body order.
List<BodyState> _overCap(
  StepCache cache,
  List<String> goods,
  List<BodyState> owned,
) => [
  for (final b in owned)
    if (goods.any((id) => (b.stock[id] ?? const BigNum.zero()) > cache.cap(b)))
      b,
];

/// The goods of every megaproject [f] feeds goods to on its own, in
/// content order, each once.
List<String> _fedGoods(Content c, FactionState f) {
  if (f.megaprojectAuto.isEmpty) return const [];
  return {
    for (final m in c.megaprojects.values)
      if (f.megaprojectAuto[m.id]?.goods ?? false)
        for (final id in m.baseCost.keys)
          if (id != creditsKey) id,
  }.toList();
}

/// Adds [more] into [into], key by key.
void _addAmounts(Map<String, BigNum> into, Map<String, BigNum> more) {
  for (final MapEntry(key: id, value: v) in more.entries) {
    into[id] = (into[id] ?? const BigNum.zero()) + v;
  }
}

final _oneUnit = BigNum.from(1);
