import 'dart:math' as math;

import '../content/content.dart';
import '../num/big_num.dart';
import '../report/flow_report.dart';
import '../rng.dart';
import '../state/game_state.dart';
import 'megaprojects.dart';
import 'production.dart';

/// Posts contracts on every faction's board whose slots are due to refill
/// by [now]: while it holds fewer than [RulesDef.contractSlots] contracts
/// and `now >= contractRefillAt[0]`, a contract is posted from the state's
/// [Rng] and that refill is used up.
///
/// A contract asks for a resource of a template's tiers that has a base
/// price, is not already on the board, and that the faction makes now:
/// its buildings' output of it ([FlowReport.producedPerSec], gross of what
/// they use) is at least the template's `minQuantity / quantitySeconds`
/// a second, so a trickle never gets an order. The template is drawn
/// first among those with such a resource, then the resource, each in
/// proportion to its weight: 1 for most goods, the template's
/// [ContractTemplateDef.lifeSupportWeight] for what a habitat consumes, so
/// orders seldom compete with crew upkeep; a template weighs as much as
/// its heaviest resource.
///
/// Its quantity is the gross rate × `quantitySeconds`, rounded to two
/// significant figures, at most the template's `maxQuantity` × (1 + the
/// faction's megaproject levels summed) and the largest storage cap among
/// its bodies (each rounded down to two figures), at least `minQuantity`,
/// in whole units ([twoSignificantFigures]). Its reward is `quantity ×
/// basePrice × rewardMultiplier` credits, at least `rewardIncomeSeconds`
/// of the faction's income ([FlowReport.creditsPerSec]) and at most
/// `rewardCapIncomeSeconds` of it. The first contract a faction is ever
/// offered ([FactionState.contractsPosted] 0) is exempt from the cap, as
/// is any posted while the faction earns nothing at all (an hour of no
/// income would make the order worthless).
///
/// When nothing qualifies, the refill stays due and is used once something
/// does. Whether a resource is made at all, and on the board, is
/// remembered per faction, for as long as the resources it has made
/// (`lifetimeProduced > 0`) and those on its board stay the same, so a
/// refill left waiting through a long catch-up costs one cheap comparison
/// a tick, not an eligibility scan; and the flow report is only built
/// when some building could make a candidate fast enough at full rate.
/// Neither ever changes what is posted. The RNG is drawn only when a
/// contract is posted, two numbers each time, and the flow report built
/// at most once per faction per call, so a tick without a due refill
/// costs next to nothing. A faction with no refills banked (every faction
/// but the player in stage 1.5) has no board.
///
/// The engine runs it at the end of every tick with the tick's end time,
/// so a refill due within the tick is posted in it.
void stepContracts(GameState s, Content c, double now) {
  if (c.contractTemplates.isEmpty) return;
  for (final f in s.factions) {
    FlowReport? report;
    while (f.contracts.length < RulesDef.contractSlots &&
        f.contractRefillAt.isNotEmpty &&
        f.contractRefillAt.first <= now) {
      final key = _EligibilityKey.of(c, f);
      if (_nothingEligible[f]?.matches(key) ?? false) break;
      final candidates = _candidates(c, f);
      if (candidates.isEmpty) {
        _nothingEligible[f] = key;
        break;
      }
      if (report == null && !_couldQualify(s, c, f, candidates)) break;
      final made = report ??= buildFlowReport(s, c, f.id);
      final choices = [
        for (final (t, ids) in candidates)
          if ([
                for (final id in ids)
                  if (made.producedPerSec(id) >= _floorRate(t)) id,
              ]
              case final ok when ok.isNotEmpty)
            (t, ok),
      ];
      if (choices.isEmpty) break;
      final lifeSupport = _lifeSupport(c);
      double weight(ContractTemplateDef t, String id) =>
          lifeSupport.contains(id) ? t.lifeSupportWeight : 1;
      final rng = Rng.fromState(s.rngState);
      final (template, resources) = _draw(rng, choices, (choice) {
        var most = 0.0;
        for (final id in choice.$2) {
          most = math.max(most, weight(choice.$1, id));
        }
        return most;
      });
      final resourceId = _draw(rng, resources, (id) => weight(template, id));
      s.rngState = rng.state;
      final quantity = _quantity(
        s,
        c,
        f,
        template,
        made.producedPerSec(resourceId),
      );
      f.contractRefillAt.removeAt(0);
      f.contracts.add(
        ContractState(
          id: s.newId('c'),
          templateId: template.id,
          resourceId: resourceId,
          quantity: quantity,
          rewardCredits: _reward(c, f, template, resourceId, quantity, made),
          postedAt: now,
        ),
      );
      f.contractsPosted++;
    }
  }
}

/// Ids of the resources a habitat in [c] consumes, which contracts weigh
/// at [ContractTemplateDef.lifeSupportWeight]. Worked out once per content.
Set<String> _lifeSupport(Content c) => _lifeSupportOf[c] ??= {
  for (final b in c.buildings.values)
    if (b.kind == BuildingKind.habitat) ...b.inputs.keys,
};

final _lifeSupportOf = Expando<Set<String>>('lifeSupport');

/// One of [items], drawn from [rng] in proportion to [weight] (all above
/// zero): one number drawn. With equal weights it is the item
/// `rng.nextInt(items.length)` would pick.
T _draw<T>(Rng rng, List<T> items, double Function(T) weight) {
  var total = 0.0;
  for (final x in items) {
    total += weight(x);
  }
  final at = rng.nextDouble() * total;
  var sum = 0.0;
  for (final x in items) {
    sum += weight(x);
    if (at < sum) return x;
  }
  return items.last;
}

/// Units a second [t] needs of a resource to ask for it at all: its
/// `minQuantity` over its `quantitySeconds`.
BigNum _floorRate(ContractTemplateDef t) =>
    t.minQuantity.mulDouble(1 / t.quantitySeconds);

/// Whether a building of [f] at full rate, fully crewed and housed, could
/// make a candidate of [candidates] at its template's [_floorRate]: what
/// the flow report shows is never more, so when none could, nothing
/// qualifies and the report need not be built.
bool _couldQualify(
  GameState s,
  Content c,
  FactionState f,
  List<(ContractTemplateDef, List<String>)> candidates,
) {
  final bonuses = bonusesFor(s, c, f.id);
  final most = <String, BigNum>{};
  for (final body in s.bodies) {
    if (body.ownerId != f.id) continue;
    for (final b in body.buildings) {
      final out = fullRateFlow(c, body, b, 1, 1, bonuses: bonuses).outputs;
      for (final MapEntry(key: id, value: v) in out.entries) {
        most[id] = (most[id] ?? const BigNum.zero()) + v;
      }
    }
  }
  return candidates.any(
    (k) =>
        k.$2.any((id) => (most[id] ?? const BigNum.zero()) >= _floorRate(k.$1)),
  );
}

/// What a contract from [t] for [quantity] of [resourceId] pays [f]: by
/// quantity, at least `rewardIncomeSeconds` and, but for the first
/// contract [f] is offered and while it earns nothing, at most
/// `rewardCapIncomeSeconds` of [report]'s income.
BigNum _reward(
  Content c,
  FactionState f,
  ContractTemplateDef t,
  String resourceId,
  BigNum quantity,
  FlowReport report,
) {
  final income = report.creditsPerSec;
  final byQuantity =
      quantity *
      c.resources[resourceId]!.basePrice.mulDouble(t.rewardMultiplier);
  final reward = byQuantity.max(income.mulDouble(t.rewardIncomeSeconds));
  final cap = t.rewardCapIncomeSeconds;
  if (cap == null || f.contractsPosted == 0 || income.isZero) return reward;
  return reward.min(income.mulDouble(cap));
}

/// What decides whether any contract can be posted to a board: the
/// resources its faction has made and those already on the board, with the
/// content they were read against.
final class _EligibilityKey {
  _EligibilityKey(this._content, this._made, this._onBoard);

  /// The key for [f] against [c]; resources in content order.
  factory _EligibilityKey.of(Content c, FactionState f) => _EligibilityKey(c, [
    for (final id in c.resources.keys)
      if ((f.lifetimeProduced[id] ?? const BigNum.zero()) > const BigNum.zero())
        id,
  ], [for (final k in f.contracts) k.resourceId]..sort());

  final Content _content;
  final List<String> _made;
  final List<String> _onBoard;

  /// Whether [o] is the same key.
  bool matches(_EligibilityKey o) =>
      identical(_content, o._content) &&
      _sameIds(_made, o._made) &&
      _sameIds(_onBoard, o._onBoard);
}

bool _sameIds(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// The key under which a faction last had no contract to post. It lives
/// outside [FactionState], so it is never saved or copied: a loaded or
/// copied state simply scans once.
final _nothingEligible = Expando<_EligibilityKey>('nothingEligible');

/// Banks a refill for a slot of [f]'s board freed at [now], by a contract
/// completed or discarded: `max(now, last refill banked) +
/// contractRefillSeconds`, so slots freed together refill one after
/// another. Nothing is banked once [RulesDef.contractSlots] refills are.
void freeContractSlot(FactionState f, Content c, double now) {
  final refills = f.contractRefillAt;
  if (refills.length >= RulesDef.contractSlots) return;
  final last = refills.isEmpty || refills.last < now ? now : refills.last;
  refills.add(last + c.rules.contractRefillSeconds);
}

/// Units a contract from [t] asks [f] for, given its gross production
/// [rate] of the resource: `rate × quantitySeconds` rounded to two
/// significant figures, at most the largest storage cap among the bodies
/// [f] owns and [ContractTemplateDef.maxQuantity] × (1 + [f]'s megaproject
/// levels summed) (each rounded down to two figures), and at least
/// [ContractTemplateDef.minQuantity]; then rounded down to whole units, at
/// least 1.
BigNum _quantity(
  GameState s,
  Content c,
  FactionState f,
  ContractTemplateDef t,
  BigNum rate,
) {
  BigNum? largest;
  for (final b in s.bodies) {
    if (b.ownerId != f.id) continue;
    final cap = storageCap(s, c, b);
    if (largest == null || cap > largest) largest = cap;
  }
  final levels = f.megaprojectLevels.values.fold(0, (t, v) => t + v);
  final most = t.maxQuantity?.mulDouble(1.0 + levels);
  final ceiling = largest == null || most == null
      ? largest ?? most
      : largest.min(most);
  var q = twoSignificantFigures(rate.mulDouble(t.quantitySeconds));
  if (ceiling != null) q = q.min(_twoFiguresDown(ceiling));
  // Deliveries move whole units, so the quantity is whole, at least 1.
  return q.max(t.minQuantity).floor().max(BigNum.from(1));
}

/// [v], positive, rounded down to two significant figures.
BigNum _twoFiguresDown(BigNum v) {
  final figures = (v.mantissa * 10 + 1e-9).floor();
  return BigNum.parse('${figures}e${v.exponent - 1}');
}

/// [v] rounded to two significant figures, halves away from zero; zero
/// stays zero.
BigNum twoSignificantFigures(BigNum v) {
  if (v.isZero) return v;
  // The mantissa is in [1, 10), so tenths of it are the second figure.
  final figures = (v.mantissa * 10).round();
  return BigNum.parse('${figures}e${v.exponent - 1}');
}

/// Each template, in content order, with the resources a contract from it
/// may ask [f] for, made rate aside, in content order: priced, made at
/// some time (`lifetimeProduced > 0`) and not on the board; templates with
/// none left out.
List<(ContractTemplateDef, List<String>)> _candidates(
  Content c,
  FactionState f,
) {
  final onBoard = {for (final k in f.contracts) k.resourceId};
  final eligible = [
    for (final r in c.resources.values)
      if (!r.basePrice.isZero &&
          !onBoard.contains(r.id) &&
          (f.lifetimeProduced[r.id] ?? const BigNum.zero()) >
              const BigNum.zero())
        r,
  ];
  return [
    for (final t in c.contractTemplates.values)
      if ([
            for (final r in eligible)
              if (r.tier >= t.minTier && r.tier <= t.maxTier) r.id,
          ]
          case final ids when ids.isNotEmpty)
        (t, ids),
  ];
}
