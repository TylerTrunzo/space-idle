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
  final body = _findBody(s, f, cmd.bodyId);
  if (body == null) return _unknownBody(cmd.bodyId);
  if (body.ownerId != f.id) return _notYours(s, f, body);
  if (cmd.amount <= const BigNum.zero()) {
    return _fail(CommandError.invalidAmount, 'Amount must be above 0');
  }
  final held = body.stock[k.resourceId] ?? const BigNum.zero();
  if (held <= const BigNum.zero()) {
    return _fail(
      CommandError.invalidAmount,
      '${body.name} has no ${_resourceName(c, k.resourceId)} to deliver',
    );
  }

  final amount = cmd.amount.min(held).min(k.remaining);
  body.take(k.resourceId, amount);
  k.delivered = k.delivered + amount;
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
      bodyId: body.id,
      contractId: k.id,
      resourceId: k.resourceId,
      delivered: amount,
      totalDelivered: k.delivered,
      quantity: k.quantity,
      rewardPaid: done ? k.rewardCredits : null,
      nextContractAt: done ? f.contractRefillAt.firstOrNull : null,
    ),
  );
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
