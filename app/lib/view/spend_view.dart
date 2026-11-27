import 'package:game_core/game_core.dart';
import 'package:space_idle/game/game_controller.dart';

/// Spends above this share of the credits held ask for a second, inline
/// tap before they go through.
const double confirmShare = 0.5;

/// Whether spending [price] credits out of [held] is big enough to
/// confirm first: more than [confirmShare] of them.
///
/// One the player cannot afford is not asked about: it goes to the
/// command, which says why it fails, so a confirm never offers a spend
/// that a stale button still showed as affordable.
bool needsConfirm(BigNum price, BigNum held) =>
    price <= held && price > held.mulDouble(confirmShare);

/// Up to [levels] levels of [track] on building [buildingId], bought one
/// after another as a long press would: how many the player can afford
/// now and their credits in all.
///
/// A dry run of the real upgrade command on a copy of the state;
/// [GameController.state] is not touched.
({int levels, BigNum price}) bulkUpgrade(
  GameController c,
  String buildingId,
  UpgradeTrack track,
  int levels,
) {
  final copy = c.state.copy();
  final before = copy.faction(c.playerId).credits;
  final cmd = UpgradeCommand(c.playerId, buildingId, track);
  var bought = 0;
  while (bought < levels && c.engine.apply(copy, cmd) is CommandOk) {
    bought++;
  }
  return (levels: bought, price: before - copy.faction(c.playerId).credits);
}
