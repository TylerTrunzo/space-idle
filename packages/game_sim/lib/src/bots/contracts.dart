part of 'bot.dart';

/// The faction's contracts board: the next delivery or discard. The
/// engine's auto-sell holds back what open contracts still need.
extension _Contracts on _View {
  /// One step on the faction's contracts board, contracts in board order:
  /// discards a contract on a resource no staffed building makes and no
  /// owned body holds, or delivers, in one command from every owned body
  /// (`DeliverContractCommand` with no body), what the owned bodies hold of
  /// a contract's resource beyond what each keeps for its own use
  /// ([keepForUse], at most half of what it holds), once that finishes the
  /// contract or a body's store of it is nearly full; null if neither is
  /// wanted. The engine takes from the fullest bodies first. Contracts come
  /// before megaproject stages, which would otherwise take every unit of a
  /// good they share.
  Command? workContracts() {
    for (final k in faction.contracts) {
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
