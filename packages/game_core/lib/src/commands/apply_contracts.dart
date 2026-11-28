part of 'apply.dart';

// The contracts board: deliveries to contracts and discards.

/// [f]'s contract [id], or null if its board has none.
ContractState? _findContract(FactionState f, String id) {
  for (final k in f.contracts) {
    if (k.id == id) return k;
  }
  return null;
}

CommandFailed _unknownContract(String id) =>
    _fail(CommandError.unknownContract, 'You have no contract $id');

CommandResult _deliverContract(
  GameState s,
  Content c,
  FactionState f,
  DeliverContractCommand cmd,
) {
  final k = _findContract(f, cmd.contractId);
  if (k == null) return _unknownContract(cmd.contractId);
  final List<BodyState> from;
  if (cmd.bodyId case final id?) {
    final body = _findBody(s, f, id);
    if (body == null) return _unknownBody(id);
    if (body.ownerId != f.id) return _notYours(s, f, body);
    from = [body];
  } else {
    from = _holdersOf(s, f, k.resourceId);
  }
  if (cmd.amount <= const BigNum.zero()) {
    return _fail(CommandError.invalidAmount, 'Amount must be above 0');
  }
  if (cmd.amount < _oneUnit) return _wholeUnitsOnly();
  if (cmd.bodyId != null) {
    final body = from.single;
    final held = body.stock[k.resourceId] ?? const BigNum.zero();
    if (held <= const BigNum.zero()) {
      return _fail(
        CommandError.invalidAmount,
        '${body.name} has no ${_resourceName(c, k.resourceId)} to deliver',
      );
    }
    if (held.floor().isZero) {
      return _fail(
        CommandError.invalidAmount,
        '${body.name} has less than one whole '
        '${_resourceName(c, k.resourceId)} to deliver',
      );
    }
  } else if (from.isEmpty) {
    return _fail(
      CommandError.invalidAmount,
      'None of your bodies has a whole ${_resourceName(c, k.resourceId)} '
      'to deliver',
    );
  }

  // Whole units only, so what is left stays whole too.
  var left = cmd.amount.min(k.remaining).floor();
  final taken = <String, BigNum>{};
  for (final body in from) {
    if (left <= const BigNum.zero()) break;
    final amount = (body.stock[k.resourceId] ?? const BigNum.zero())
        .floor()
        .min(left);
    if (amount <= const BigNum.zero()) continue;
    body.take(k.resourceId, amount);
    taken[body.id] = amount;
    left = left - amount;
  }
  var delivered = const BigNum.zero();
  for (final v in taken.values) {
    delivered = delivered + v;
  }
  k.delivered = k.delivered + delivered;
  final done = k.delivered >= k.quantity;
  if (done) {
    k.delivered = k.quantity;
    f.credits = f.credits + k.rewardCredits;
    f.lifetimeCredits = f.lifetimeCredits + k.rewardCredits;
    f.contractsCompleted++;
    f.contracts.remove(k);
    freeContractSlot(f, c, s.time);
  }
  return CommandOk(
    outcome: ContractProgress(
      bodyId: cmd.bodyId,
      fromBodies: taken,
      contractId: k.id,
      resourceId: k.resourceId,
      delivered: delivered,
      totalDelivered: k.delivered,
      quantity: k.quantity,
      rewardPaid: done ? k.rewardCredits : null,
      nextContractAt: done ? f.contractRefillAt.firstOrNull : null,
    ),
  );
}

/// The bodies [f] owns holding at least one whole unit of [resourceId],
/// the one holding the most first, ties by body id.
List<BodyState> _holdersOf(GameState s, FactionState f, String resourceId) {
  BigNum held(BodyState b) => b.stock[resourceId] ?? const BigNum.zero();
  return [
    for (final b in s.bodies)
      if (b.ownerId == f.id && held(b) >= _oneUnit) b,
  ]..sort((x, y) {
    final byStock = held(y).compareTo(held(x));
    return byStock != 0 ? byStock : x.id.compareTo(y.id);
  });
}

CommandResult _discardContract(
  GameState s,
  Content c,
  FactionState f,
  DiscardContractCommand cmd,
) {
  final k = _findContract(f, cmd.contractId);
  if (k == null) return _unknownContract(cmd.contractId);

  f.contracts.remove(k);
  freeContractSlot(f, c, s.time);
  return CommandOk(
    outcome: ContractDiscarded(
      contractId: k.id,
      resourceId: k.resourceId,
      quantity: k.quantity,
      nextContractAt: f.contractRefillAt.firstOrNull,
    ),
  );
}
