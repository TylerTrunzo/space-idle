part of 'bot.dart';

/// The faction's contracts board: the next delivery or discard. The
/// engine's auto-sell holds back what open contracts still need.
extension _Contracts on _View {
  /// One step on the faction's contracts board, contracts in board order:
  /// discards a contract on a resource no staffed building makes and no
  /// owned body holds, or, with a flow report (the balanced and casual
  /// bots), one whose remaining units the spare stock and a day
  /// ([_fillWithinSeconds]) of the owned bodies' net production
  /// ([surplus]) would not cover, so a slot is not held for days by an
  /// order the empire consumes as it makes; or delivers, in one command
  /// from every owned body
  /// (`DeliverContractCommand` with no body), what the owned bodies hold of
  /// a contract's resource beyond what each keeps for its own use
  /// ([keepForUse], at most half of what it holds), once that finishes the
  /// contract or a body's store of it is nearly full; null if neither is
  /// wanted. The engine takes from the fullest bodies first. Contracts come
  /// before megaproject stages, which would otherwise take every unit of a
  /// good they share. But with a flow report, a contract that has held
  /// goods a megaproject fed on its own still owes for more than
  /// [_blockedForSeconds] ([FlowReport.contractBlocks]) is discarded: a
  /// side job never stalls a stage the faction is feeding.
  Command? workContracts() {
    for (final k in faction.contracts) {
      if (report?.contractBlocks.any(
            (n) =>
                n.contractId == k.id &&
                s.time - n.firstSeenAt > _blockedForSeconds,
          ) ??
          false) {
        return DiscardContractCommand(factionId, k.id);
      }
      final id = k.resourceId;
      if (!made(id) && owned.every((b) => stock(b, id).isZero)) {
        return DiscardContractCommand(factionId, k.id);
      }
      var spare = const BigNum.zero();
      var full = false;
      for (final body in owned) {
        final held = stock(body, id);
        // At most half of what a body holds is kept back from a contract,
        // so a good its own buildings use heavily can still be delivered.
        // Deliveries move whole units.
        final free = (held - keepForUse(body, id).min(held.mulDouble(0.5)))
            .floor();
        if (free <= const BigNum.zero()) continue;
        spare = spare + free;
        if (held >= storageCap(s, c, body).mulDouble(_fullShare)) full = true;
      }
      if (report != null) {
        final rate = owned.fold(
          0.0,
          (t, b) => t + math.max(0.0, surplus(b, id)),
        );
        if (spare.toDouble() + rate * _fillWithinSeconds <
            k.remaining.toDouble()) {
          return DiscardContractCommand(factionId, k.id);
        }
      }
      if (spare <= const BigNum.zero()) continue;
      if (spare >= k.remaining || full) {
        return DeliverContractCommand(
          factionId,
          k.id,
          null,
          spare.min(k.remaining),
        );
      }
    }
    return null;
  }
}

/// Game seconds within which the balanced and casual bots expect to fill a
/// contract at today's net production ([_Contracts.workContracts]); a
/// longer one is discarded: about a day.
const double _fillWithinSeconds = 86400;

/// Game seconds after which the balanced and casual bots discard a
/// contract that holds goods a megaproject they feed still owes
/// ([_Contracts.workContracts]): a day.
const double _blockedForSeconds = 86400;
