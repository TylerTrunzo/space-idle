import 'package:flutter_test/flutter_test.dart';
import 'package:game_core/game_core.dart';
import 'package:space_idle/game/content_source.dart';
import 'package:space_idle/view/messages.dart';

final Content content = loadEmbeddedContent();
const _p = 'player';

/// A new game with plenty of everything on Kora, so every command can
/// succeed.
GameState _richGame() {
  final s = GameEngine(content).newGame(1);
  s.faction(_p).credits = BigNum.parse('1e15');
  for (final id in content.resources.keys) {
    s.body('kora').stock[id] = BigNum.from(1e6);
  }
  return s;
}

void main() {
  group('bottleneckText', () {
    late GameState s;
    setUp(() => s = _richGame());

    String text(Bottleneck n) => bottleneckText(s, content, _p, n);

    test('input, one building and a group', () {
      expect(
        text(
          const Bottleneck(
            kind: BottleneckKind.input,
            bodyId: 'kora',
            buildingId: 'b3',
            resourceId: 'iron_ore',
            runFraction: 0.5,
            buildingIds: ['b3'],
          ),
        ),
        'Smelter on Kora is running at 50%: not enough Iron Ore',
      );
      expect(
        text(
          const Bottleneck(
            kind: BottleneckKind.input,
            bodyId: 'kora',
            buildingId: null,
            resourceId: 'iron_ore',
            runFraction: 0.996,
            count: 2,
            buildingIds: ['b1', 'b2'],
          ),
        ),
        '2 Mines on Kora are running as low as 99%: not enough Iron Ore',
      );
    });

    test('noCrew and understaffed, one building and a group', () {
      s.body('kora').buildings.firstWhere((b) => b.id == 'b3').crew = 0;
      expect(
        text(
          const Bottleneck(
            kind: BottleneckKind.noCrew,
            bodyId: 'kora',
            buildingId: 'b3',
            resourceId: null,
            runFraction: 0,
            buildingIds: ['b3'],
          ),
        ),
        'Smelter on Kora has no crew',
      );
      expect(
        text(
          const Bottleneck(
            kind: BottleneckKind.noCrew,
            bodyId: 'kora',
            buildingId: null,
            resourceId: null,
            runFraction: 0,
            count: 2,
            buildingIds: ['b1', 'b3'],
          ),
        ),
        '2 buildings on Kora have no crew',
      );
      // Circuit Fabs have 2 base slots; give one a single crew.
      final fab = BuildingState(
        id: 'b_fab',
        defId: 'circuit_fab',
        crew: 1,
        levels: {for (final t in UpgradeTrack.values) t: 0},
      );
      s.body('kora').buildings.add(fab);
      expect(
        text(
          const Bottleneck(
            kind: BottleneckKind.understaffed,
            bodyId: 'kora',
            buildingId: 'b_fab',
            resourceId: null,
            runFraction: 0.5,
            buildingIds: ['b_fab'],
          ),
        ),
        'Circuit Fab on Kora is understaffed: 1 of 2 crew',
      );
      expect(
        text(
          const Bottleneck(
            kind: BottleneckKind.understaffed,
            bodyId: 'kora',
            buildingId: null,
            resourceId: null,
            runFraction: 0.5,
            count: 3,
            buildingIds: ['b_fab', 'b_fab', 'b_fab'],
          ),
        ),
        '3 Circuit Fabs on Kora are understaffed',
      );
    });

    test('crewShortage names the housing figures', () {
      final t = crewTotals(s, content, _p);
      expect(
        text(
          const Bottleneck(
            kind: BottleneckKind.crewShortage,
            bodyId: null,
            buildingId: null,
            resourceId: null,
            runFraction: 0.8,
          ),
        ),
        'Your empire is short on crew: habitats and base crew support '
        '${t.supported} of ${t.assigned} assigned',
      );
    });

    test('storageFull, now and while away', () {
      const full = Bottleneck(
        kind: BottleneckKind.storageFull,
        bodyId: 'kora',
        buildingId: null,
        resourceId: 'steel',
        runFraction: 0,
      );
      expect(
        text(full),
        'Kora storage is full of Steel: output is being wasted',
      );
      expect(
        text(
          const Bottleneck(
            kind: BottleneckKind.storageFull,
            bodyId: 'kora',
            buildingId: null,
            resourceId: 'steel',
            runFraction: 0,
            fromAbsence: true,
          ),
        ),
        'Kora storage filled up with Steel while you were away: output '
        'was wasted',
      );
    });

    test('noSales', () {
      expect(
        text(
          const Bottleneck(
            kind: BottleneckKind.noSales,
            bodyId: null,
            buildingId: null,
            resourceId: null,
            runFraction: 0,
          ),
        ),
        'Nothing is being sold: turn on auto-sell or sell goods',
      );
    });

    test('megaprojectDiversion and keepBlocksDelivery', () {
      expect(
        text(
          Bottleneck(
            kind: BottleneckKind.megaprojectDiversion,
            bodyId: null,
            buildingId: null,
            resourceId: 'hull_plate',
            runFraction: 0.6,
            megaprojectId: 'orbital_station',
            shareOfSales: 0.4,
            lostCreditsPerHour: BigNum.from(1500),
          ),
        ),
        'Orbital Station takes 40% of the Hull Plate that would sell: '
        '1.5K credits an hour not earned',
      );
      s
          .faction(_p)
          .autoSell
          .add(
            AutoSellRule(
              bodyId: 'kora',
              resourceId: 'hull_plate',
              keepAtLeast: BigNum.from(500),
            ),
          );
      expect(
        text(
          Bottleneck(
            kind: BottleneckKind.keepBlocksDelivery,
            bodyId: 'kora',
            buildingId: null,
            resourceId: 'hull_plate',
            runFraction: 0,
            megaprojectId: 'orbital_station',
            heldByKeep: BigNum.from(120),
          ),
        ),
        'Orbital Station still needs Hull Plate, but Kora keeps 120 of it '
        'back for its auto-sell keepAtLeast 500',
      );
    });

    test('contractBlocksDelivery names the contract and what it holds', () {
      Bottleneck held(num n) => Bottleneck(
        kind: BottleneckKind.contractBlocksDelivery,
        bodyId: null,
        buildingId: null,
        resourceId: 'survey_drone',
        runFraction: 0,
        megaprojectId: 'orbital_station',
        contractId: 'c205',
        heldForContract: BigNum.from(n),
      );
      expect(
        text(held(104000)),
        'Contract #c205 holds 104K Survey Drones the Orbital Station needs',
      );
      expect(
        text(held(1)),
        'Contract #c205 holds 1 Survey Drone the Orbital Station needs',
      );
    });

    group('routeLimited names what holds the route back', () {
      late String routeId;
      setUp(() {
        s.body('brine').ownerId = _p;
        final r = GameEngine(content).apply(
          s,
          CreateRouteCommand(
            _p,
            'kora',
            'brine',
            'iron_ore',
            BigNum.from(1),
            1,
          ),
        );
        routeId = (r as CommandOk).createdId!;
        s
            .body('brine')
            .buildings
            .add(
              BuildingState(
                id: 'b_sm',
                defId: 'smelter',
                crew: 1,
                levels: {for (final t in UpgradeTrack.values) t: 0},
              ),
            );
      });

      Bottleneck limited(RouteLimit binding, {int count = 1}) => Bottleneck(
        kind: BottleneckKind.routeLimited,
        bodyId: 'brine',
        buildingId: count == 1 ? 'b_sm' : null,
        resourceId: 'iron_ore',
        runFraction: 0.39,
        count: count,
        buildingIds: List.filled(count, 'b_sm'),
        routeId: routeId,
        binding: binding,
        routePerSec: 10,
      );

      test('each binding', () {
        const into =
            'Smelter on Brine is running at 39%: Iron Ore into Brine '
            'is limited by';
        expect(
          text(limited(RouteLimit.rate)),
          "$into the route's rate (10/s); raise its rate",
        );
        expect(
          text(limited(RouteLimit.ships)),
          "$into the route's 1 Cargo Ship (10/s); assign more ships",
        );
        expect(
          text(limited(RouteLimit.destinationRoom)),
          startsWith("$into Brine's storage (10/s); a "),
        );
        expect(
          text(limited(RouteLimit.stopLevel)),
          "$into the route's stop level (10/s); raise its stop level",
        );
        expect(
          text(limited(RouteLimit.sourceStock)),
          '$into what Kora has to send (10/s)',
        );
      });

      test('a group', () {
        expect(
          text(limited(RouteLimit.rate, count: 2)),
          startsWith('2 Smelters on Brine are running as low as 39%: '),
        );
      });
    });

    test('every kind has its own text, none empty', () {
      for (final kind in BottleneckKind.values) {
        final n = Bottleneck(
          kind: kind,
          bodyId: 'kora',
          buildingId: 'b3',
          resourceId: 'iron_ore',
          runFraction: 0.5,
          buildingIds: const ['b3'],
          megaprojectId: 'orbital_station',
          shareOfSales: 0.5,
          heldByKeep: BigNum.from(1),
          lostCreditsPerHour: BigNum.from(1),
          routeId: 'r_none',
          binding: RouteLimit.rate,
          routePerSec: 1,
          contractId: 'c1',
          heldForContract: BigNum.from(1),
        );
        expect(text(n), isNotEmpty, reason: kind.name);
      }
    });
  });

  group('outcomeMessage', () {
    late GameState s;
    late GameEngine e;
    late Set<Type> seen;

    setUp(() {
      s = _richGame();
      e = GameEngine(content);
      seen = {};
    });

    /// Applies [cmd], which must succeed, and returns its message.
    String run(Command cmd) {
      final r = e.apply(s, cmd);
      expect(r, isA<CommandOk>(), reason: r is CommandFailed ? r.message : '');
      final o = (r as CommandOk).outcome!;
      seen.add(o.runtimeType);
      final text = outcomeMessage(s, content, cmd, o);
      expect(text, isNotEmpty);
      return text;
    }

    test('building commands', () => _buildingSteps(s, run));
    test('logistics and sales', () => _logisticsSteps(s, run));
    test('projects', () => _projectSteps(s, run));
    test('megaprojects', () => _megaprojectSteps(s, run));
    test('contracts', () => _contractSteps(s, run));

    test('every outcome subtype is covered', () {
      // Claims first: owning Brine (logistics) would make it a second claim.
      _projectSteps(s, run);
      _buildingSteps(s, run);
      _logisticsSteps(s, run);
      _megaprojectSteps(s, run);
      _contractSteps(s, run);
      expect(seen, {
        Built,
        Demolished,
        CrewAssigned,
        Upgraded,
        RouteCreated,
        RouteUpdated,
        RouteRemoved,
        ShipsSent,
        Sold,
        AutoSellSet,
        ProjectStarted,
        MegaprojectDelivered,
        MegaprojectAutoSet,
        AutoPayReserveSet,
        ContractProgress,
        ContractDiscarded,
        UpgradesBought,
      });
    });
  });
}

/// Building commands, each checked as it runs.
void _buildingSteps(GameState s, String Function(Command) run) {
  final built = run(const BuildCommand(_p, 'kora', 'smelter'));
  expect(built, startsWith('Built Smelter on Kora with 1 of 1 crew'));
  expect(built, contains('Iron Ore'));
  final id = s.body('kora').buildings.last.id;
  expect(
    run(DemolishCommand(_p, id)),
    startsWith('Demolished Smelter on Kora; got back '),
  );
  expect(
    run(const AssignCrewCommand(_p, 'b3', 0)),
    'Smelter on Kora now has 0 of 1 crew',
  );
  expect(
    run(const UpgradeCommand(_p, 'b3', UpgradeTrack.speed)),
    startsWith('Smelter on Kora is at Speed level 1, for '),
  );
  expect(
    run(const UpgradeCommand(_p, 'b3', UpgradeTrack.capacity)),
    allOf(
      startsWith('Smelter on Kora is at capacity level 1; '),
      endsWith(' crew)'),
    ),
  );
  // Buy max: levels bought, what they cost, and why it stopped.
  final bought = run(BuyUpgradesCommand(_p, BigNum.from(1000)));
  expect(
    bought,
    matches(RegExp(r'^Bought \d+ upgrade levels? on \d+ buildings? for ')),
  );
  expect(bought, contains('more than the budget allows'));
  expect(
    run(BuyUpgradesCommand(_p, const BigNum.zero())),
    startsWith('Bought no upgrades: the cheapest costs '),
  );
  expect(
    run(BuyUpgradesCommand(_p, BigNum.from(1e9), maxPurchases: 2)),
    endsWith('stopped at 2 levels, the most this command buys'),
  );
}

/// Logistics and sales, each checked as it runs.
void _logisticsSteps(GameState s, String Function(Command) run) {
  s.body('brine').ownerId = _p;
  final created = run(
    CreateRouteCommand(_p, 'kora', 'brine', 'iron_ore', BigNum.from(1), 1),
  );
  expect(
    created,
    'Created a route: Iron Ore from Kora to Brine at 1/s with 1 Cargo Ship',
  );
  final routeId = s.routes.single.id;
  expect(
    run(UpdateRouteCommand(_p, routeId, ratePerSecond: BigNum.from(2))),
    'Updated the route: Iron Ore from Kora to Brine at 2/s with 1 Cargo '
    'Ship',
  );
  expect(run(RemoveRouteCommand(_p, routeId)), startsWith('Closed a route'));
  expect(
    run(const MoveShipsCommand(_p, 'kora', 'brine', 2)),
    startsWith('Sent 2 Cargo Ships from Kora to Brine; they land in '),
  );
  expect(
    run(SellCommand(_p, 'kora', 'iron_ore', BigNum.from(10))),
    startsWith('Sold 10 Iron Ore from Kora for '),
  );
  expect(
    run(SetAutoSellCommand(_p, 'kora', 'steel', BigNum.from(500))),
    'Kora now auto-sells Steel above 500',
  );
  expect(
    run(const SetAutoSellCommand(_p, 'kora', 'steel', null)),
    'Kora no longer auto-sells Steel',
  );
}

/// Projects, each checked as it runs.
void _projectSteps(GameState s, String Function(Command) run) {
  expect(
    run(const ClaimBodyCommand(_p, 'hollow_reach', 'kora')),
    'Started claiming Hollow Reach for 5K credits (no kits needed); '
    'done in 30m',
  );
  expect(
    run(const SurveyCommand(_p, null, 'kora')),
    startsWith('Started a survey for 20K credits and 3 Survey Drone'),
  );
  expect(
    run(const ExpandSlotsCommand(_p, 'kora')),
    startsWith('Started an extra build slot on Kora for '),
  );
}

/// Megaprojects, each checked as it runs.
void _megaprojectSteps(GameState s, String Function(Command) run) {
  expect(
    run(const StartMegaprojectStageCommand(_p, 'orbital_station', 'kora')),
    startsWith('Started Orbital Station level 1 on Kora for '),
  );
  expect(
    run(
      DeliverToMegaprojectCommand(_p, 'orbital_station', 'kora', {
        'hull_plate': BigNum.from(10),
      }),
    ),
    startsWith(
      'Delivered 10 Hull Plate to Orbital Station level 2; it '
      'still needs ',
    ),
  );
  expect(
    run(
      const SetMegaprojectAutoCommand(
        _p,
        'orbital_station',
        goods: GoodsFeedMode.always,
        credits: true,
      ),
    ),
    startsWith('Orbital Station now takes goods from every body'),
  );
  expect(
    run(const SetMegaprojectAutoCommand(_p, 'orbital_station')),
    'Orbital Station is fed by hand only',
  );
  expect(
    run(SetAutoPayReserveCommand(_p, BigNum.from(1000))),
    startsWith('Auto-pay now keeps 1K credits'),
  );
}

/// Contracts, each checked as it runs.
void _contractSteps(GameState s, String Function(Command) run) {
  // A new game's board may be empty; post one Veyra Exchange order.
  final k = ContractState(
    id: 'c_one',
    templateId: 'veyra_bulk',
    resourceId: 'copper_ore',
    quantity: BigNum.from(1000),
    rewardCredits: BigNum.from(7500),
    postedAt: s.time,
  );
  s.faction(_p).contracts.add(k);
  final res = content.resources[k.resourceId]!.name;
  expect(
    run(DeliverContractCommand(_p, k.id, 'kora', BigNum.from(10))),
    startsWith(
      'Delivered 10 $res from Kora to the Veyra Exchange '
      'contract (',
    ),
  );
  expect(
    run(DeliverContractCommand(_p, k.id, 'kora', k.remaining)),
    contains('and completed the contract; paid '),
  );
  s
      .faction(_p)
      .contracts
      .add(
        ContractState(
          id: 'c_test',
          templateId: k.templateId,
          resourceId: 'steel',
          quantity: BigNum.from(100),
          rewardCredits: BigNum.from(900),
          postedAt: s.time,
        ),
      );
  expect(
    run(const DiscardContractCommand(_p, 'c_test')),
    startsWith('Discarded the contract for 100 Steel; '),
  );
}
