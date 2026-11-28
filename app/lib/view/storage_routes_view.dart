import 'package:game_core/game_core.dart';
import 'package:meta/meta.dart';
import 'package:space_idle/game/game_controller.dart';

/// One choice in a storage row's Sell chooser.
@immutable
final class SellOption {
  /// Creates an option.
  const SellOption({
    required this.label,
    required this.amount,
    required this.amountText,
    required this.revenue,
  });

  /// "25%", "50%" or "All".
  final String label;

  /// Units it sells.
  final BigNum amount;

  /// [amount], formatted.
  final String amountText;

  /// Credits it would earn, formatted: what the sell command pays,
  /// saturation included, not the price times the amount.
  final String revenue;
}

/// The Sell chooser for [resourceId] on [bodyId]: a quarter, a half and
/// all of the stock, each with what it would earn.
///
/// Each revenue is a dry run of the real sell command on a copy of the
/// state, so it is worked out only when the chooser opens. A part that
/// rounds down to nothing, or to all of it, is left out; an empty store
/// offers nothing.
List<SellOption> sellOptions(
  GameController c,
  String bodyId,
  String resourceId,
) {
  final stock = c.state.body(bodyId).stock[resourceId] ?? const BigNum.zero();
  if (stock <= const BigNum.zero()) return const [];
  SellOption option(String label, BigNum amount) {
    final r = c.engine.apply(
      c.state.copy(),
      SellCommand(c.playerId, bodyId, resourceId, amount),
    );
    final earned = switch (r) {
      CommandOk(outcome: final Sold o) => o.revenue,
      _ => const BigNum.zero(),
    };
    return SellOption(
      label: label,
      amount: amount,
      amountText: formatNumber(amount),
      revenue: formatNumber(earned),
    );
  }

  return [
    for (final (label, share) in [('25%', 0.25), ('50%', 0.5)])
      if (stock.mulDouble(share).floor() case final part
          when part > const BigNum.zero() && part < stock)
        option(label, part),
    option('All', stock),
  ];
}

/// A body offered in a form: its id and name.
typedef BodyChoice = ({String id, String name});

/// A resource offered in a form: its id and name.
typedef ResourceChoice = ({String id, String name});

/// What the New route and Move ships forms on [bodyId] can offer.
@immutable
final class RouteFormView {
  /// Creates a view.
  const RouteFormView({
    required this.destinations,
    required this.resources,
    required this.ships,
  });

  /// The player's other bodies in the same system, in body order.
  final List<BodyChoice> destinations;

  /// The resources it holds, cargo ships aside, in content order.
  final List<ResourceChoice> resources;

  /// Whole cargo ships in its stock.
  final int ships;
}

/// The route forms for [bodyId]. Which are valid is the commands' call:
/// the forms run them and show their reason when they fail.
RouteFormView routeForm(GameController c, String bodyId) {
  final s = c.state;
  final body = s.body(bodyId);
  final ship = c.content.rules.cargoShipResource;
  final ships = (body.stock[ship] ?? const BigNum.zero()).floor().toDouble();
  return RouteFormView(
    destinations: [
      for (final b in s.bodies)
        if (b.id != bodyId &&
            b.ownerId == c.playerId &&
            b.systemId == body.systemId)
          (id: b.id, name: b.name),
    ],
    resources: [
      for (final MapEntry(key: id, value: def) in c.content.resources.entries)
        if (id != ship &&
            (body.stock[id] ?? const BigNum.zero()) > const BigNum.zero())
          (id: id, name: def.name),
    ],
    ships: ships.isFinite && ships > 0 ? ships.round() : 0,
  );
}

/// [v] as a plain number a text field can read back: `1500`, `0.5`,
/// `1e+40`, never the display form (`1.5K`) that would not parse.
String editableNumber(BigNum v) {
  final d = v.toDouble();
  if (d == d.truncateToDouble() && d.abs() < 1e15) {
    return d.toInt().toString();
  }
  return d.toString();
}
