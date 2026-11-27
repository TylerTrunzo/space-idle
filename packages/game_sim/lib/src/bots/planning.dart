part of 'bot.dart';

/// The balanced bot's goals: the next milestone, megaproject level or more
/// housing, and the chain of builds, crew and ships toward each.
extension _Goals on _View {
  /// The next step toward the first unreached milestone that has one, else
  /// toward more housing when crew has run out.
  ///
  /// Saving is only worth it once at least [_saveFrom] of the sum is in
  /// hand and today's income would cover the rest within
  /// [_saveWithinSeconds]; a goal further off than that lets the next one
  /// act, so the bot keeps growing in the meantime.
  _Step pursueGoals() {
    final income = this.income;
    _Step? worth(_Step step) => switch (step) {
      _Do() => step,
      _Save(:final credits)
          when faction.credits >= credits.mulDouble(_saveFrom) &&
              faction.credits.toDouble() + income * _saveWithinSeconds >=
                  credits.toDouble() =>
        step,
      _ => null,
    };
    // Nearly out of crew, a step toward housing comes before saving for a
    // goal, while there is still crew to staff the chain it needs: every
    // later goal needs crew too.
    if (freeCrew < _housingAheadCrew) {
      if (_ensureHousing() case final _Do step) return step;
    }
    for (final m in c.milestones) {
      if (faction.reachedMilestones.contains(m.id) || _met(m)) {
        continue;
      }
      final step = switch (m.condition) {
        StockCondition(:final resourceId) ||
        ProducedCondition(:final resourceId) => ensureMade(resourceId),
        BodiesOwnedCondition() => _ensureClaimable(),
        BuildingCountCondition(:final defId) => _ensureBuilt(defId),
        CreditsCondition(:final amount) => _Save(amount),
        // Earned credits come with growth; saving them up does not help.
        CreditsEarnedCondition() => const _Waiting(),
        // Contracts are worked as they are posted ([workContracts]).
        ContractsCompletedCondition() => const _Waiting(),
        MegaprojectLevelCondition(:final megaprojectId) => _ensureStage(
          c.megaprojects[megaprojectId]!,
        ),
        // These follow from play (growth, projects, surveys); nothing to
        // build for them directly.
        ProductionRateCondition() ||
        BuildingTypesBuiltCondition() ||
        CrewTotalCondition() ||
        ZeroWasteForCondition() ||
        BodiesSurveyedCondition() => const _Waiting(),
      };
      if (worth(step) case final step?) return step;
    }
    // Megaproject levels go on past their milestones.
    for (final m in c.megaprojects.values) {
      if (worth(_ensureStage(m)) case final step?) return step;
    }
    if (freeCrew < 1) {
      if (worth(_ensureHousing()) case final step?) return step;
    }
    return const _Waiting();
  }

  /// Whether [m] holds in this (possibly planned-ahead) state, which the
  /// engine has not yet checked for milestones ([milestoneProgress]), or
  /// will once the faction's claims under way complete.
  bool _met(MilestoneDef m) => switch (m.condition) {
    // Unlike the engine, claims under way count: the bot plans as if they
    // had completed, so it does not save for a body it is already claiming.
    BodiesOwnedCondition(:final count) =>
      bodiesOwnedOrClaiming(s, factionId) >= count,
    // A flow report per check is costly, and the bot waits on it anyway.
    ProductionRateCondition() => false,
    _ => milestoneProgress(s, c, factionId, m).met,
  };

  /// Gets the next claim within reach: makes its outpost kits, then saves
  /// its credits.
  _Step _ensureClaimable() {
    if (_claimTarget() == null) return const _Waiting();
    final cost = claimCost(s, c, factionId);
    for (final MapEntry(key: id, value: need) in cost.entries) {
      if (id == 'credits') continue;
      if (owned.any((b) => stock(b, id) >= need)) continue;
      final step = ensureMade(id);
      // Kits are on their way: save for the credits meanwhile.
      if (step is _Waiting && made(id)) return _Save(cost['credits']!);
      return step;
    }
    return _Save(cost['credits']!);
  }

  /// Builds one more [defId] on the first owned body with a free slot,
  /// unless one is already waiting for crew.
  _Step _ensureBuilt(String defId) {
    final d = c.buildings[defId]!;
    if (buildings.any((x) => x.$2.defId == defId && x.$2.crew == 0)) {
      return const _Waiting();
    }
    for (final body in owned) {
      if (!hasFreeSlot(body)) continue;
      if (buildDeposits(d, body) case [final dep, ...]) {
        return _buildAt(d, body, dep);
      }
    }
    return const _Stuck();
  }

  /// The next step toward a staffed building that makes [resourceId]:
  /// staffing an idle one, building an extractor on a deposit, or building
  /// a factory once something makes each of its inputs (those first); a
  /// build slot first when the only bodies that fit are full.
  _Step ensureMade(String resourceId, [Set<String> visiting = const {}]) {
    if (visiting.length > _maxChainDepth || visiting.contains(resourceId)) {
      return const _Stuck();
    }
    if (made(resourceId)) return _feed(resourceId, {...visiting, resourceId});
    for (final (_, b) in buildings) {
      if (b.crew == 0 && makes(b, resourceId)) return _staff(b);
    }
    for (final d in c.buildings.values) {
      if (d.kind != BuildingKind.extractor ||
          !d.extracts.contains(resourceId)) {
        continue;
      }
      for (final body in owned) {
        if (hasFreeSlot(body) &&
            body.deposits.any((x) => x.resourceId == resourceId)) {
          return _buildAt(d, body, resourceId);
        }
      }
      // Every body with the deposit is full: a slot there comes first.
      for (final body in owned) {
        if (body.deposits.any((x) => x.resourceId == resourceId)) {
          return _expand(body);
        }
      }
    }
    final deeper = {...visiting, resourceId};
    for (final d in c.buildings.values) {
      if (d.kind != BuildingKind.factory ||
          !d.outputs.containsKey(resourceId)) {
        continue;
      }
      final step = _ensureInputs(d.inputs.keys, deeper);
      if (_acts(step)) return step;
      if (step is _Stuck) continue;
      final body = _site(d.inputs.keys);
      if (body != null) return _buildAt(d, body, null);
      // A full body could get them all: a slot there comes first.
      final full = _site(d.inputs.keys, needSlot: false);
      if (full != null) return _expand(full);
      // Every input is made, but no body can get them all: ships are short.
      final ships = _shipsFor(d.inputs.keys, deeper);
      if (_acts(ships)) return ships;
    }
    return const _Stuck();
  }

  /// The next step toward an input that every staffed maker of
  /// [resourceId] stands idle for want of: making it, routing it in from a
  /// body that has it (or growing the route that brings it), getting cargo
  /// ships to such a body, or, when the input's own makers starve too,
  /// feeding them in turn. [_Waiting] while some maker runs at
  /// [_fedShare] or more, or nothing can be done.
  _Step _feed(String resourceId, Set<String> visiting) {
    final makers = [
      for (final (body, b) in buildings)
        if (b.crew > 0 && makes(b, resourceId)) (body, b),
    ];
    if (makers.any((x) => x.$2.lastRunFraction >= _fedShare)) {
      return const _Waiting();
    }
    for (final (body, b) in makers) {
      final reason = b.lastLimitReason;
      if (reason == null || !reason.startsWith('input:')) continue;
      final input = reason.substring('input:'.length);
      if (visiting.contains(input)) continue;
      final deeper = {...visiting, input};
      if (!made(input)) {
        final step = ensureMade(input, deeper);
        if (_acts(step)) return step;
        continue;
      }
      if (routeInto(body, input)) {
        if (_fixInput(body, input) case final fix?) return _Do(fix);
      } else if (!madeAt(body, input)) {
        final need = flowOf(body, b).inputs[input]!;
        if (_route(input, body, need) case final cmd?) return _Do(cmd);
        final ships = _shipsFor([input], deeper);
        if (_acts(ships)) return ships;
      }
      final upstream = _feed(input, deeper);
      if (_acts(upstream)) return upstream;
    }
    return const _Waiting();
  }

  /// [_Waiting] once something makes every one of [inputs], else the first
  /// step toward that, or [_Stuck].
  _Step _ensureInputs(Iterable<String> inputs, Set<String> visiting) {
    for (final i in inputs) {
      if (made(i)) continue;
      final step = ensureMade(i, visiting);
      return _acts(step) ? step : const _Stuck();
    }
    return const _Waiting();
  }

  /// The owned body with a free slot (any body, without [needSlot]) that
  /// can get every one of [inputs], made there or shipped in, with the
  /// most made there; body order breaks a tie. Goods ship only from bodies
  /// holding a cargo ship.
  BodyState? _site(Iterable<String> inputs, {bool needSlot = true}) {
    BodyState? best;
    var bestLocal = -1;
    for (final body in owned) {
      if (needSlot && !hasFreeSlot(body)) continue;
      var local = 0;
      var reachable = true;
      for (final i in inputs) {
        if (madeAt(body, i)) {
          local++;
        } else if (!routeInto(body, i) &&
            !owned.any((o) => o != body && hasShip(o) && madeAt(o, i))) {
          reachable = false;
        }
      }
      if (reachable && local > bestLocal) {
        best = body;
        bestLocal = local;
      }
    }
    return best;
  }

  /// The next step toward cargo ships on a body that makes one of
  /// [inputs] and has none: making ships, then sending [_shipsSent] there
  /// from a body holding more ([moveShipsTo]).
  _Step _shipsFor(Iterable<String> inputs, Set<String> visiting) {
    final making = ensureMade(r.cargoShipResource, visiting);
    if (_acts(making) || making is _Stuck) return making;
    for (final to in owned) {
      if (shipsAt(to) >= 1) continue;
      if (!inputs.any((i) => madeAt(to, i))) continue;
      final move = moveShipsTo(to);
      return move == null ? const _Waiting() : _Do(move);
    }
    return const _Waiting();
  }

  /// One more build slot on full [body]: bought now, saved for, waited for
  /// while one is under way, or [_Stuck] at the most a save holds.
  _Step _expand(BodyState body) {
    if (expanding(body)) return const _Waiting();
    if (body.extraSlots >= SaveCodec.maxExtraSlots) return const _Stuck();
    final cost = slotCost(c, body);
    return canPay(body, cost)
        ? _Do(ExpandSlotsCommand(factionId, body.id))
        : _Save(cost['credits']!);
  }

  /// Builds [d] on [body], or saves for it; staffing follows on a later
  /// step so that crew moved to it is not handed straight back.
  _Step _buildAt(BuildingDef d, BodyState body, String? deposit) {
    // Buildings without crew slots (crewless habitats, warehouses) need no
    // crew to run.
    if (d.crewSlots > 0 && freeCrew < 1 && _crewDonor(null) == null) {
      return const _Stuck();
    }
    if (!canPay(body, d.buildCost)) {
      final credits = d.buildCost['credits'] ?? const BigNum.zero();
      final short = d.buildCost.entries.any(
        (x) => x.key != 'credits' && stock(body, x.key) < x.value,
      );
      return short ? const _Stuck() : _Save(credits);
    }
    return _Do(
      BuildCommand(factionId, body.id, d.id, depositResourceId: deposit),
    );
  }

  /// Staffs idle building [b]: free crew is assigned by [assignFreeCrew],
  /// so this takes one crew from the most-crewed other building with more
  /// than one, the lowest-value first on a tie.
  _Step _staff(BuildingState b) {
    if (freeCrew >= 1) return const _Waiting();
    final donor = _crewDonor(b);
    if (donor == null) return const _Stuck();
    return _Do(AssignCrewCommand(factionId, donor.id, donor.crew - 1));
  }

  /// The building other than [except] that can best spare one crew: the
  /// most crewed with at least [minCrew], the lowest value per crew on a
  /// tie; never one that [keepsCrewAlive].
  BuildingState? _crewDonor(BuildingState? except, {int minCrew = 2}) {
    (BuildingState, double)? best;
    for (final (body, x) in buildings) {
      if (x == except || x.crew < minCrew || keepsCrewAlive(x)) continue;
      final v = value(flowOf(body, x)) / x.crew;
      if (best == null ||
          x.crew > best.$1.crew ||
          (x.crew == best.$1.crew && v < best.$2)) {
        best = (x, v);
      }
    }
    return best?.$1;
  }

  /// The next step toward a running habitat that has its life support:
  /// staffing an idle one that needs crew, making its build resources and inputs, shipping
  /// its build resources to the chosen body, then building it.
  _Step _ensureHousing() {
    final hab = c.buildings.values
        .where((d) => d.kind == BuildingKind.habitat)
        .firstOrNull;
    if (hab == null) return const _Stuck();
    for (final (_, b) in buildings) {
      if (b.crew == 0 &&
          def(b).kind == BuildingKind.habitat &&
          !runsWithoutCrew(def(b))) {
        return _staff(b);
      }
    }
    // Feed the habitats there are before adding more.
    if (crewEff < 1 ||
        buildings.any(
          (x) =>
              def(x.$2).kind == BuildingKind.habitat &&
              x.$2.lastRunFraction < 1,
        )) {
      return const _Waiting();
    }
    // A capacity level on a fed habitat adds housing more cheaply than a
    // new habitat, until its price passes a new one's credits.
    final more = _habitatCapacity();
    final newCredits = hab.buildCost['credits'] ?? const BigNum.zero();
    if (more != null && more.$2 <= newCredits) {
      return canPay(more.$3, {'credits': more.$2})
          ? _Do(more.$1)
          : _Save(more.$2);
    }
    final parts = {
      for (final MapEntry(key: id, value: n) in hab.buildCost.entries)
        if (id != 'credits') id: n,
    };
    for (final id in parts.keys) {
      final step = ensureMade(id);
      if (_acts(step)) return step;
      if (step is _Stuck) return step;
    }
    final inputs = _ensureInputs(hab.inputs.keys, const {});
    if (inputs is! _Waiting) return inputs;
    // Only where life support is made on the spot: a habitat fed by routes
    // starves whenever its source's own buildings use the supply first,
    // and every crewed building slows with it.
    final body = owned
        .where(
          (b) => hasFreeSlot(b) && hab.inputs.keys.every((i) => madeAt(b, i)),
        )
        .firstOrNull;
    if (body == null) {
      // Complete life support on a body that makes some of it.
      final local = _completeLifeSupport(hab);
      if (local != null) return local;
      // No room for a new one: grow the ones there are.
      if (more == null) return const _Stuck();
      return canPay(more.$3, {'credits': more.$2})
          ? _Do(more.$1)
          : _Save(more.$2);
    }
    for (final MapEntry(key: id, value: n) in parts.entries) {
      if (stock(body, id) >= n) continue;
      if (routeInto(body, id)) return const _Waiting();
      final from = owned
          .where((o) => o != body && hasShip(o) && stock(o, id) >= n)
          .firstOrNull;
      if (from == null) {
        // The parts are made elsewhere but nothing can carry them: ships
        // first.
        if (owned.any(hasShip)) return const _Waiting();
        final ships = ensureMade(r.cargoShipResource);
        return _acts(ships) ? ships : const _Waiting();
      }
      return _Do(
        CreateRouteCommand(
          factionId,
          from.id,
          body.id,
          id,
          BigNum.from(_trickleRate),
          1,
          stopAtDestination: n,
        ),
      );
    }
    return _buildAt(hab, body, null);
  }

  /// A step toward one body making all of [hab]'s inputs itself: on the
  /// body with a free slot that makes the most of them already (body order
  /// on a tie), a factory for a missing one whose own inputs are all made
  /// there. Null if no body can get closer that way.
  _Step? _completeLifeSupport(BuildingDef hab) {
    BodyState? best;
    var bestMade = 0;
    for (final b in owned) {
      if (!hasFreeSlot(b)) continue;
      final made = hab.inputs.keys.where((i) => madeAt(b, i)).length;
      if (made > bestMade) {
        best = b;
        bestMade = made;
      }
    }
    if (best == null) return null;
    for (final i in hab.inputs.keys) {
      if (madeAt(best, i)) continue;
      for (final d in c.buildings.values) {
        if (d.kind != BuildingKind.factory ||
            !d.outputs.containsKey(i) ||
            !d.inputs.keys.every((x) => madeAt(best!, x))) {
          continue;
        }
        return _buildAt(d, best, null);
      }
    }
    return null;
  }

  /// The cheapest capacity level on a habitat that runs at full rate, its
  /// credit cost and its body; null if there is none.
  (Command, BigNum, BodyState)? _habitatCapacity() {
    (Command, BigNum, BodyState)? best;
    for (final (body, b) in buildings) {
      final d = def(b);
      if (d.kind != BuildingKind.habitat ||
          b.lastRunFraction < 1 ||
          !canUpgrade(b, UpgradeTrack.capacity)) {
        continue;
      }
      final credits = upgradeCost(c, b, UpgradeTrack.capacity)['credits']!;
      if (best == null || credits < best.$2) {
        best = (
          UpgradeCommand(factionId, b.id, UpgradeTrack.capacity),
          credits,
          body,
        );
      }
    }
    return best;
  }
}
