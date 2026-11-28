part of 'apply.dart';

// Logistics and the market: routes, ship moves, sales and auto-sell rules.

/// The failure if [from] and [to], bodies in sight of [f], are not a pair
/// goods can move between: both owned by [f], different, and in one
/// system; else null.
CommandFailed? _checkPair(
  GameState s,
  FactionState f,
  BodyState from,
  BodyState to,
) {
  if (from.ownerId != f.id) return _notYours(s, f, from);
  if (to.ownerId != f.id) return _notYours(s, f, to);
  if (from.id == to.id) {
    return _fail(
      CommandError.routeInvalid,
      'From and to are both ${from.name}; pick two different bodies',
    );
  }
  if (from.systemId != to.systemId) {
    return _fail(
      CommandError.routeInvalid,
      '${from.name} and ${to.name} are in different systems',
    );
  }
  return null;
}

/// The failure if [stop], a route's stop level, is not above zero.
CommandFailed? _checkStop(BigNum? stop) =>
    stop != null && stop <= const BigNum.zero()
    ? _fail(CommandError.invalidAmount, 'The stock to stop at must be above 0')
    : null;

/// [stop], a route's stop level, kept to the storage cap of [to], its
/// destination, with the cap when that cut it (else null): stock above
/// the cap is wasted at the end of every tick, so a higher level would
/// only waste the cargo that fills it.
(BigNum?, BigNum?) _fitStop(
  GameState s,
  Content c,
  BodyState to,
  BigNum? stop,
) {
  if (stop == null) return (null, null);
  final cap = storageCap(s, c, to);
  return stop > cap ? (cap, cap) : (stop, null);
}

/// "the route from Kora to Brine": route [r] by its endpoints' names.
String _routeName(GameState s, RouteState r) =>
    'the route from ${s.body(r.fromBodyId).name} '
    'to ${s.body(r.toBodyId).name}';

CommandResult _createRoute(
  GameState s,
  Content c,
  FactionState f,
  CreateRouteCommand cmd,
) {
  final from = _findBody(s, f, cmd.fromBodyId);
  if (from == null) return _unknownBody(cmd.fromBodyId);
  final to = _findBody(s, f, cmd.toBodyId);
  if (to == null) return _unknownBody(cmd.toBodyId);
  if (!c.resources.containsKey(cmd.resourceId)) {
    return _unknownResource(cmd.resourceId);
  }
  final bad = _checkPair(s, f, from, to);
  if (bad != null) return bad;
  if (cmd.cargoShips < 1) {
    return _fail(
      CommandError.invalidAmount,
      'A route needs at least one cargo ship',
    );
  }
  if (cmd.ratePerSecond <= const BigNum.zero()) {
    return _fail(CommandError.invalidAmount, 'Rate must be above 0');
  }
  final badStop = _checkStop(cmd.stopAtDestination);
  if (badStop != null) return badStop;
  final ships = {c.rules.cargoShipResource: BigNum.from(cmd.cargoShips)};
  final short = _checkCost(c, f, from, ships);
  if (short != null) return short;

  final (stop, clamped) = _fitStop(s, c, to, cmd.stopAtDestination);
  _pay(f, from, ships);
  final r = RouteState(
    id: s.newId('r'),
    ownerId: f.id,
    fromBodyId: from.id,
    toBodyId: to.id,
    resourceId: cmd.resourceId,
    ratePerSecond: cmd.ratePerSecond,
    cargoShips: cmd.cargoShips,
    stopAtDestination: stop,
  );
  s.routes.add(r);
  return CommandOk(
    createdId: r.id,
    outcome: RouteCreated(
      bodyId: from.id,
      routeId: r.id,
      stopClampedTo: clamped,
      spent: ships,
    ),
  );
}

/// [f]'s route [id], or the failure if there is none or another faction
/// owns it.
(RouteState?, CommandFailed?) _ownedRoute(
  GameState s,
  FactionState f,
  String id,
) {
  for (final r in s.routes) {
    if (r.id != id) continue;
    if (r.ownerId != f.id) return (null, _notOwner(_routeName(s, r)));
    return (r, null);
  }
  return (null, _fail(CommandError.routeInvalid, 'There is no route $id'));
}

CommandResult _updateRoute(
  GameState s,
  Content c,
  FactionState f,
  UpdateRouteCommand cmd,
) {
  final (r, missing) = _ownedRoute(s, f, cmd.routeId);
  if (r == null) return missing!;
  final rate = cmd.ratePerSecond;
  final ships = cmd.cargoShips;
  final stop = cmd.stopAtDestination;
  if (rate == null &&
      ships == null &&
      stop == null &&
      !cmd.removeStopAtDestination) {
    return _fail(
      CommandError.invalidAmount,
      'Name what to change on ${_routeName(s, r)}: its rate, cargo ships '
      'or the stock to stop at',
    );
  }
  if (stop != null && cmd.removeStopAtDestination) {
    return _fail(
      CommandError.invalidAmount,
      'Set a stock to stop at or remove it, not both',
    );
  }
  if (rate != null && rate <= const BigNum.zero()) {
    return _fail(CommandError.invalidAmount, 'Rate must be above 0');
  }
  final badStop = _checkStop(stop);
  if (badStop != null) return badStop;
  final from = s.body(r.fromBodyId);
  final extra = (ships ?? r.cargoShips) - r.cargoShips;
  if (ships != null) {
    if (ships < 1) {
      return _fail(
        CommandError.invalidAmount,
        'A route needs at least one cargo ship',
      );
    }
    if (extra != 0 && from.ownerId != f.id) return _notYours(s, f, from);
    if (extra > 0) {
      final short = _checkCost(c, f, from, {
        c.rules.cargoShipResource: BigNum.from(extra),
      });
      if (short != null) return short;
    }
  }

  final (fitted, clamped) = _fitStop(s, c, s.body(r.toBodyId), stop);
  final shipId = c.rules.cargoShipResource;
  if (extra > 0) {
    from.take(shipId, BigNum.from(extra));
  } else if (extra < 0) {
    from.stock[shipId] =
        (from.stock[shipId] ?? const BigNum.zero()) + BigNum.from(-extra);
  }
  r.cargoShips += extra;
  if (rate != null) r.ratePerSecond = rate;
  if (fitted != null) r.stopAtDestination = fitted;
  if (cmd.removeStopAtDestination) r.stopAtDestination = null;
  return CommandOk(
    outcome: RouteUpdated(
      bodyId: from.id,
      routeId: r.id,
      stopClampedTo: clamped,
      spent: {if (extra > 0) shipId: BigNum.from(extra)},
      gained: {if (extra < 0) shipId: BigNum.from(-extra)},
    ),
  );
}

CommandResult _moveShips(
  GameState s,
  Content c,
  FactionState f,
  MoveShipsCommand cmd,
) {
  final from = _findBody(s, f, cmd.fromBodyId);
  if (from == null) return _unknownBody(cmd.fromBodyId);
  final to = _findBody(s, f, cmd.toBodyId);
  if (to == null) return _unknownBody(cmd.toBodyId);
  final bad = _checkPair(s, f, from, to);
  if (bad != null) return bad;
  if (cmd.count < 1) {
    return _fail(CommandError.invalidAmount, 'Move at least one cargo ship');
  }
  final ships = {c.rules.cargoShipResource: BigNum.from(cmd.count)};
  final short = _checkCost(c, f, from, ships);
  if (short != null) return short;

  _pay(f, from, ships);
  final id = s.newId('m');
  final arriveAt = s.time + travelSeconds(s, c, from, to);
  s.shipments.add(
    Shipment(
      routeId: id,
      fromBodyId: from.id,
      toBodyId: to.id,
      ownerId: f.id,
      resourceId: c.rules.cargoShipResource,
      amount: BigNum.from(cmd.count),
      departAt: s.time,
      arriveAt: arriveAt,
    ),
  );
  return CommandOk(
    createdId: id,
    outcome: ShipsSent(
      bodyId: from.id,
      shipmentId: id,
      toBodyId: to.id,
      count: cmd.count,
      arriveAt: arriveAt,
      spent: ships,
    ),
  );
}

CommandResult _removeRoute(
  GameState s,
  Content c,
  FactionState f,
  RemoveRouteCommand cmd,
) {
  final (r, missing) = _ownedRoute(s, f, cmd.routeId);
  if (r == null) return missing!;

  final from = s.body(r.fromBodyId);
  final ships = c.rules.cargoShipResource;
  from.stock[ships] =
      (from.stock[ships] ?? const BigNum.zero()) + BigNum.from(r.cargoShips);
  s.routes.remove(r);
  return CommandOk(
    outcome: RouteRemoved(
      bodyId: from.id,
      routeId: r.id,
      gained: {ships: BigNum.from(r.cargoShips)},
    ),
  );
}

CommandResult _sell(GameState s, Content c, FactionState f, SellCommand cmd) {
  final body = _findBody(s, f, cmd.bodyId);
  if (body == null) return _unknownBody(cmd.bodyId);
  if (!c.resources.containsKey(cmd.resourceId)) {
    return _unknownResource(cmd.resourceId);
  }
  if (body.ownerId != f.id) return _notYours(s, f, body);
  if (cmd.amount <= const BigNum.zero()) {
    return _fail(CommandError.invalidAmount, 'Amount must be above 0');
  }
  final held = body.stock[cmd.resourceId] ?? const BigNum.zero();
  if (held <= const BigNum.zero()) {
    return _fail(
      CommandError.invalidAmount,
      '${body.name} has no ${_resourceName(c, cmd.resourceId)} to sell',
    );
  }

  final sale = sell(s, c, f.id, body.id, cmd.resourceId, cmd.amount);
  return CommandOk(
    outcome: Sold(
      bodyId: body.id,
      resourceId: cmd.resourceId,
      amount: sale.sold,
      revenue: sale.revenue,
    ),
  );
}

CommandResult _setAutoSell(
  GameState s,
  Content c,
  FactionState f,
  SetAutoSellCommand cmd,
) {
  final body = _findBody(s, f, cmd.bodyId);
  if (body == null) return _unknownBody(cmd.bodyId);
  if (!c.resources.containsKey(cmd.resourceId)) {
    return _unknownResource(cmd.resourceId);
  }
  if (body.ownerId != f.id) return _notYours(s, f, body);
  final keep = cmd.keepAtLeast;
  if (keep != null && keep.isNegative) {
    return _fail(
      CommandError.invalidAmount,
      "The amount to keep can't be negative",
    );
  }

  final i = f.autoSell.indexWhere(
    (r) => r.bodyId == body.id && r.resourceId == cmd.resourceId,
  );
  if (keep == null) {
    if (i >= 0) f.autoSell.removeAt(i);
  } else if (i >= 0) {
    f.autoSell[i].keepAtLeast = keep;
  } else {
    f.autoSell.add(
      AutoSellRule(
        bodyId: body.id,
        resourceId: cmd.resourceId,
        keepAtLeast: keep,
      ),
    );
  }
  return CommandOk(
    outcome: AutoSellSet(
      bodyId: body.id,
      resourceId: cmd.resourceId,
      keepAtLeast: keep,
    ),
  );
}
