import 'package:game_core/game_core.dart';

/// Test fixture: hands Hollow Reach to the player and adds a Kora → Hollow
/// Reach route with one shipment that left [departIn] seconds from now
/// (negative: in the past) and takes [tripSeconds].
void addRouteAndShipment(
  GameState s, {
  double departIn = -25,
  double tripSeconds = 100,
}) {
  s.body('hollow_reach').ownerId = 'player';
  s.routes.add(
    RouteState(
      id: 'r_test',
      ownerId: 'player',
      fromBodyId: 'kora',
      toBodyId: 'hollow_reach',
      resourceId: 'iron_ore',
      ratePerSecond: BigNum.from(1),
      cargoShips: 1,
    ),
  );
  final departAt = s.time + departIn;
  s.shipments.add(
    Shipment(
      routeId: 'r_test',
      fromBodyId: 'kora',
      toBodyId: 'hollow_reach',
      ownerId: 'player',
      resourceId: 'iron_ore',
      amount: BigNum.from(5),
      departAt: departAt,
      arriveAt: departAt + tripSeconds,
    ),
  );
}
