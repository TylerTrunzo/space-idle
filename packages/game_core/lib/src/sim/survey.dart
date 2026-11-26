import '../content/content.dart';
import '../num/big_num.dart';
import '../state/game_state.dart';

/// Whether [b] is in sight of faction [factionId]: it has been surveyed
/// (every body but a hidden one starts so) or the faction owns it.
///
/// Every lookup a player's command or report makes goes through it, so a
/// hidden body that nothing has surveyed is `unknownBody` to commands and
/// absent from state, costs and flow reports. The one exception is
/// `SurveyCommand`, which names the body it reveals.
bool isVisible(GameState s, BodyState b, String factionId) =>
    b.surveyed || b.ownerId == factionId;

/// The bodies [factionId] can see, in body order.
Iterable<BodyState> visibleBodies(GameState s, String factionId) =>
    s.bodies.where((b) => isVisible(s, b, factionId));

/// What one survey costs: `surveyCredits` credits and `surveyDrones`
/// survey drones from the paying body's stock. The drones are left out when
/// the rules ask for none.
Map<String, BigNum> surveyCost(Content c) => {
  'credits': c.rules.surveyCredits,
  if (c.rules.surveyDrones > 0)
    c.rules.surveyDroneResource: BigNum.from(c.rules.surveyDrones),
};

/// Seconds a survey takes, `surveySeconds` kept within
/// [[RulesDef.minProjectSeconds], [RulesDef.maxProjectSeconds]].
double surveySeconds(Content c) => c.rules.surveySeconds.clamp(
  RulesDef.minProjectSeconds,
  RulesDef.maxProjectSeconds,
);
