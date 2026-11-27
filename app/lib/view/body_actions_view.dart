import 'package:game_core/game_core.dart';
import 'package:meta/meta.dart';
import 'package:space_idle/game/game_controller.dart';
import 'package:space_idle/view/messages.dart';
import 'package:space_idle/view/project_views.dart';
import 'package:space_idle/view/spend_view.dart';

/// The "Expand slots (+1)" row of an owned body.
@immutable
final class ExpandSlotsView {
  /// Creates a view.
  const ExpandSlotsView({
    required this.cost,
    required this.price,
    required this.time,
    required this.affordable,
    required this.running,
    required this.blockedReason,
  });

  /// What the next slot costs, such as "2K credits".
  final String cost;

  /// Its price in credits, as a number, for the spend confirm.
  final BigNum price;

  /// How long it takes, such as "4h".
  final String time;

  /// Whether it can be started now.
  final bool affordable;

  /// The slot under way, if any.
  final ProjectView? running;

  /// Why it cannot start now; null when it can or one is running.
  final String? blockedReason;
}

/// Body [bodyId]'s expand-slots row; null unless the player owns it.
///
/// The checks follow the expand-slots command's own order: one under way,
/// the most extra slots, then the credits.
ExpandSlotsView? expandSlotsView(GameController c, String bodyId) {
  final s = c.state;
  final body = s.bodies.where((b) => b.id == bodyId).firstOrNull;
  if (body == null || body.ownerId != c.playerId) return null;
  final cost = slotCost(c.content, body)[creditsKey] ?? const BigNum.zero();
  final have = s.faction(c.playerId).credits;
  final running = projectOn(s, ProjectKind.expandSlots, bodyId);
  final String? blocked;
  if (running != null) {
    blocked = null;
  } else if (body.extraSlots >= SaveCodec.maxExtraSlots) {
    blocked = 'at the most extra slots (${SaveCodec.maxExtraSlots})';
  } else if (have < cost) {
    blocked =
        'needs ${formatNumber(cost)} credits '
        '(you have ${formatNumber(have, rounding: NumberRounding.down)})';
  } else {
    blocked = null;
  }
  return ExpandSlotsView(
    cost: '${formatNumber(cost)} credits',
    price: cost,
    time: formatDuration(c.content.rules.expandSlotsSeconds),
    affordable: running == null && blocked == null,
    running: running == null ? null : projectView(c, running),
    blockedReason: blocked,
  );
}

/// What the "Buy max" button would buy now, worked out by running the
/// real command on a copy of the state: the cheapest upgrade levels on
/// every owned body's buildings, with all the player's credits as budget.
@immutable
final class BuyMaxView {
  /// Creates a view.
  const BuyMaxView({
    required this.levels,
    required this.buildings,
    required this.cost,
    required this.share,
    required this.blockedReason,
  });

  /// Levels it would buy.
  final int levels;

  /// Buildings they are on.
  final int buildings;

  /// What they would cost in all, formatted.
  final String cost;

  /// That cost as a share of the credits held, 0 to 1.
  final double share;

  /// Why it would buy nothing, such as "the cheapest costs 75 credits,
  /// more than the budget allows"; null when it would buy something.
  final String? blockedReason;

  /// Whether the spend is big enough to confirm first.
  bool get confirm => share > confirmShare;
}

/// The Buy max preview from a dry run; [GameController.state] is not
/// touched.
BuyMaxView buyMaxView(GameController c) {
  final credits = c.state.faction(c.playerId).credits;
  final copy = c.state.copy();
  final r = c.engine.apply(copy, BuyUpgradesCommand(c.playerId, credits));
  final o = switch (r) {
    CommandOk(outcome: final UpgradesBought o) => o,
    _ => null,
  };
  if (o == null) {
    return BuyMaxView(
      levels: 0,
      buildings: 0,
      cost: '0',
      share: 0,
      blockedReason: r is CommandFailed ? r.message : 'nothing to buy',
    );
  }
  final held = credits.toDouble();
  return BuyMaxView(
    levels: o.levels,
    buildings: {for (final p in o.purchases) p.buildingId}.length,
    cost: formatNumber(o.total),
    share: held <= 0 ? 0 : (o.total.toDouble() / held).clamp(0.0, 1.0),
    blockedReason: o.levels == 0 ? upgradesStopText(o) : null,
  );
}
