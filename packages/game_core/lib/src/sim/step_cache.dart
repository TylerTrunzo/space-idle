import '../content/content.dart';
import '../num/big_num.dart';
import '../state/game_state.dart';
import 'crew.dart';
import 'megaprojects.dart';
import 'production.dart';

/// What one engine step reads over and over once production has run, and
/// that holds for the rest of the step: each faction's crew efficiency,
/// each body's storage cap, and what each body's buildings use at full
/// supply over a length of time.
///
/// Stock plays no part in any of them, so they hold while cargo,
/// auto-delivery and the market move goods; the steps after production
/// share one, so each is worked out once a tick instead of once a step.
/// A faction's megaproject levels can still change within the step
/// (auto-delivery completes the stages due by the minute), so every entry
/// is kept with the faction's bonuses it was worked out at and worked out
/// again once they change ([bonusesFor] gives the same object while the
/// levels stay the same).
///
/// Build one after production and drop it when the step ends: crew,
/// buildings and habitat run fractions must not change while it is used.
final class StepCache {
  /// Creates an empty cache over [s].
  StepCache(this.s, this.c);

  /// The state the step runs on.
  final GameState s;

  /// The content the step runs with.
  final Content c;

  final _crewEff = <String, (EmpireBonuses, double)>{};
  final _caps = <String, (EmpireBonuses, BigNum)>{};
  final _use = <(String, double), (EmpireBonuses, Map<String, BigNum>)>{};

  /// [crewEfficiency] of [factionId].
  double crewEff(String factionId) {
    final bonuses = bonusesFor(s, c, factionId);
    if (_crewEff[factionId] case (
      final at,
      final v,
    ) when identical(at, bonuses)) {
      return v;
    }
    final v = crewEfficiency(s, c, factionId);
    _crewEff[factionId] = (bonuses, v);
    return v;
  }

  /// [storageCap] of [body].
  BigNum cap(BodyState body) {
    final bonuses = bonusesFor(s, c, body.ownerId);
    if (_caps[body.id] case (final at, final v) when identical(at, bonuses)) {
      return v;
    }
    final v = storageCap(s, c, body);
    _caps[body.id] = (bonuses, v);
    return v;
  }

  /// Resource id to what [body]'s buildings use in [seconds] at full
  /// supply ([fullRateFlow]), its owner's crew working at [crewEff] with
  /// its bonuses; empty for a body nobody owns. Worked out once a second
  /// and scaled: use at full supply is in proportion to the time.
  Map<String, BigNum> use(BodyState body, double seconds) {
    final owner = body.ownerId;
    if (owner == null) return const {};
    final bonuses = bonusesFor(s, c, owner);
    final key = (body.id, seconds);
    if (_use[key] case (final at, final v) when identical(at, bonuses)) {
      return v;
    }
    final Map<String, BigNum> total;
    if (seconds == 1) {
      total = _perSecond(body, owner, bonuses);
    } else {
      total = {
        for (final MapEntry(key: id, value: v) in use(body, 1).entries)
          id: v.mulDouble(seconds),
      };
    }
    _use[key] = (bonuses, total);
    return total;
  }

  /// What [body]'s buildings use a second at full supply, at [owner]'s
  /// crew efficiency and [bonuses]: kept with the body from tick to tick
  /// while none of what it depends on changes (its buildings, their crew
  /// and levels, the crew efficiency and the bonuses), since that is most
  /// ticks of a catch-up.
  Map<String, BigNum> _perSecond(
    BodyState body,
    String owner,
    EmpireBonuses bonuses,
  ) {
    final eff = crewEff(owner);
    final known = _bodyUse[body];
    if (known != null &&
        identical(known.bonuses, bonuses) &&
        known.crewEff == eff &&
        known.matches(body)) {
      return known.perSecond;
    }
    final total = <String, BigNum>{};
    for (final b in body.buildings) {
      final inputs = fullRateFlow(c, body, b, 1, eff, bonuses: bonuses).inputs;
      for (final MapEntry(key: id, value: v) in inputs.entries) {
        total[id] = (total[id] ?? const BigNum.zero()) + v;
      }
    }
    _bodyUse[body] = _BodyUse(bonuses, eff, _BodyUse.signature(body), total);
    return total;
  }
}

/// A body's buildings' use a second at full supply ([StepCache.use]), and
/// what it was worked out from.
final class _BodyUse {
  _BodyUse(this.bonuses, this.crewEff, this._signature, this.perSecond);

  final EmpireBonuses bonuses;
  final double crewEff;
  final List<Object?> _signature;
  final Map<String, BigNum> perSecond;

  /// Everything of [body] that [fullRateFlow] reads: its deposits and,
  /// for each building in order, the building, its type, deposit, crew
  /// and levels.
  static List<Object?> signature(BodyState body) => [
    body.deposits,
    for (final b in body.buildings) ...[
      b,
      b.defId,
      b.depositResourceId,
      b.crew,
      for (final t in UpgradeTrack.values) b.levels[t],
    ],
  ];

  /// Whether [body] is as it was when this was worked out.
  bool matches(BodyState body) {
    final now = signature(body);
    if (now.length != _signature.length) return false;
    for (var i = 0; i < now.length; i++) {
      final (a, b) = (now[i], _signature[i]);
      if (a is BodyState || a is BuildingState || a is List) {
        if (!identical(a, b)) return false;
      } else if (a != b) {
        return false;
      }
    }
    return true;
  }
}

/// Each body's last [_BodyUse].
final _bodyUse = Expando<_BodyUse>('bodyUse');
