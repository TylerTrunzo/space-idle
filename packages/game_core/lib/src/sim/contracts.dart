import 'dart:math' as math;

import '../content/content.dart';
import '../num/big_num.dart';
import '../report/flow_report.dart';
import '../rng.dart';
import '../state/game_state.dart';
import 'market.dart';
import 'megaprojects.dart';
import 'production.dart';

/// Posts contracts on every faction's board whose slots are due to refill
/// by [now]: while it holds fewer than [RulesDef.contractSlots] contracts
/// and `now >= contractRefillAt[0]`, a contract is posted from the state's
/// [Rng] and that refill is used up.
///
/// A contract asks for a resource of a template's tiers that has a base
/// price, is not already on the board, and that the faction makes now
/// from steady supply: its buildings' steady output of it
/// ([FlowReport.steadyProducedPerSec], gross of what they use, never fed
/// from a stock nothing refills) is at least the template's `minQuantity /
/// quantitySeconds` a second, so neither a trickle nor a stockpile gets
/// an order. Of those, only the goods worth an order are drawn from
/// ([_worthChoosing]): the largest order the faction could be asked for
/// sells for at least `quantityIncomeSecondsMin` of its income at today's
/// price; when none is, the three whose largest order is worth most. The
/// template is drawn
/// first among those with such a resource, then the resource, each in
/// proportion to its weight: 1 for most goods, the template's
/// [ContractTemplateDef.lifeSupportWeight] for what a habitat consumes, so
/// orders seldom compete with crew upkeep; a template weighs as much as
/// its heaviest resource.
///
/// Its quantity sells, at the current price ([price]), for the faction's
/// income basis ([incomeBasis]) over a span rolled between the template's
/// `quantityIncomeSecondsMin` and `quantityIncomeSecondsMax` (10 to 30
/// minutes), rounded to two significant figures, at most the storage caps
/// of its bodies summed, the template's `quantityProductionSecondsMax` of
/// that steady gross rate, and the template's `maxQuantity` × (1 + the
/// faction's levels of the megaprojects that
/// [MegaprojectDef.scalesContracts], summed) (each rounded down to two
/// figures), at least `minQuantity`, in whole units
/// ([twoSignificantFigures]). So delivering it gives up a known share of
/// play's sales. Its reward is that sale value × `rewardMultiplier`, at
/// least `rewardIncomeSeconds` and at most `rewardCapIncomeSeconds` of the
/// income basis, both at least `minRewardCredits`, and never below the
/// sale value × `minRewardMultiplier`, in whole credits. The first
/// contract a faction is ever offered ([FactionState.contractsPosted] 0)
/// is exempt from the cap and pays at least `firstContractMinReward`.
///
/// When nothing qualifies, the refill stays due and is used once something
/// does. Whether a resource is made at all, and on the board, is
/// remembered per faction, for as long as the resources it has made
/// (`lifetimeProduced > 0`) and those on its board stay the same, so a
/// refill left waiting through a long catch-up costs one cheap comparison
/// a tick, not an eligibility scan; and the flow report is only built
/// when some building could make a candidate fast enough at full rate.
/// Neither changes what is posted. A refill already due before the step
/// that ends at [now] began is checked again only in a step that reaches a
/// whole game minute ([_dueNowOrOnMinute]), so one waiting on a starved
/// maker builds a report once a game minute, at the same game times for
/// any step size. The RNG is drawn only when a
/// contract is posted, three numbers each time (the template, the
/// resource, then the span), and the flow report built
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
      if (report == null &&
          (!_dueNowOrOnMinute(s, f, now) ||
              !_couldQualify(s, c, f, candidates))) {
        break;
      }
      final made = report ??= buildFlowReport(s, c, f.id);
      final steady = [
        for (final (t, ids) in candidates)
          if ([
                for (final id in ids)
                  if (made.steadyProducedPerSec(id) >= _floorRate(t)) id,
              ]
              case final ok when ok.isNotEmpty)
            (t, ok),
      ];
      if (steady.isEmpty) break;
      final income = incomeBasis(s, c, made);
      final choices = _worthChoosing(s, c, f, steady, made, income);
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
      final roll = rng.nextDouble();
      s.rngState = rng.state;
      final quantity = _quantity(
        s,
        c,
        f,
        template,
        resourceId,
        income,
        made.steadyProducedPerSec(resourceId),
        roll,
      );
      f.contractRefillAt.removeAt(0);
      f.contracts.add(
        ContractState(
          id: s.newId('c'),
          templateId: template.id,
          resourceId: resourceId,
          quantity: quantity,
          rewardCredits: _reward(
            s,
            c,
            f,
            template,
            resourceId,
            quantity,
            income,
          ),
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

/// Game seconds between checks of a refill left waiting.
const double _recheckSeconds = 60;

/// Whether [f]'s first refill is worth a flow report at [now]: it came due
/// in the step that ends at [now] (from `s.time`), the call is not a
/// step's (`now <= s.time`), or the step reaches a whole multiple of
/// [_recheckSeconds] of game time. So a refill left waiting on a maker that
/// is staffed but short of inputs is checked once a game minute, at the
/// same game times whatever the step, not every tick.
bool _dueNowOrOnMinute(GameState s, FactionState f, double now) =>
    f.contractRefillAt.first > s.time ||
    now <= s.time ||
    (now / _recheckSeconds).floor() > (s.time / _recheckSeconds).floor();

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

/// What a contract from [t] for [quantity] of [resourceId] pays [f], whose
/// income basis ([incomeBasis]) is [income] a second: its sale value at
/// current prices ([price]) times `rewardMultiplier`, at least the floor
/// and at most the cap, which are `rewardIncomeSeconds` and
/// `rewardCapIncomeSeconds` of the income, neither below
/// `minRewardCredits`; then never below the sale value times
/// `minRewardMultiplier`, cap or not, and in whole credits (rounded down).
/// The first contract [f] is ever offered has no cap and pays at least
/// `firstContractMinReward`.
BigNum _reward(
  GameState s,
  Content c,
  FactionState f,
  ContractTemplateDef t,
  String resourceId,
  BigNum quantity,
  BigNum income,
) {
  final sale = quantity * price(s, c, resourceId);
  final floor = t.minRewardCredits.max(income.mulDouble(t.rewardIncomeSeconds));
  var reward = sale.mulDouble(t.rewardMultiplier).max(floor);
  if (f.contractsPosted == 0) {
    reward = reward.max(t.firstContractMinReward ?? const BigNum.zero());
  } else if (t.rewardCapIncomeSeconds case final cap?) {
    reward = reward.min(floor.max(income.mulDouble(cap)));
  }
  // Whole credits, never less than the goods' sale value times the
  // least multiple.
  return reward.max(sale.mulDouble(t.minRewardMultiplier)).floor();
}

/// Credits a second a contract's reward is measured against, for the
/// faction [report] is about: the larger of its steady auto-sale income
/// ([FlowReport.creditsPerSec]) and the value of what is left over with
/// every flow steady, at [s]'s market prices (each resource's
/// [FlowReport.steadySurplusPerSec] × [price]). So the floor and cap do
/// not depend on which goods auto-sell: a player who sells by hand, or
/// turns auto-sell off before a refill, is measured like one who
/// auto-sells. And as for credits per second, output fed from a stock
/// nothing refills does not count, so a stockpile does not raise it.
BigNum incomeBasis(GameState s, Content c, FlowReport report) {
  var made = const BigNum.zero();
  for (final id in c.resources.keys) {
    final left = report.steadySurplusPerSec(id);
    if (left > const BigNum.zero()) made = made + left * price(s, c, id);
  }
  return report.creditsPerSec.max(made);
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

/// Units of [resourceId] a contract from [t] asks [f] for, whose income
/// basis ([incomeBasis]) is [income] a second, given a [roll] in `[0, 1)`:
/// what sells for the income of a span rolled between
/// [ContractTemplateDef.quantityIncomeSecondsMin] and
/// [ContractTemplateDef.quantityIncomeSecondsMax] at the current price
/// ([price]), rounded to two significant figures; at most the storage caps
/// of the bodies [f] owns, summed (an order can be filled from several),
/// [ContractTemplateDef.quantityProductionSecondsMax] of [rate], what [f]
/// makes of it a second (steady and gross), and
/// [ContractTemplateDef.maxQuantity] × (1 + [f]'s levels of the
/// megaprojects that [MegaprojectDef.scalesContracts], summed) (each
/// rounded down to two figures), and at least
/// [ContractTemplateDef.minQuantity]; then rounded down to whole units, at
/// least 1.
BigNum _quantity(
  GameState s,
  Content c,
  FactionState f,
  ContractTemplateDef t,
  String resourceId,
  BigNum income,
  BigNum rate,
  double roll,
) {
  final ceiling = _ceiling(s, c, f, t, rate);
  final seconds =
      t.quantityIncomeSecondsMin +
      (t.quantityIncomeSecondsMax - t.quantityIncomeSecondsMin) * roll;
  // Every market's price is above zero: its floor is.
  var q = twoSignificantFigures(
    income.mulDouble(seconds) / price(s, c, resourceId),
  );
  if (ceiling != null) q = q.min(ceiling);
  // Deliveries move whole units, so the quantity is whole, at least 1.
  return q.max(t.minQuantity).floor().max(BigNum.from(1));
}

/// The most units of a resource a contract from [t] may ask [f] for,
/// given its steady gross production [rate] of it: the least of the
/// storage caps of [f]'s bodies summed,
/// [ContractTemplateDef.quantityProductionSecondsMax] of [rate], and
/// [ContractTemplateDef.maxQuantity] × (1 + [f]'s levels of the
/// megaprojects that [MegaprojectDef.scalesContracts], summed), rounded
/// down to two significant figures; null when none applies.
BigNum? _ceiling(
  GameState s,
  Content c,
  FactionState f,
  ContractTemplateDef t,
  BigNum rate,
) {
  BigNum? stores;
  for (final b in s.bodies) {
    if (b.ownerId != f.id) continue;
    stores = (stores ?? const BigNum.zero()) + storageCap(s, c, b);
  }
  var levels = 0;
  for (final m in c.megaprojects.values) {
    if (m.scalesContracts) levels += f.megaprojectLevels[m.id] ?? 0;
  }
  BigNum? ceiling;
  for (final v in [
    stores,
    t.maxQuantity?.mulDouble(1.0 + levels),
    if (t.quantityProductionSecondsMax case final most?) rate.mulDouble(most),
  ]) {
    if (v != null) ceiling = ceiling == null ? v : ceiling.min(v);
  }
  return ceiling == null || ceiling.isZero ? ceiling : _twoFiguresDown(ceiling);
}

/// Goods a fallback draws from when no good is worth an order: the most
/// valuable few.
const int _fallbackGoods = 3;

/// Of [steady], each template with the resources [f] makes fast enough
/// for it, those worth an order: whose achievable quantity ([_ceiling] at
/// their steady gross rate in [report]) sells, at the current price, for
/// at least the template's `quantityIncomeSecondsMin` of [income]. So a
/// contract can always ask for goods worth 10 minutes of play; a cheap
/// bulk good late in the game, of which the faction can store only
/// seconds of income, is not asked for.
///
/// When none is, the [_fallbackGoods] template and resource pairs whose
/// achievable quantity sells for most (in template then resource order on
/// a tie), so a board still fills; their orders pay the reward floor.
/// Templates and resources keep their order.
List<(ContractTemplateDef, List<String>)> _worthChoosing(
  GameState s,
  Content c,
  FactionState f,
  List<(ContractTemplateDef, List<String>)> steady,
  FlowReport report,
  BigNum income,
) {
  // Each pair with what its achievable quantity sells for (null: no
  // ceiling, so any quantity can be asked) and whether that is enough.
  final valued =
      <({ContractTemplateDef t, String id, BigNum? worth, bool ok})>[];
  for (final (t, ids) in steady) {
    for (final id in ids) {
      final most = _ceiling(s, c, f, t, report.steadyProducedPerSec(id));
      final worth = most == null ? null : most * price(s, c, id);
      valued.add((
        t: t,
        id: id,
        worth: worth,
        ok:
            worth == null ||
            worth >= income.mulDouble(t.quantityIncomeSecondsMin),
      ));
    }
  }
  var pick = [
    for (final v in valued)
      if (v.ok) v,
  ];
  if (pick.isEmpty) {
    // Every pair has a ceiling here, so a worth.
    final ranked = [...valued.indexed]
      ..sort((x, y) {
        final byWorth = y.$2.worth!.compareTo(x.$2.worth!);
        return byWorth != 0 ? byWorth : x.$1.compareTo(y.$1);
      });
    pick = [for (final (_, v) in ranked.take(_fallbackGoods)) v];
  }
  return [
    for (final (t, ids) in steady)
      if ([
            for (final id in ids)
              if (pick.any((v) => identical(v.t, t) && v.id == id)) id,
          ]
          case final kept when kept.isNotEmpty)
        (t, kept),
  ];
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
