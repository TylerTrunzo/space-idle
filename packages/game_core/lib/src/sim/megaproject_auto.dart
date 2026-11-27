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
/// ([MegaprojectAuto.credits]) the whole credits it holds above its
/// shared reserve ([FactionState.autoPayReserve]), in a step of [dt]
/// seconds from `s.time` that reaches a whole multiple of
/// [autoDeliverySeconds]; a step that reaches none pays nothing. Returns
/// what went in.
///
/// The credits above the reserve are split evenly among the credit-fed
/// megaprojects that still owe credits for the stage they pay for (current
/// or queued), in whole credits, the odd ones to the first in content
/// order; a share a megaproject cannot use, owing less, goes on to the
/// others in another round. So every credit-fed megaproject progresses,
/// whatever its place in content order, and credits never go below the
/// reserve. Each payment is a [DeliverToMegaprojectCommand]: a stage paid
/// in full starts (or waits), and the next one, owing credits again, joins
/// the later rounds.
///
/// The engine runs it after the market, so a step pays in what was earned
/// up to the minute, whatever its length. Payments are made as at the
/// minute, factions in list order.
AutoDeliveries stepMegaprojectCredits(GameState s, Content c, double dt) {
  if (!s.factions.any((f) => f.megaprojectAuto.values.any((a) => a.credits))) {
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
    final fed = [
      for (final m in c.megaprojects.values)
        if (f.megaprojectAuto[m.id]?.credits ?? false) m,
    ];
    if (fed.isEmpty) continue;
    final payer = s.bodies.where((b) => b.ownerId == f.id).firstOrNull;
    if (payer == null) continue;
    final got = {for (final m in fed) m.id: <String, BigNum>{}};
    // Stages paid for in full per megaproject: at most [_maxPasses].
    final paid = {for (final m in fed) m.id: 0};
    for (var round = 0; round < fed.length * (_maxPasses + 1); round++) {
      final spare = (f.credits - f.autoPayReserve).floor();
      if (spare < _oneUnit) break;
      final owing = [
        for (final m in fed)
          if (paid[m.id]! < _maxPasses &&
              megaprojectTakesDeliveries(s, c, f.id, m))
            if (megaprojectRemaining(s, c, f.id, m)[creditsKey]
                case final owed?)
              (m, owed),
      ];
      if (owing.isEmpty) break;
      final n = BigNum.from(owing.length);
      final share = (spare / n).floor();
      // The odd credits, one each, to the first in content order.
      final odd = (spare - share * n).toDouble().floor().clamp(
        0,
        owing.length - 1,
      );
      var moved = false;
      for (final (i, (m, owed)) in owing.indexed) {
        final give = (i < odd ? share + _oneUnit : share).min(owed);
        if (give < _oneUnit) continue;
        final level = megaprojectDeliveryLevel(s, f.id, m);
        if (!_deliver(s, c, f, m, payer, {creditsKey: give}, got[m.id]!)) {
          continue;
        }
        moved = true;
        if (megaprojectDeliveryLevel(s, f.id, m) != level) {
          paid[m.id] = paid[m.id]! + 1;
        }
      }
      if (!moved) break;
    }
    for (final m in fed) {
      if (got[m.id]!.isNotEmpty) (out[f.id] ??= {})[m.id] = got[m.id]!;
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
