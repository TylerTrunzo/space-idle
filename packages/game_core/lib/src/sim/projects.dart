import 'dart:math' as math;

import '../content/content.dart';
import '../state/game_state.dart';

/// Seconds a claim [factionId] starts now takes.
///
/// With `n` bodies owned or being claimed by it:
/// `claimSecondsBase + claimSecondsPerOwned × (n − 1)`, clamped to
/// [[RulesDef.minProjectSeconds], [RulesDef.maxProjectSeconds]]. Claims under
/// way count, so claims started side by side take as long as one after
/// another.
double claimSeconds(GameState s, Content c, String factionId) {
  final r = c.rules;
  final n = bodiesOwnedOrClaiming(s, factionId);
  return (r.claimSecondsBase + r.claimSecondsPerOwned * math.max(0, n - 1))
      .clamp(RulesDef.minProjectSeconds, RulesDef.maxProjectSeconds);
}

/// Bodies [factionId] owns plus the claims it has under way.
int bodiesOwnedOrClaiming(GameState s, String factionId) =>
    s.bodies.where((b) => b.ownerId == factionId).length +
    s.projects
        .where((p) => p.factionId == factionId && p.kind == ProjectKind.claim)
        .length;

/// The project of [kind] under way on [targetId], any faction's, or null.
ProjectState? projectOn(GameState s, ProjectKind kind, String targetId) {
  for (final p in s.projects) {
    if (p.kind == kind && p.targetId == targetId) return p;
  }
  return null;
}

/// Starts a [kind] project for [factionId] on [targetId] that takes
/// [seconds] from now, and returns it. The caller has already paid for it.
ProjectState startProject(
  GameState s,
  String factionId,
  ProjectKind kind,
  String targetId,
  double seconds,
) {
  final p = ProjectState(
    id: s.newId('p'),
    factionId: factionId,
    kind: kind,
    targetId: targetId,
    startedAt: s.time,
    finishAt: s.time + seconds,
  );
  s.projects.add(p);
  return p;
}

/// [factionId]'s projects under way, soonest to finish first, then in the
/// order they were started.
List<ProjectState> runningProjects(GameState s, String factionId) => [
  for (final p in s.projects)
    if (p.factionId == factionId) p,
]..sort(_byFinish);

/// Display name of what [p] acts on: its body's or its megaproject's.
String projectTargetName(GameState s, Content c, ProjectState p) =>
    switch (p.kind) {
      ProjectKind.claim ||
      ProjectKind.expandSlots ||
      ProjectKind.survey => s.body(p.targetId).name,
      ProjectKind.megaprojectStage => c.megaprojects[p.targetId]!.name,
    };

/// Completes every project with `finishAt <= s.time`, in `finishAt` order,
/// ties in the order they were started, and applies its effect once: it
/// leaves [GameState.projects] before the effect.
///
/// The engine runs it in every tick, before time moves on, so a project
/// due at exactly the end of a tick completes at the start of the next,
/// as a shipment lands.
void stepProjects(GameState s, Content c) {
  final due = [
    for (final p in s.projects)
      if (p.finishAt <= s.time) p,
  ];
  if (due.isEmpty) return;
  due.sort(_byFinish);
  s.projects.removeWhere((p) => p.finishAt <= s.time);
  for (final p in due) {
    switch (p.kind) {
      case ProjectKind.claim:
        _completeClaim(s, p);
      case ProjectKind.expandSlots:
        _completeExpandSlots(s, p);
      case ProjectKind.megaprojectStage:
        _completeMegaprojectStage(s, p);
      case ProjectKind.survey:
        // No command starts these yet; they complete with no effect.
        break;
    }
  }
}

/// Orders by `finishAt`, then by creation: the number an id such as `p9`
/// ends in ([GameState.newId] counts up), so `p9` comes before `p10`.
/// Ids with the same number, or none, fall back to comparing the ids.
int _byFinish(ProjectState a, ProjectState b) {
  final byTime = a.finishAt.compareTo(b.finishAt);
  if (byTime != 0) return byTime;
  final (x, y) = (_idNumber(a.id), _idNumber(b.id));
  if (x != null && y != null && x != y) return x.compareTo(y);
  return a.id.compareTo(b.id);
}

final _trailingDigits = RegExp(r'(\d+)$');

/// The number [id] ends in, or null if it ends in none.
int? _idNumber(String id) {
  final m = _trailingDigits.firstMatch(id);
  return m == null ? null : int.tryParse(m.group(1)!);
}

/// Makes the claimed body [p]'s faction's, unless someone owns it by now.
void _completeClaim(GameState s, ProjectState p) {
  final body = s.body(p.targetId);
  body.ownerId ??= p.factionId;
}

/// Adds the extra build slot [p] paid for to its body.
void _completeExpandSlots(GameState s, ProjectState p) {
  s.body(p.targetId).extraSlots++;
}

/// Raises [p]'s faction's level of its megaproject by one.
void _completeMegaprojectStage(GameState s, ProjectState p) {
  final levels = s.faction(p.factionId).megaprojectLevels;
  levels[p.targetId] = (levels[p.targetId] ?? 0) + 1;
}
