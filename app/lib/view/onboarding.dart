import 'package:game_core/game_core.dart';
import 'package:meta/meta.dart';

// The first-hour guide (findings §5(b)): an ordered list of steps, each
// done when the game state shows it, never by what was tapped. Pure: the
// guide's place is kept outside the game save, by the app.

/// One step of the first-hour guide.
@immutable
final class OnboardingStep {
  const OnboardingStep._(this.id, this.title, this.done);

  /// A stable name for the step.
  final String id;

  /// What the step asks, such as "Build a second Smelter".
  final String title;

  /// Whether the player has done it, from the state alone.
  final bool Function(GameState s, Content c, String factionId) done;
}

/// Free crew at or below which the Habitat step comes forward, before free
/// crew runs out.
const int habitatStepFreeCrew = 2;

/// The guide's steps, in order.
final List<OnboardingStep> onboardingSteps = [
  OnboardingStep._(
    'sell-steel',
    'Sell some Steel, or turn on auto-sell for it',
    (s, c, f) =>
        (s.faction(f).salesRevenue['steel'] ?? const BigNum.zero()) >
            const BigNum.zero() ||
        s.faction(f).autoSell.any((r) => r.resourceId == 'steel'),
  ),
  OnboardingStep._(
    'second-smelter',
    'Build a second Smelter',
    (s, c, f) => _count(s, f, 'smelter') >= 2,
  ),
  OnboardingStep._(
    'add-crew',
    'Add crew to a building',
    (s, c, f) => crewTotals(s, c, f).assigned > _startingCrew(c),
  ),
  OnboardingStep._(
    'upgrade',
    'Buy an upgrade',
    (s, c, f) => _owned(s, f).any(
      (body) => body.buildings.any((b) => b.levels.values.any((l) => l > 0)),
    ),
  ),
  OnboardingStep._(
    'claim',
    'Claim a body',
    (s, c, f) => bodiesOwnedOrClaiming(s, f) >= 2,
  ),
  OnboardingStep._(
    'build-away',
    'Build on your new body',
    (s, c, f) =>
        _owned(s, f).any((b) => b.id != _home(c) && b.buildings.isNotEmpty),
  ),
  OnboardingStep._(
    'circuits',
    'Make Circuits',
    (s, c, f) => _made(s, f, 'circuit'),
  ),
  OnboardingStep._(
    'habitat',
    'Build a Habitat',
    (s, c, f) => _count(s, f, 'habitat') >= 1,
  ),
  OnboardingStep._(
    'outpost-kit',
    'Make an Outpost Kit',
    (s, c, f) => _made(s, f, 'outpost_kit'),
  ),
];

/// The step to show from [reached] on (the first not yet passed), or null
/// when the guide is done: the first step from [reached] the state has not
/// done, steps already done skipped. While free crew is at or below
/// [habitatStepFreeCrew] and no Habitat stands, the Habitat step comes
/// forward, so it shows before free crew runs out.
int? onboardingStepAt(GameState s, Content c, String factionId, int reached) {
  int? first;
  for (var i = reached; i < onboardingSteps.length; i++) {
    if (!onboardingSteps[i].done(s, c, factionId)) {
      first = i;
      break;
    }
  }
  if (first == null) return null;
  final habitat = onboardingSteps.indexWhere((x) => x.id == 'habitat');
  if (first < habitat &&
      !onboardingSteps[habitat].done(s, c, factionId) &&
      crewTotals(s, c, factionId).free <= habitatStepFreeCrew) {
    return habitat;
  }
  return first;
}

/// Where the guide stands now: the first step from [reached] not done, the
/// Habitat step aside, which only comes forward and never moves [reached].
/// So a passed step is not asked again if the state undoes it.
int onboardingReached(GameState s, Content c, String factionId, int reached) {
  var i = reached;
  while (i < onboardingSteps.length &&
      onboardingSteps[i].done(s, c, factionId)) {
    i++;
  }
  return i;
}

/// The step's detail line, from the state: what each body mines and the
/// claim's cost for the claim step; the Buy max tip on the upgrade step,
/// once the player has credits to spare; else null.
String? onboardingDetail(
  OnboardingStep step,
  GameState s,
  Content c,
  String f,
) {
  switch (step.id) {
    case 'claim':
      final cost = claimCost(s, c, f)[creditsKey] ?? const BigNum.zero();
      final bodies = [
        for (final b in s.bodies)
          if (b.ownerId == null && isVisible(s, b, f))
            '${b.name}: ${b.deposits.map((d) => c.resources[d.resourceId]!.name).join(', ')}',
      ];
      return 'A claim costs ${formatNumber(cost)} credits. '
          '${bodies.join('; ')}';
    case 'upgrade':
      // The tip waits for spare credits: twice the cheapest level.
      BigNum? cheapest;
      for (final body in _owned(s, f)) {
        for (final b in body.buildings) {
          for (final t in c.buildings[b.defId]!.upgrades.keys) {
            if (upgradeMaxedReason(c, b, t) != null) continue;
            final cost =
                upgradeCost(c, b, t)[creditsKey] ?? const BigNum.zero();
            if (cheapest == null || cost < cheapest) cheapest = cost;
          }
        }
      }
      final spare =
          cheapest != null && s.faction(f).credits >= cheapest * BigNum.from(2);
      return spare
          ? 'Tip: tap Buy max in the top bar to spend on the best-value '
                'upgrades'
          : null;
    case _:
      return null;
  }
}

int _count(GameState s, String f, String defId) => _owned(
  s,
  f,
).fold(0, (n, b) => n + b.buildings.where((x) => x.defId == defId).length);

bool _made(GameState s, String f, String id) =>
    (s.faction(f).lifetimeProduced[id] ?? const BigNum.zero()) >
    const BigNum.zero();

Iterable<BodyState> _owned(GameState s, String f) =>
    s.bodies.where((b) => b.ownerId == f);

/// The new game's player state, worked out once per content.
final _start = Expando<GameState>('new game');

GameState _newGame(Content c) => _start[c] ??= newGameState(c, 0);

String _player(GameState s) => s.factions.firstWhere((f) => f.isPlayer).id;

/// Crew a new game's buildings start with.
int _startingCrew(Content c) {
  final s = _newGame(c);
  return crewTotals(s, c, _player(s)).assigned;
}

/// The body a new game starts on.
String _home(Content c) {
  final s = _newGame(c);
  final p = _player(s);
  return s.bodies.firstWhere((b) => b.ownerId == p).id;
}
