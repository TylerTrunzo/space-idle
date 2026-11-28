part of 'bot.dart';

/// The balanced bot's bottleneck fixes: upgrades and new suppliers where a
/// building starves, storage where a store fills, and routes and cargo
/// ships between bodies.
extension _Bottlenecks on _View {
  /// Units per second of [resourceId] made on [body] beyond what its
  /// buildings use; zero or less when there is none.
  double surplus(BodyState body, String resourceId) {
    final flow = report!.bodies.where((f) => f.bodyId == body.id).firstOrNull;
    if (flow == null) return 0;
    final madeHere = flow.producedPerSec[resourceId] ?? const BigNum.zero();
    final used = flow.consumedPerSec[resourceId] ?? const BigNum.zero();
    return (madeHere - used).toDouble();
  }

  /// The first fix for one of the worst bottlenecks not yet in [tried],
  /// adding it to [tried] when fixed.
  ///
  /// Understaffed buildings are left out: assigning free crew sees to them
  /// first, and they would crowd out the bottlenecks worth fixing. So are
  /// buildings short of an input that still run at [below] or more
  /// ([BalancedBot.inputWorthFixingBelow]). A shortage the report puts down
  /// to a route ([BottleneckKind.routeLimited]) is fixed as any input
  /// shortage is.
  Command? fixBottleneck(Set<String> tried, {required double below}) {
    for (final neck
        in report!.bottlenecks
            .where(
              (n) =>
                  n.kind != BottleneckKind.understaffed &&
                  (!_isInput(n) || n.runFraction < below),
            )
            .take(BalancedBot.bottlenecksConsidered)) {
      if (neck.kind == BottleneckKind.storageFull) {
        final key = '${neck.bodyId}:store';
        if (tried.contains(key)) continue;
        final fix = _addStorage(s.body(neck.bodyId!));
        if (fix != null) {
          tried.add(key);
          return fix;
        }
        continue;
      }
      if (!_isInput(neck)) {
        // Free crew is assigned first and a crew shortage is shed
        // ([shedCrew]); an idle building waits for crew to free up.
        continue;
      }
      final key = '${neck.bodyId}:${neck.resourceId}';
      if (tried.contains(key)) continue;
      final fix = _fixInput(s.body(neck.bodyId!), neck.resourceId!);
      if (fix != null) {
        tried.add(key);
        return fix;
      }
    }
    return null;
  }

  /// More storage on [body], whose store of something is full and wasting
  /// output: a warehouse if there is a free slot and it can be paid, else
  /// a capacity level on the warehouse there with the cheapest one.
  Command? _addStorage(BodyState body) {
    final depot = c.buildings.values
        .where((d) => d.kind == BuildingKind.warehouse)
        .firstOrNull;
    if (depot == null) return null;
    if (hasFreeSlot(body) && canPay(body, depot.buildCost)) {
      return BuildCommand(factionId, body.id, depot.id);
    }
    (Command, BigNum)? best;
    for (final b in body.buildings) {
      if (def(b).kind != BuildingKind.warehouse ||
          !canUpgrade(b, UpgradeTrack.capacity)) {
        continue;
      }
      final cost = upgradeCost(c, b, UpgradeTrack.capacity);
      if (!canPay(body, cost)) continue;
      if (best == null || cost['credits']! < best.$2) {
        best = (
          UpgradeCommand(factionId, b.id, UpgradeTrack.capacity),
          cost['credits']!,
        );
      }
    }
    return best?.$1;
  }

  Command? _fixInput(BodyState body, String resourceId) {
    final local = _boostSupply(body, resourceId);
    if (local != null) return local;

    // Everything on [body] that uses it, so one route serves them all.
    var demand = const BigNum.zero();
    for (final b in body.buildings) {
      if (b.crew == 0) continue;
      final need = flowOf(body, b).inputs[resourceId];
      if (need != null) demand = demand + need;
    }
    final existing = s.routes
        .where((rt) => rt.toBodyId == body.id && rt.resourceId == resourceId)
        .firstOrNull;
    if (existing == null) return _route(resourceId, body, demand);
    final carries = existing.ratePerSecond.min(routeCapacity(c, existing));
    final from = s.body(existing.fromBodyId);
    if (carries >= demand.mulDouble(_routeSlack)) {
      // The route is big enough; its source is what runs short.
      return _boostSupply(from, resourceId);
    }
    // Too small for today's demand: carry more, with the ships for it from
    // the source, or ships sent there first.
    final rate = existing.ratePerSecond.max(demand.mulDouble(_feedHeadroom));
    final want = (rate.toDouble() / r.shipCapacityPerSecond).ceil();
    final held = stock(from, r.cargoShipResource).toDouble().floor();
    final ships = math.min(want, existing.cargoShips + held);
    if (ships > existing.cargoShips ||
        existing.ratePerSecond < demand.mulDouble(_routeSlack)) {
      return UpdateRouteCommand(
        factionId,
        existing.id,
        ratePerSecond: rate,
        cargoShips: ships > existing.cargoShips ? ships : null,
      );
    }
    return moveShipsTo(from, count: want - existing.cargoShips + held);
  }

  /// More [resourceId] made on [body]: the cheapest affordable upgrade of a
  /// staffed building there that makes it (speed if it runs freely,
  /// efficiency if it is itself short of inputs), else a new supplier.
  Command? _boostSupply(BodyState body, String resourceId) {
    (Command, BigNum)? upgrade;
    for (final b in body.buildings) {
      if (b.crew == 0 || !makes(b, resourceId)) continue;
      final t = _runsFreely(b) ? UpgradeTrack.speed : UpgradeTrack.efficiency;
      if (!canUpgrade(b, t)) continue;
      final cost = upgradeCost(c, b, t);
      if (!canPay(body, cost)) continue;
      if (upgrade == null || cost['credits']! < upgrade.$2) {
        upgrade = (UpgradeCommand(factionId, b.id, t), cost['credits']!);
      }
    }
    return upgrade?.$1 ?? _buildSupplier(body, resourceId);
  }

  /// The cheapest affordable building on [body] that makes [resourceId]:
  /// an extractor on its deposit, or a factory whose inputs [body] has a
  /// surplus of. Null without a free slot or free crew to staff it.
  Command? _buildSupplier(BodyState body, String resourceId) {
    if (!hasFreeSlot(body) || freeCrew < 1) return null;
    (Command, BigNum)? best;
    for (final d in c.buildings.values) {
      final String? deposit;
      if (d.kind == BuildingKind.extractor) {
        if (!d.extracts.contains(resourceId) ||
            !body.deposits.any((x) => x.resourceId == resourceId)) {
          continue;
        }
        deposit = resourceId;
      } else if (d.kind == BuildingKind.factory &&
          d.outputs.containsKey(resourceId) &&
          d.inputs.keys.every((i) => surplus(body, i) > 0)) {
        deposit = null;
      } else {
        continue;
      }
      if (!canPay(body, d.buildCost)) continue;
      final credits = d.buildCost['credits'] ?? const BigNum.zero();
      if (best == null || credits < best.$2) {
        best = (
          BuildCommand(factionId, body.id, d.id, depositResourceId: deposit),
          credits,
        );
      }
    }
    return best?.$1;
  }

  /// A route feeding [to]'s buildings [resourceId] at [_feedHeadroom]
  /// times their [rate] from the body in its system that makes the most
  /// spare of it (else one that holds some), with ships for that rate, or
  /// cargo ships sent to that body first when it has none ([moveShipsTo]).
  /// Null if no body can supply it or a route already brings it.
  ///
  /// The route stops at what [to] keeps for its buildings ([stopFor]): the
  /// headroom lets it keep up as they grow, and the stop keeps it from
  /// filling [to]'s storage, the surplus staying to be sold at the source.
  Command? _route(String resourceId, BodyState to, BigNum rate) {
    if (routeInto(to, resourceId)) return null;
    final from = _supplier(resourceId, to);
    if (from == null) return null;
    if (!hasShip(from)) return moveShipsTo(from);
    final carry = rate.mulDouble(_feedHeadroom);
    final ships = stock(from, r.cargoShipResource).toDouble().floor();
    final want = (carry.toDouble() / r.shipCapacityPerSecond).ceil();
    return CreateRouteCommand(
      factionId,
      from.id,
      to.id,
      resourceId,
      carry,
      math.max(1, math.min(ships, want)),
      stopAtDestination: stopFor(to, resourceId),
    );
  }

  /// The other owned body in [to]'s system with the largest surplus of
  /// [resourceId], else the first holding some; body order on a tie.
  BodyState? _supplier(String resourceId, BodyState to) {
    BodyState? best;
    var most = 0.0;
    for (final from in owned) {
      if (from.id == to.id || from.systemId != to.systemId) continue;
      final spare = surplus(from, resourceId);
      if (spare > most) {
        best = from;
        most = spare;
      }
    }
    return best ??
        owned
            .where(
              (o) =>
                  o.id != to.id &&
                  o.systemId == to.systemId &&
                  stock(o, resourceId) > const BigNum.zero(),
            )
            .firstOrNull;
  }

  /// Cargo ships on their way to [to] or held there.
  int shipsAt(BodyState to) {
    var n = stock(to, r.cargoShipResource).toDouble().floor();
    for (final sh in s.shipments) {
      if (sh.toBodyId == to.id && sh.resourceId == r.cargoShipResource) {
        n += sh.amount.toDouble().floor();
      }
    }
    return n;
  }

  /// Sends cargo ships to [to] until it holds or has on their way [count]
  /// ([_shipsSent] by default), from the other owned body in its system
  /// holding the most beyond [_shipsSent] of its own, as many as it can
  /// spare; null if [to] has them already or none can be spared.
  Command? moveShipsTo(BodyState to, {int count = _shipsSent}) {
    final short = count - shipsAt(to);
    if (short < 1) return null;
    BodyState? from;
    var most = _shipsSent;
    for (final o in owned) {
      if (o.id == to.id || o.systemId != to.systemId) continue;
      final held = stock(o, r.cargoShipResource).toDouble().floor();
      if (held > most) {
        from = o;
        most = held;
      }
    }
    if (from == null) return null;
    return MoveShipsCommand(
      factionId,
      from.id,
      to.id,
      math.min(short, most - _shipsSent),
    );
  }

  /// The first other owned body in [to]'s system with a surplus or stock of
  /// [resourceId] and a cargo ship, or null if there is none or a route
  /// already brings it.
  BodyState? routeSource(String resourceId, BodyState to) {
    if (routeInto(to, resourceId)) return null;
    for (final from in owned) {
      if (from.id == to.id || from.systemId != to.systemId) continue;
      if (!hasShip(from)) continue;
      if (surplus(from, resourceId) > 0 ||
          stock(from, resourceId) > const BigNum.zero()) {
        return from;
      }
    }
    return null;
  }
}

/// Whether [n] is a building short of an input, route-limited or not.
bool _isInput(Bottleneck n) =>
    n.kind == BottleneckKind.input || n.kind == BottleneckKind.routeLimited;
