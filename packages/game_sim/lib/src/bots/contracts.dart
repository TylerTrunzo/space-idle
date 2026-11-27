part of 'bot.dart';

/// The faction's contracts board: the next delivery or discard. The
/// engine's auto-sell holds back what open contracts still need.
extension _Contracts on _View {
  /// One step on the faction's contracts board, contracts in board order:
  /// discards a contract on a resource no staffed building makes and no
  /// owned body holds, or delivers what an owned body holds of a contract's
  /// resource beyond what it keeps for its own use ([keepForUse], at most half
  /// of what it holds) once that
  /// finishes the contract or the body's store is nearly full; null if
  /// neither is wanted. Contracts come before megaproject stages, which
  /// would otherwise take every unit of a good they share.
  Command? workContracts() {
    for (final k in faction.contracts) {
      final id = k.resourceId;
      if (!made(id) && owned.every((b) => stock(b, id).isZero)) {
        return DiscardContractCommand(factionId, k.id);
      }
      for (final body in owned) {
        final held = stock(body, id);
        // At most half of what a body holds is kept back from a contract,
        // so a good its own buildings use heavily can still be delivered.
        // Deliveries move whole units.
        final spare = (held - keepForUse(body, id).min(held.mulDouble(0.5)))
            .floor();
        if (spare <= const BigNum.zero()) continue;
        if (spare >= k.remaining ||
            stock(body, id) >= storageCap(s, c, body).mulDouble(_fullShare)) {
          return DeliverContractCommand(
            factionId,
            k.id,
            body.id,
            spare.min(k.remaining),
          );
        }
      }
    }
    return null;
  }
}
