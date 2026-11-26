import 'dart:math' as math;

import '../content/content.dart';
import '../state/game_state.dart';

/// A faction's crew over the bodies it owns.
final class CrewTotals {
  /// Creates crew totals.
  const CrewTotals({
    required this.base,
    required this.supported,
    required this.assigned,
  });

  /// Crew available without habitats.
  final int base;

  /// Crew the faction can support: [base] plus each habitat's
  /// [habitatHousing] scaled by its last run fraction, the housing total
  /// rounded down.
  final int supported;

  /// Crew assigned to buildings on its bodies.
  final int assigned;

  /// Crew still free to assign: `supported − assigned`, never below 0.
  int get free => math.max(0, supported - assigned);

  /// Crew assigned beyond what is supported: `assigned − supported`, never
  /// below 0; above 0 when starving habitats house fewer crew than are
  /// assigned, which slows every crewed building ([crewEfficiency]).
  int get overAssigned => math.max(0, assigned - supported);
}

/// Crew habitat [b], of type [def], houses at full rate:
/// `housing × (1 + capacityHousingPerLevel × capacity level)`.
double habitatHousing(RulesDef r, BuildingDef def, BuildingState b) =>
    def.housing *
    (1 + r.capacityHousingPerLevel * b.levels[UpgradeTrack.capacity]!);

/// Base, supported, assigned and free crew of [factionId] over the bodies
/// it owns; see [CrewTotals]. Throws if the faction does not exist.
CrewTotals crewTotals(GameState s, Content c, String factionId) {
  var housing = 0.0;
  var assigned = 0;
  for (final body in s.bodies) {
    if (body.ownerId != factionId) continue;
    for (final b in body.buildings) {
      assigned += b.crew;
      final def = c.buildings[b.defId]!;
      if (def.kind == BuildingKind.habitat) {
        housing += habitatHousing(c.rules, def, b) * b.lastRunFraction;
      }
    }
  }
  final base = s.faction(factionId).baseCrew;
  // The small epsilon keeps products such as 0.29 × 100 from flooring to 28.
  return CrewTotals(
    base: base,
    supported: base + (housing + 1e-9).floor(),
    assigned: assigned,
  );
}

/// Crew [factionId] can still assign: base crew plus habitat housing scaled
/// by each habitat's last run fraction (the total rounded down), minus crew
/// already assigned on its bodies, never below 0 ([CrewTotals.free]).
///
/// Throws if the faction does not exist.
int availableCrew(GameState s, Content c, String factionId) =>
    crewTotals(s, c, factionId).free;

/// Share of [factionId]'s assigned crew its housing supports:
/// `min(1, supported / assigned)`, or 1 when no crew is assigned.
///
/// Supported crew follows the same rule as [availableCrew]. Every crewed
/// building of the faction works at this fraction of its crew.
/// Throws if the faction does not exist.
double crewEfficiency(GameState s, Content c, String factionId) {
  final t = crewTotals(s, c, factionId);
  if (t.assigned == 0) return 1;
  return math.min(1, t.supported / t.assigned);
}
