import '../content/content.dart';
import '../num/big_num.dart';
import '../report/flow_report.dart';
import '../rng.dart';
import '../state/game_state.dart';

/// Posts contracts on every faction's board whose slots are due to refill
/// by [now]: while it holds fewer than [RulesDef.contractSlots] contracts
/// and `now >= contractRefillAt[0]`, a contract is posted from the state's
/// [Rng] and that refill is used up.
///
/// A contract asks for a resource of a template's tiers that the faction
/// has made (`lifetimeProduced > 0`), or that a recipe makes from inputs it
/// has all made, and that has a base price and is not already on its board.
/// The template is drawn first among those with such a resource, then the
/// resource. Its quantity is `max(minQuantity, net production rate ×
/// quantitySeconds)`, rounded to two significant figures
/// ([twoSignificantFigures]), with the rate from the flow report's steady
/// rates ([FlowReport.netProducedPerSec]); its reward is `quantity ×
/// basePrice × rewardMultiplier` credits.
///
/// When nothing qualifies, the refill stays due and is used once something
/// does. The RNG is drawn only when a contract is posted, two numbers each
/// time, and the flow report built at most once per faction per call, so
/// a tick without a due refill costs next to nothing. A faction with no
/// refills banked (every faction but the player in stage 1.5) has no board.
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
      final choices = _choices(c, f);
      if (choices.isEmpty) break;
      final rng = Rng.fromState(s.rngState);
      final (template, resources) = choices[rng.nextInt(choices.length)];
      final resourceId = resources[rng.nextInt(resources.length)];
      s.rngState = rng.state;
      report ??= buildFlowReport(s, c, f.id);
      final rate = report.netProducedPerSec(resourceId);
      final quantity = twoSignificantFigures(
        rate.mulDouble(template.quantitySeconds).max(template.minQuantity),
      );
      f.contractRefillAt.removeAt(0);
      f.contracts.add(
        ContractState(
          id: s.newId('c'),
          templateId: template.id,
          resourceId: resourceId,
          quantity: quantity,
          rewardCredits:
              quantity *
              c.resources[resourceId]!.basePrice.mulDouble(
                template.rewardMultiplier,
              ),
          postedAt: now,
        ),
      );
    }
  }
}

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

/// [v] rounded to two significant figures, halves away from zero; zero
/// stays zero.
BigNum twoSignificantFigures(BigNum v) {
  if (v.isZero) return v;
  // The mantissa is in [1, 10), so tenths of it are the second figure.
  final figures = (v.mantissa * 10).round();
  return BigNum.parse('${figures}e${v.exponent - 1}');
}

/// Each template, in content order, with the resources a contract from it
/// may ask [f] for, in content order; templates with none left out.
List<(ContractTemplateDef, List<String>)> _choices(Content c, FactionState f) {
  bool made(String id) =>
      (f.lifetimeProduced[id] ?? const BigNum.zero()) > const BigNum.zero();
  final onBoard = {for (final k in f.contracts) k.resourceId};
  final eligible = <ResourceDef>[];
  for (final r in c.resources.values) {
    if (r.basePrice.isZero || onBoard.contains(r.id)) continue;
    if (made(r.id) ||
        c.buildings.values.any(
          (b) =>
              b.kind != BuildingKind.extractor &&
              b.outputs.containsKey(r.id) &&
              b.inputs.isNotEmpty &&
              b.inputs.keys.every(made),
        )) {
      eligible.add(r);
    }
  }
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
