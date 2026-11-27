import 'dart:math' as math;

import '../content/content.dart';
import '../state/game_state.dart';
import 'megaprojects.dart';

/// A faction's crew over the bodies it owns.
final class CrewTotals {
  /// Creates crew totals.
  const CrewTotals({
    required this.base,
    required this.supported,
    required this.assigned,
  });

  /// Restores totals written by [toJson].
  factory CrewTotals.fromJson(Map<String, Object?> j) => CrewTotals(
    base: j['base']! as int,
    supported: j['supported']! as int,
    assigned: j['assigned']! as int,
  );

  /// Crew available without habitats.
  final int base;

  /// Crew the faction can support: [base] plus each habitat's
  /// [habitatHousing] scaled by its last run fraction, the housing total
  /// scaled by the faction's [EmpireBonuses.housingMultiplier] and rounded
  /// down.
  final int supported;

  /// Crew assigned to buildings on its bodies.
  final int assigned;

  /// Crew still free to assign: `supported − assigned`, never below 0.
  int get free => math.max(0, supported - assigned);

  /// Crew assigned beyond what is supported: `assigned − supported`, never
  /// below 0; above 0 when starving habitats house fewer crew than are
  /// assigned, which slows every crewed building ([crewEfficiency]).
  int get overAssigned => math.max(0, assigned - supported);

  /// These totals as JSON.
  Map<String, Object?> toJson() => {
    'base': base,
    'supported': supported,
    'assigned': assigned,
  };
}

/// How much habitat [b]'s capacity levels scale it:
/// `1 + capacityHousingPerLevel × capacity level`.
///
/// Housing and life-support inputs both scale by it ([habitatHousing],
/// `fullRateFlow`), so each crew housed costs the same upkeep at any level.
double habitatCapacityScale(RulesDef r, BuildingState b) =>
    1 + r.capacityHousingPerLevel * b.levels[UpgradeTrack.capacity]!;

/// Crew habitat [b], of type [def], houses at full rate:
/// `housing × habitatCapacityScale`.
double habitatHousing(RulesDef r, BuildingDef def, BuildingState b) =>
    def.housing * habitatCapacityScale(r, b);

/// Base, supported, assigned and free crew of [factionId] over the bodies
/// it owns; see [CrewTotals]. Throws if the faction does not exist.
CrewTotals crewTotals(GameState s, Content c, String factionId) {
  final (:base, :housing, :assigned) = _crew(s, c, factionId);
  // The small epsilon keeps products such as 0.29 × 100 from flooring to 28.
  return CrewTotals(
    base: base,
    supported: base + (housing + 1e-9).floor(),
    assigned: assigned,
  );
}

/// [factionId]'s base crew, the crew its habitats house unrounded
/// (habitat housing at each habitat's last run fraction, times the housing
/// bonus) and its assigned crew.
({int base, double housing, int assigned}) _crew(
  GameState s,
  Content c,
  String factionId,
) {
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
  housing *= bonusesFor(s, c, factionId).housingMultiplier;
  return (base: base, housing: housing, assigned: assigned);
}

/// Crew [factionId] can still assign: base crew plus habitat housing scaled
/// by each habitat's last run fraction and the housing bonus (the total
/// rounded down), minus crew already assigned on its bodies, never below 0
/// ([CrewTotals.free]).
///
/// Throws if the faction does not exist.
int availableCrew(GameState s, Content c, String factionId) =>
    crewTotals(s, c, factionId).free;

/// Share of [factionId]'s assigned crew its housing supports:
/// [crewShare] of the crew its base crew and habitats house, unrounded
/// (habitat housing at each habitat's last run fraction, times the
/// housing bonus), so 9.5 crew housed for 10 assigned is 0.95.
///
/// Every crewed building of the faction works at this fraction of its
/// crew. Production settles each step on the fraction that step's own
/// housing gives (`stepProduction`), so this is also the fraction the
/// last step ran at. Throws if the faction does not exist.
double crewEfficiency(GameState s, Content c, String factionId) {
  final (:base, :housing, :assigned) = _crew(s, c, factionId);
  return crewShare(base + housing, assigned);
}

/// Share of [assigned] crew that [housed] crew of housing supports:
/// `min(1, housed / assigned)`, or 1 when no crew is assigned.
double crewShare(double housed, int assigned) =>
    assigned == 0 ? 1 : math.min(1, housed / assigned);
