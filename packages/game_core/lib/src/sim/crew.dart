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
  return CrewTotals(
    base: base,
    supported: base + _settled(housing).floor(),
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
/// `housed / assigned`, or 1 when [housed] covers [assigned] within
/// [housingTolerance] or no crew is assigned. So crew efficiency is below
/// 1 exactly when [CrewTotals.overAssigned] is above 0.
double crewShare(double housed, int assigned) =>
    _settled(housed) >= assigned ? 1 : housed / assigned;

/// Crew a housing total may fall short of a whole number by and still
/// count as housing it: float products such as 0.29 × 100 or 5 × 20 × 2 ×
/// 1.15 land a hair below the integer they mean. [crewTotals] and
/// [crewShare] both allow for it, so supported crew and crew efficiency
/// agree on whether housing falls short.
const double housingTolerance = 1e-9;

/// [housed] crew with [housingTolerance] added.
double _settled(double housed) => housed + housingTolerance;

/// Sets [b]'s crew to [crew], [def] being its type: the one way commands
/// and ticks change a building's crew. Once its base slots are full it no
/// longer waits for crew ([BuildingState.awaitingCrew] cleared), so no
/// sequence of crew changes leaves a flag a save would refuse.
void setBuildingCrew(BuildingState b, BuildingDef def, int crew) {
  b.crew = crew;
  if (crew >= def.crewSlots) b.awaitingCrew = false;
}

/// Fills every building [BuildingState.awaitingCrew] from its faction's
/// free crew, up to its base slots, factions in list order and their
/// buildings in body and list order, and clears the flag on each, filled
/// or not.
///
/// The engine runs it right after production, whose habitats have then
/// run and house their crew: so a building put up alongside new habitats,
/// which house no one until they first run, takes its crew as the batch
/// of commands it came in ends. Crew that frees up later is the player's
/// to assign.
void fillAwaitingCrew(GameState s, Content c) {
  for (final f in s.factions) {
    int? free;
    for (final body in s.bodies) {
      if (body.ownerId != f.id) continue;
      for (final b in body.buildings) {
        if (!b.awaitingCrew) continue;
        b.awaitingCrew = false;
        free ??= availableCrew(s, c, f.id);
        final def = c.buildings[b.defId]!;
        final take = math.min(free, def.crewSlots - b.crew);
        if (take <= 0) continue;
        setBuildingCrew(b, def, b.crew + take);
        free -= take;
      }
    }
  }
}
