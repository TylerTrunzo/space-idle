import 'dart:math' as math;

import '../content/content.dart';
import '../state/game_state.dart';

/// Crew [factionId] can support and has assigned, over the bodies it owns.
///
/// Supported crew is base crew plus habitat housing scaled by each habitat's
/// last run fraction, the housing total rounded down. Throws if the faction
/// does not exist.
({int supported, int assigned}) _crewTotals(
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
        housing += def.housing * b.lastRunFraction;
      }
    }
  }
  // The small epsilon keeps products such as 0.29 × 100 from flooring to 28.
  final supported = s.faction(factionId).baseCrew + (housing + 1e-9).floor();
  return (supported: supported, assigned: assigned);
}

/// Crew [factionId] can still assign: base crew plus habitat housing scaled
/// by each habitat's last run fraction (the total rounded down), minus crew
/// already assigned on its bodies.
///
/// Negative when starving habitats house fewer crew than are assigned.
/// Throws if the faction does not exist.
int availableCrew(GameState s, Content c, String factionId) {
  final t = _crewTotals(s, c, factionId);
  return t.supported - t.assigned;
}

/// Share of [factionId]'s assigned crew its housing supports:
/// `min(1, supported / assigned)`, or 1 when no crew is assigned.
///
/// Supported crew follows the same rule as [availableCrew]. Every crewed
/// building of the faction works at this fraction of its crew.
/// Throws if the faction does not exist.
double crewEfficiency(GameState s, Content c, String factionId) {
  final t = _crewTotals(s, c, factionId);
  if (t.assigned == 0) return 1;
  return math.min(1, t.supported / t.assigned);
}
