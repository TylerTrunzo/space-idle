part of 'bot.dart';

/// The balanced bot's claims and surveys, started as soon as they can be
/// paid for so their timers run while the player is away.
extension _Claims on _View {
  /// Starts surveying the first hidden body not yet surveyed, in body
  /// order, paid from the first owned body that holds the drones; null
  /// while a survey of its own is under way, when it cannot pay, when
  /// nothing is left to survey, or when the drones held are needed for the
  /// megaproject stage being paid for: a survey only takes drones beyond
  /// what that stage still lacks.
  Command? survey() {
    if (s.projects.any(
      (p) => p.factionId == factionId && p.kind == ProjectKind.survey,
    )) {
      return null;
    }
    final target = s.bodies
        .where(
          (b) => !b.surveyed && projectOn(s, ProjectKind.survey, b.id) == null,
        )
        .firstOrNull;
    final cost = surveyCost(c);
    final source = owned.where((b) => canPay(b, cost)).firstOrNull;
    if (target == null || source == null) return null;
    final drones = cost.keys.where((id) => id != 'credits');
    for (final id in drones) {
      final held = owned.fold(const BigNum.zero(), (t, b) => t + stock(b, id));
      if (held - _owedToStages(id) < cost[id]!) return null;
    }
    return SurveyCommand(factionId, target.id, source.id);
  }

  /// Claims the best unowned body when the faction can pay, kits taken from
  /// the first owned body that holds enough.
  ///
  /// Claims take time, so one is started as soon as it can be paid for,
  /// even while another is under way.
  Command? claim() {
    final cost = claimCost(s, c, factionId);
    final source = owned.where((b) => canPay(b, cost)).firstOrNull;
    final target = _claimTarget();
    if (source == null || target == null) return null;
    return ClaimBodyCommand(factionId, target.id, source.id);
  }

  /// The unowned body no one is claiming that adds the most deposit types
  /// the faction lacks, then the most richness in them; body order breaks
  /// a tie.
  BodyState? _claimTarget() {
    final have = {
      for (final b in owned)
        for (final d in b.deposits) d.resourceId,
    };
    BodyState? best;
    var bestCount = -1;
    var bestRichness = 0.0;
    for (final b in s.bodies) {
      if (!isVisible(s, b, factionId) ||
          b.ownerId != null ||
          projectOn(s, ProjectKind.claim, b.id) != null) {
        continue;
      }
      final fresh = b.deposits.where((d) => !have.contains(d.resourceId));
      final richness = fresh.fold(0.0, (sum, d) => sum + d.richness);
      if (fresh.length > bestCount ||
          (fresh.length == bestCount && richness > bestRichness)) {
        best = b;
        bestCount = fresh.length;
        bestRichness = richness;
      }
    }
    return best;
  }
}
