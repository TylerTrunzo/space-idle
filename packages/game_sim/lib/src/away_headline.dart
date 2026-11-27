import 'package:game_core/game_core.dart';

/// The away summary [sum] in one line for the player, built from its typed
/// fields with [c]'s names.
///
/// - The time away, and what of it counted when the cap cut it: "Away 4d
///   2h; 12h counted (cap)".
/// - The credits: the change, "+1.2M credits", when nothing was paid in
///   on its own; otherwise what was earned, what went to each megaproject
///   and the change, "earned 2.67B credits, 2.11B to Mass Driver, net
///   +560M", so a fall in credits that went into a megaproject does not
///   read as a loss.
/// - A crew shortage on return: "Crew short: 41 housed for 67 assigned".
/// - The highest level each megaproject reached while away: "Orbital
///   Station reached level 3".
String awayHeadline(OfflineSummary sum, Content c) {
  final parts = ['Away ${formatDuration(sum.secondsAway)}'];
  if (sum.capped) {
    parts.add('${formatDuration(sum.secondsSimulated)} counted (cap)');
  }
  final net = _signed(sum.creditsGained);
  final paid = [
    for (final MapEntry(key: id, value: got) in sum.autoDelivered.entries)
      if (got[creditsKey] case final v? when !v.isZero)
        '${formatNumber(v)} to ${c.megaprojects[id]?.name ?? id}',
  ];
  parts.add(
    paid.isEmpty
        ? '$net credits'
        : 'earned ${formatNumber(sum.creditsEarned)} credits, '
              '${paid.join(' and ')}, net $net',
  );
  if (sum.housingAfter.overAssigned > 0) {
    parts.add(
      'Crew short: ${sum.housingAfter.supported} housed for '
      '${sum.housingAfter.assigned} assigned',
    );
  }
  final levels = <String, (String, int)>{};
  for (final p in sum.projectsCompleted) {
    if (p.level case final level?) levels[p.targetId] = (p.name, level);
  }
  for (final (name, level) in levels.values) {
    parts.add('$name reached level $level');
  }
  return parts.join('; ');
}

/// [v] formatted with its sign: "+1.2M", "-1.5K", "+0".
String _signed(BigNum v) => '${v.isNegative ? '' : '+'}${formatNumber(v)}';
