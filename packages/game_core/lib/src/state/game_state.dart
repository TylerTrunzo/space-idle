import '../content/content.dart';
import '../num/big_num.dart';
import '../rng.dart';

Map<String, Object?> _asMap(Object? v) => (v as Map).cast<String, Object?>();

List<T> _list<T>(Object? v, T Function(Map<String, Object?>) f) => [
  for (final e in (v as List)) f(_asMap(e)),
];

Map<String, BigNum> _bigMap(Object? v) => {
  for (final e in _asMap(v).entries) e.key: BigNum.fromJson(e.value! as String),
};

/// A rule that sells a body's surplus of one resource automatically.
final class AutoSellRule {
  /// Creates a rule.
  AutoSellRule({
    required this.bodyId,
    required this.resourceId,
    required this.keepAtLeast,
  });

  /// Restores a rule written by [toJson].
  factory AutoSellRule.fromJson(Map<String, Object?> j) => AutoSellRule(
    bodyId: j['bodyId']! as String,
    resourceId: j['resourceId']! as String,
    keepAtLeast: BigNum.fromJson(j['keepAtLeast']! as String),
  );

  /// Body whose stock is sold.
  final String bodyId;

  /// Resource sold.
  final String resourceId;

  /// Units always kept; only the excess is sold.
  BigNum keepAtLeast;

  /// Serializes this rule.
  Map<String, Object?> toJson() => {
    'bodyId': bodyId,
    'resourceId': resourceId,
    'keepAtLeast': keepAtLeast.toJson(),
  };
}

/// A faction's mutable state: the player or an AI rival.
final class FactionState {
  /// Creates a faction.
  FactionState({
    required this.id,
    required this.name,
    required this.isPlayer,
    required this.credits,
    required this.baseCrew,
    List<AutoSellRule>? autoSell,
    Set<String>? reachedMilestones,
  }) : autoSell = autoSell ?? [],
       reachedMilestones = reachedMilestones ?? {};

  /// Restores a faction written by [toJson].
  factory FactionState.fromJson(Map<String, Object?> j) => FactionState(
    id: j['id']! as String,
    name: j['name']! as String,
    isPlayer: j['isPlayer']! as bool,
    credits: BigNum.fromJson(j['credits']! as String),
    baseCrew: j['baseCrew']! as int,
    autoSell: _list(j['autoSell'], AutoSellRule.fromJson),
    reachedMilestones: {
      for (final e in j['reachedMilestones']! as List) e as String,
    },
  );

  /// Unique id.
  final String id;

  /// Display name.
  final String name;

  /// Whether a human plays this faction.
  final bool isPlayer;

  /// Credits held.
  BigNum credits;

  /// Crew available without habitats.
  int baseCrew;

  /// Auto-sell rules in priority order.
  final List<AutoSellRule> autoSell;

  /// Ids of milestones already reached.
  final Set<String> reachedMilestones;

  /// Serializes this faction; milestones are written sorted.
  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'isPlayer': isPlayer,
    'credits': credits.toJson(),
    'baseCrew': baseCrew,
    'autoSell': [for (final r in autoSell) r.toJson()],
    'reachedMilestones': reachedMilestones.toList()..sort(),
  };
}

/// One constructed building and its upgrade levels.
final class BuildingState {
  /// Creates a building; every upgrade track starts at level 0 unless given.
  BuildingState({
    required this.id,
    required this.defId,
    this.depositResourceId,
    required this.crew,
    Map<UpgradeTrack, int>? levels,
    this.lastRunFraction = 0,
    this.lastLimitReason,
  }) : levels = {for (final t in UpgradeTrack.values) t: levels?[t] ?? 0};

  /// Restores a building written by [toJson].
  factory BuildingState.fromJson(Map<String, Object?> j) {
    final lv = _asMap(j['levels']);
    return BuildingState(
      id: j['id']! as String,
      defId: j['defId']! as String,
      depositResourceId: j['depositResourceId'] as String?,
      crew: j['crew']! as int,
      levels: {
        for (final t in UpgradeTrack.values) t: (lv[t.name] as int?) ?? 0,
      },
      lastRunFraction: (j['lastRunFraction']! as num).toDouble(),
      lastLimitReason: j['lastLimitReason'] as String?,
    );
  }

  /// Unique id.
  final String id;

  /// Id of its [BuildingDef].
  final String defId;

  /// Extractor only: the deposit it mines.
  final String? depositResourceId;

  /// Crew assigned.
  int crew;

  /// Level of every upgrade track.
  final Map<UpgradeTrack, int> levels;

  /// Fraction of full rate achieved in the last step.
  double lastRunFraction;

  /// Why the last step ran below full rate, if it did.
  String? lastLimitReason;

  /// Serializes this building.
  Map<String, Object?> toJson() => {
    'id': id,
    'defId': defId,
    'depositResourceId': depositResourceId,
    'crew': crew,
    'levels': {for (final e in levels.entries) e.key.name: e.value},
    'lastRunFraction': lastRunFraction,
    'lastLimitReason': lastLimitReason,
  };
}

/// A planet, moon, or belt and what is built on it.
final class BodyState {
  /// Creates a body.
  BodyState({
    required this.id,
    required this.name,
    required this.systemId,
    required this.typeId,
    required this.orbit,
    required this.deposits,
    this.ownerId,
    Map<String, BigNum>? stock,
    List<BuildingState>? buildings,
  }) : stock = stock ?? {},
       buildings = buildings ?? [];

  /// Restores a body written by [toJson].
  factory BodyState.fromJson(Map<String, Object?> j) => BodyState(
    id: j['id']! as String,
    name: j['name']! as String,
    systemId: j['systemId']! as String,
    typeId: j['typeId']! as String,
    orbit: j['orbit']! as int,
    deposits: [
      for (final d in j['deposits']! as List)
        DepositDef(
          resourceId: _asMap(d)['resourceId']! as String,
          richness: (_asMap(d)['richness']! as num).toDouble(),
        ),
    ],
    ownerId: j['ownerId'] as String?,
    stock: _bigMap(j['stock']),
    buildings: _list(j['buildings'], BuildingState.fromJson),
  );

  /// Unique id.
  final String id;

  /// Display name.
  final String name;

  /// Id of the system it belongs to.
  final String systemId;

  /// Id of its [BodyTypeDef].
  final String typeId;

  /// Orbit index within its system.
  final int orbit;

  /// Its deposits.
  final List<DepositDef> deposits;

  /// Owning faction id, or null if unclaimed.
  String? ownerId;

  /// Resource id to units stored here.
  final Map<String, BigNum> stock;

  /// Buildings on this body.
  final List<BuildingState> buildings;

  /// Resource id to output lost to the storage cap in the last production
  /// step.
  ///
  /// Transient: reset at the start of every step, never serialized.
  final Map<String, BigNum> wastedThisStep = {};

  /// Serializes this body; [wastedThisStep] is left out.
  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'systemId': systemId,
    'typeId': typeId,
    'orbit': orbit,
    'deposits': [
      for (final d in deposits)
        {'resourceId': d.resourceId, 'richness': d.richness},
    ],
    'ownerId': ownerId,
    'stock': {for (final e in stock.entries) e.key: e.value.toJson()},
    'buildings': [for (final b in buildings) b.toJson()],
  };
}

/// A standing transport order between two bodies.
final class RouteState {
  /// Creates a route.
  RouteState({
    required this.id,
    required this.ownerId,
    required this.fromBodyId,
    required this.toBodyId,
    required this.resourceId,
    required this.ratePerSecond,
    required this.cargoShips,
  });

  /// Restores a route written by [toJson].
  factory RouteState.fromJson(Map<String, Object?> j) => RouteState(
    id: j['id']! as String,
    ownerId: j['ownerId']! as String,
    fromBodyId: j['fromBodyId']! as String,
    toBodyId: j['toBodyId']! as String,
    resourceId: j['resourceId']! as String,
    ratePerSecond: BigNum.fromJson(j['ratePerSecond']! as String),
    cargoShips: j['cargoShips']! as int,
  );

  /// Unique id.
  final String id;

  /// Owning faction id.
  final String ownerId;

  /// Source body id.
  final String fromBodyId;

  /// Destination body id.
  final String toBodyId;

  /// Resource moved.
  final String resourceId;

  /// Requested units per second.
  BigNum ratePerSecond;

  /// Cargo ships assigned.
  int cargoShips;

  /// Serializes this route.
  Map<String, Object?> toJson() => {
    'id': id,
    'ownerId': ownerId,
    'fromBodyId': fromBodyId,
    'toBodyId': toBodyId,
    'resourceId': resourceId,
    'ratePerSecond': ratePerSecond.toJson(),
    'cargoShips': cargoShips,
  };
}

/// Cargo in flight along a route.
final class Shipment {
  /// Creates a shipment.
  Shipment({
    required this.routeId,
    required this.fromBodyId,
    required this.toBodyId,
    required this.ownerId,
    required this.resourceId,
    required this.amount,
    required this.departAt,
    required this.arriveAt,
  });

  /// Restores a shipment written by [toJson].
  factory Shipment.fromJson(Map<String, Object?> j) => Shipment(
    routeId: j['routeId']! as String,
    fromBodyId: j['fromBodyId']! as String,
    toBodyId: j['toBodyId']! as String,
    ownerId: j['ownerId']! as String,
    resourceId: j['resourceId']! as String,
    amount: BigNum.fromJson(j['amount']! as String),
    departAt: (j['departAt']! as num).toDouble(),
    arriveAt: (j['arriveAt']! as num).toDouble(),
  );

  /// Route that sent it.
  final String routeId;

  /// Source body id, where the goods return if the destination is lost.
  final String fromBodyId;

  /// Destination body id.
  final String toBodyId;

  /// Faction that sent it; it outlives the route's removal.
  final String ownerId;

  /// Resource carried.
  final String resourceId;

  /// Units carried; grows while later sends merge into it (see
  /// `stepLogistics`).
  BigNum amount;

  /// Game time in seconds at which it left; later sends within
  /// `shipmentMergeSeconds` of this join it.
  final double departAt;

  /// Game time in seconds at which it arrives.
  final double arriveAt;

  /// Serializes this shipment.
  Map<String, Object?> toJson() => {
    'routeId': routeId,
    'fromBodyId': fromBodyId,
    'toBodyId': toBodyId,
    'ownerId': ownerId,
    'resourceId': resourceId,
    'amount': amount.toJson(),
    'departAt': departAt,
    'arriveAt': arriveAt,
  };
}

/// Market saturation per resource.
final class MarketState {
  /// Creates a market; a missing resource is at full saturation.
  MarketState({Map<String, double>? saturation})
    : saturation = saturation ?? {};

  /// Restores a market written by [toJson].
  factory MarketState.fromJson(Map<String, Object?> j) => MarketState(
    saturation: {
      for (final e in _asMap(j['saturation']).entries)
        e.key: (e.value! as num).toDouble(),
    },
  );

  /// Resource id to saturation in `[floor, 1]`; absent means 1.
  final Map<String, double> saturation;

  /// Serializes this market.
  Map<String, Object?> toJson() => {'saturation': saturation};
}

/// The whole mutable game world.
final class GameState {
  /// Creates a game state.
  GameState({
    this.saveVersion = currentSaveVersion,
    this.time = 0,
    required this.rngState,
    required this.factions,
    required this.bodies,
    List<RouteState>? routes,
    List<Shipment>? shipments,
    MarketState? market,
    this.nextId = 1,
  }) : routes = routes ?? [],
       shipments = shipments ?? [],
       market = market ?? MarketState();

  /// Restores a state written by [toJson].
  factory GameState.fromJson(Map<String, Object?> j) => GameState(
    saveVersion: j['saveVersion']! as int,
    time: (j['time']! as num).toDouble(),
    rngState: j['rngState']! as int,
    factions: _list(j['factions'], FactionState.fromJson),
    bodies: _list(j['bodies'], BodyState.fromJson),
    routes: _list(j['routes'], RouteState.fromJson),
    shipments: _list(j['shipments'], Shipment.fromJson),
    market: MarketState.fromJson(_asMap(j['market'])),
    nextId: j['nextId']! as int,
  );

  /// The save format version this code writes.
  static const int currentSaveVersion = 1;

  /// Version of the format this state was loaded from or created in.
  int saveVersion;

  /// Game seconds elapsed.
  double time;

  /// State of the game's [Rng].
  int rngState;

  /// Factions in content order.
  final List<FactionState> factions;

  /// Bodies in content order.
  final List<BodyState> bodies;

  /// Transport routes.
  final List<RouteState> routes;

  /// Cargo in flight.
  final List<Shipment> shipments;

  /// Market saturation.
  final MarketState market;

  /// Counter behind [newId].
  int nextId;

  /// Returns a fresh unique id such as `b7`.
  String newId(String prefix) => '$prefix${nextId++}';

  /// Returns the faction with [id]; throws if there is none.
  FactionState faction(String id) => factions.firstWhere((f) => f.id == id);

  /// Returns the body with [id]; throws if there is none.
  BodyState body(String id) => bodies.firstWhere((b) => b.id == id);

  /// Serializes the whole state.
  Map<String, Object?> toJson() => {
    'saveVersion': saveVersion,
    'time': time,
    'rngState': rngState,
    'factions': [for (final f in factions) f.toJson()],
    'bodies': [for (final b in bodies) b.toJson()],
    'routes': [for (final r in routes) r.toJson()],
    'shipments': [for (final s in shipments) s.toJson()],
    'market': market.toJson(),
    'nextId': nextId,
  };
}

/// Builds the starting world from [content], seeding the game [Rng] with
/// [seed].
GameState newGameState(Content content, int seed) {
  final state = GameState(
    rngState: Rng(seed).state,
    factions: [],
    bodies: [
      for (final sys in content.galaxy.systems)
        for (final b in sys.bodies)
          BodyState(
            id: b.id,
            name: b.name,
            systemId: sys.id,
            typeId: b.typeId,
            orbit: b.orbit,
            deposits: List.of(b.deposits),
          ),
    ],
  );
  for (final f in content.galaxy.factions) {
    state.factions.add(
      FactionState(
        id: f.id,
        name: f.name,
        isPlayer: f.isPlayer,
        credits: f.credits,
        baseCrew: f.baseCrew,
      ),
    );
    final home = state.body(f.homeBodyId)..ownerId = f.id;
    home.stock.addAll(f.stock);
    for (final sb in f.buildings) {
      home.buildings.add(
        BuildingState(
          id: state.newId('b'),
          defId: sb.defId,
          depositResourceId: sb.depositResourceId,
          crew: sb.crew,
        ),
      );
    }
  }
  return state;
}
