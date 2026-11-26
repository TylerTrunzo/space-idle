import 'dart:convert';
import 'dart:math' as math;

import 'package:game_core/game_core.dart';
import 'package:test/test.dart';

import '../state/helpers.dart';

void main() {
  final content = shippedContent();
  BigNum n(num v) => BigNum.from(v);

  // The crew counts below assume 10 base crew, whatever the shipped
  // content currently starts with.
  GameState fresh() =>
      newGameState(content, 1)..faction('player').baseCrew = 10;

  /// Applies [cmd] under [using] (default the shipped content), expects
  /// success, and returns the created id.
  String? expectOk(GameState s, Command cmd, {Content? using}) {
    final r = applyCommand(s, using ?? content, cmd);
    expect(r, isA<CommandOk>(), reason: r is CommandFailed ? r.message : '');
    return (r as CommandOk).createdId;
  }

  /// Applies [cmd] under [using] (default the shipped content), expects
  /// [error], and checks the state did not change.
  ///
  /// Returns the failure's message.
  String expectFails(
    GameState s,
    Command cmd,
    CommandError error, {
    Content? using,
  }) {
    final before = jsonEncode(s.toJson());
    final r = applyCommand(s, using ?? content, cmd);
    expect(r, isA<CommandFailed>().having((f) => f.error, 'error', error));
    expect(jsonEncode(s.toJson()), before);
    return (r as CommandFailed).message;
  }

  BuildingState building(GameState s, String id) =>
      s.bodies.expand((b) => b.buildings).firstWhere((b) => b.id == id);

  /// Kora plus Hollow Reach owned by the player, with ships and credits.
  GameState twoBodies() {
    final s = fresh();
    s.body('hollow_reach').ownerId = 'player';
    s.body('kora').stock['cargo_ship'] = n(3);
    return s;
  }

  /// A rival owning Brine, with one building there.
  GameState withRival() {
    final s = fresh();
    s.faction('player').credits = n(1e6);
    s.factions.add(
      FactionState(
        id: 'rival',
        name: 'Rival',
        isPlayer: false,
        credits: n(1e6),
        baseCrew: 10,
      ),
    );
    s.body('brine')
      ..ownerId = 'rival'
      ..stock['water_ice'] = n(50)
      ..buildings.add(
        BuildingState(
          id: 'rb1',
          defId: 'ice_drill',
          depositResourceId: 'water_ice',
          crew: 0,
        ),
      );
    return s;
  }

  group('build', () {
    test('happy path pays credits and adds an uncrewed building', () {
      final s = fresh();
      final id = expectOk(
        s,
        BuildCommand('player', 'kora', 'mine', depositResourceId: 'silicon'),
      );
      expect(s.faction('player').credits, n(150));
      final b = s.body('kora').buildings.last;
      expect(b.id, id);
      expect(b.defId, 'mine');
      expect(b.depositResourceId, 'silicon');
      expect(b.crew, 0);
    });

    test('resource costs are paid from the body stock', () {
      final s = fresh();
      s.faction('player').credits = n(2000);
      s.body('kora').stock['habitat_module'] = n(1);
      expectOk(s, BuildCommand('player', 'kora', 'habitat'));
      expect(s.faction('player').credits, n(500));
      expect(s.body('kora').stock['habitat_module'], n(0));
    });

    test('fails without free slot', () {
      final s = fresh();
      s.faction('player').credits = n(1e6);
      final kora = s.body('kora');
      while (kora.buildings.length < 12) {
        kora.buildings.add(
          BuildingState(id: s.newId('b'), defId: 'smelter', crew: 0),
        );
      }
      expectFails(
        s,
        BuildCommand('player', 'kora', 'smelter'),
        CommandError.noBuildSlot,
      );
    });

    test('extractor needs matching deposit', () {
      final s = fresh();
      for (final cmd in [
        BuildCommand('player', 'kora', 'mine'),
        BuildCommand('player', 'kora', 'mine', depositResourceId: 'nickel'),
        BuildCommand(
          'player',
          'kora',
          'ice_drill',
          depositResourceId: 'iron_ore',
        ),
      ]) {
        expectFails(s, cmd, CommandError.depositMissing);
      }
    });

    test('cannot afford', () {
      final s = fresh();
      expectFails(
        s,
        BuildCommand('player', 'kora', 'circuit_fab'),
        CommandError.cannotAfford,
      );
      s.faction('player').credits = n(2000);
      expectFails(
        s,
        BuildCommand('player', 'kora', 'habitat'),
        CommandError.cannotAfford,
      );
    });

    test('unknown ids', () {
      final s = fresh();
      expectFails(
        s,
        BuildCommand('nobody', 'kora', 'smelter'),
        CommandError.unknownFaction,
      );
      expectFails(
        s,
        BuildCommand('player', 'nowhere', 'smelter'),
        CommandError.unknownBody,
      );
      expectFails(
        s,
        BuildCommand('player', 'kora', 'nothing'),
        CommandError.unknownDef,
      );
    });
  });

  group('expandSlots', () {
    test('adds a build slot to the body for growing credits', () {
      final s = fresh()..faction('player').credits = n(1e9);
      final kora = s.body('kora');
      final r = content.rules;
      expect(buildSlots(content, kora), 12);
      expect(slotCost(content, kora), {'credits': r.slotBaseCredits});
      expectOk(s, ExpandSlotsCommand('player', 'kora'));
      expect(kora.extraSlots, 1);
      expect(buildSlots(content, kora), 13);
      expect(s.faction('player').credits, n(1e9) - r.slotBaseCredits);
      expect(slotCost(content, kora), {
        'credits': r.slotBaseCredits * BigNum.from(r.slotGrowth),
      });
      expectOk(s, ExpandSlotsCommand('player', 'kora'));
      expect(buildSlots(content, kora), 14);
      // Other bodies keep their own count.
      expect(s.body('brine').extraSlots, 0);
    });

    test('the new slot takes a building', () {
      final s = fresh()..faction('player').credits = n(1e9);
      final kora = s.body('kora');
      while (kora.buildings.length < 12) {
        expectOk(s, BuildCommand('player', 'kora', 'smelter'));
      }
      expectFails(
        s,
        BuildCommand('player', 'kora', 'smelter'),
        CommandError.noBuildSlot,
      );
      expectOk(s, ExpandSlotsCommand('player', 'kora'));
      expectOk(s, BuildCommand('player', 'kora', 'smelter'));
    });

    test('validation', () {
      final s = fresh()..faction('player').credits = n(10);
      expectFails(
        s,
        ExpandSlotsCommand('player', 'nowhere'),
        CommandError.unknownBody,
      );
      expectFails(
        s,
        ExpandSlotsCommand('player', 'brine'),
        CommandError.notOwner,
      );
      expect(
        expectFails(
          s,
          ExpandSlotsCommand('player', 'kora'),
          CommandError.cannotAfford,
        ),
        startsWith('Needs '),
      );
    });
  });

  test('demolish refunds half the credits and frees crew', () {
    final s = fresh();
    final smelter = s.body('kora').buildings.last;
    expect(availableCrew(s, content, 'player'), 7);
    expectOk(s, DemolishCommand('player', smelter.id));
    expect(s.faction('player').credits, n(325));
    expect(
      s.body('kora').buildings.map((b) => b.id),
      isNot(contains(smelter.id)),
    );
    expect(availableCrew(s, content, 'player'), 8);
    expectFails(
      s,
      DemolishCommand('player', smelter.id),
      CommandError.unknownBuilding,
    );
  });

  group('assignCrew', () {
    test('happy path sets the absolute count', () {
      final s = fresh();
      final mine = s.body('kora').buildings.first;
      expectOk(s, AssignCrewCommand('player', mine.id, 0));
      expect(mine.crew, 0);
      expect(availableCrew(s, content, 'player'), 8);
      mine.levels[UpgradeTrack.capacity] = 1;
      expectOk(s, AssignCrewCommand('player', mine.id, 2));
      expect(mine.crew, 2);
      expect(availableCrew(s, content, 'player'), 6);
    });

    test('crew over slots', () {
      final s = fresh();
      final mine = s.body('kora').buildings.first;
      expectFails(
        s,
        AssignCrewCommand('player', mine.id, 2),
        CommandError.crewSlotsExceeded,
      );
      s.faction('player').credits = n(1e6);
      s.body('kora').stock['steel'] = n(50);
      final depot = expectOk(s, BuildCommand('player', 'kora', 'depot'))!;
      building(s, depot).levels[UpgradeTrack.capacity] = 3;
      expectFails(
        s,
        AssignCrewCommand('player', depot, 1),
        CommandError.crewSlotsExceeded,
      );
    });

    test('crew over pool', () {
      final s = fresh();
      s.faction('player').baseCrew = 3;
      final mine = s.body('kora').buildings.first;
      mine.levels[UpgradeTrack.capacity] = 1;
      expectFails(
        s,
        AssignCrewCommand('player', mine.id, 2),
        CommandError.crewUnavailable,
      );
    });

    test('negative crew is invalid', () {
      final s = fresh();
      final mine = s.body('kora').buildings.first;
      expectFails(
        s,
        AssignCrewCommand('player', mine.id, -1),
        CommandError.invalidAmount,
      );
    });

    test('habitats add housing scaled by their run fraction', () {
      final s = fresh();
      s
          .body('kora')
          .buildings
          .add(
            BuildingState(
              id: 'h1',
              defId: 'habitat',
              crew: 1,
              lastRunFraction: 0.55,
            ),
          );
      // 10 base + floor(20 × 0.55) housing − 4 assigned.
      expect(availableCrew(s, content, 'player'), 17);
    });
  });

  group('upgrade', () {
    test('happy path pays growing credits and raises the level', () {
      final s = fresh();
      final mine = s.body('kora').buildings.first;
      expect(upgradeCost(content, mine, UpgradeTrack.speed), {
        'credits': n(50),
      });
      expectOk(s, UpgradeCommand('player', mine.id, UpgradeTrack.speed));
      expect(mine.levels[UpgradeTrack.speed], 1);
      expect(s.faction('player').credits, n(200));
      final curve = content.buildings['mine']!.upgrades[UpgradeTrack.speed]!;
      expect(upgradeCost(content, mine, UpgradeTrack.speed), {
        'credits': n(50 * curve.growth),
      });
    });

    test('track the building lacks is unknownDef', () {
      final s = fresh();
      final mine = s.body('kora').buildings.first;
      expectFails(
        s,
        UpgradeCommand('player', mine.id, UpgradeTrack.efficiency),
        CommandError.unknownDef,
      );
    });

    test('cannot afford', () {
      final s = fresh();
      s.faction('player').credits = n(10);
      final mine = s.body('kora').buildings.first;
      expectFails(
        s,
        UpgradeCommand('player', mine.id, UpgradeTrack.speed),
        CommandError.cannotAfford,
      );
    });

    test('unknown building', () {
      expectFails(
        fresh(),
        UpgradeCommand('player', 'b999', UpgradeTrack.speed),
        CommandError.unknownBuilding,
      );
    });
  });

  group('routes', () {
    CreateRouteCommand route({
      String from = 'kora',
      String to = 'hollow_reach',
      String resource = 'iron_ore',
      num rate = 2,
      int ships = 2,
    }) => CreateRouteCommand('player', from, to, resource, n(rate), ships);

    test('create consumes cargo ships from the from-body', () {
      final s = twoBodies();
      final id = expectOk(s, route());
      final r = s.routes.single;
      expect(r.id, id);
      expect(r.ownerId, 'player');
      expect(r.fromBodyId, 'kora');
      expect(r.toBodyId, 'hollow_reach');
      expect(r.resourceId, 'iron_ore');
      expect(r.ratePerSecond, n(2));
      expect(r.cargoShips, 2);
      expect(s.body('kora').stock['cargo_ship'], n(1));
    });

    test('create validation', () {
      final s = twoBodies();
      expectFails(s, route(to: 'kora'), CommandError.routeInvalid);
      expectFails(s, route(to: 'brine'), CommandError.notOwner);
      expectFails(s, route(ships: 0), CommandError.invalidAmount);
      expectFails(s, route(rate: 0), CommandError.invalidAmount);
      expectFails(s, route(ships: 4), CommandError.cannotAfford);
      expectFails(s, route(to: 'nowhere'), CommandError.unknownBody);
      expectFails(s, route(resource: 'nothing'), CommandError.unknownDef);
      final i = s.bodies.indexWhere((b) => b.id == 'hollow_reach');
      final hr = s.bodies[i];
      s.bodies[i] = BodyState(
        id: hr.id,
        name: hr.name,
        systemId: 'elsewhere',
        typeId: hr.typeId,
        orbit: hr.orbit,
        deposits: hr.deposits,
        ownerId: hr.ownerId,
      );
      expectFails(s, route(), CommandError.routeInvalid);
    });

    test('remove returns ships to the from-body', () {
      final s = twoBodies();
      final id = expectOk(s, route())!;
      expectOk(s, RemoveRouteCommand('player', id));
      expect(s.routes, isEmpty);
      expect(s.body('kora').stock['cargo_ship'], n(3));
      expectFails(
        s,
        RemoveRouteCommand('player', id),
        CommandError.routeInvalid,
      );
    });
  });

  group('paying never leaves float residue below zero', () {
    // 1 − 2^-52: equal to 1 at BigNum precision, so it affords one unit,
    // but subtracting 1 from it leaves −2.2e-16.
    final almostOne = BigNum.from(1 - 2.220446049250313e-16);

    test('a route takes its last cargo ship to exactly zero', () {
      final s = twoBodies();
      s.body('kora').stock['cargo_ship'] = almostOne;
      expectOk(
        s,
        CreateRouteCommand(
          'player',
          'kora',
          'hollow_reach',
          'iron_ore',
          n(1),
          1,
        ),
      );
      expect(s.body('kora').stock['cargo_ship'], const BigNum.zero());
      expect(s.body('kora').stock['cargo_ship']!.isNegative, isFalse);
    });

    test('a claim takes its last outpost kit to exactly zero', () {
      final s = fresh()..faction('player').credits = n(1e9);
      s.body('cinder').ownerId = 'player';
      s.body('kora').stock['outpost_kit'] = BigNum.from(2 - 4.4e-16);
      expectOk(s, const ClaimBodyCommand('player', 'brine', 'kora'));
      expect(s.body('kora').stock['outpost_kit']!.isNegative, isFalse);
    });

    test('a build spends its last credits to exactly zero', () {
      final s = fresh();
      final cost = content.buildings['mine']!.buildCost['credits']!;
      s.faction('player').credits = cost.mulDouble(1 - 2.220446049250313e-16);
      expect(s.faction('player').credits >= cost, isTrue);
      expectOk(
        s,
        const BuildCommand(
          'player',
          'kora',
          'mine',
          depositResourceId: 'silicon',
        ),
      );
      expect(s.faction('player').credits.isNegative, isFalse);
    });
  });

  group('sell', () {
    test('happy path pays credits and saturates the market', () {
      final s = fresh();
      expectOk(s, SellCommand('player', 'kora', 'iron_ore', n(10)));
      // Depth 10000: saturation falls to e^(−0.001), and the 10 units earn
      // 10000 × (1 − e^(−0.001)) at base price 1.
      expect(
        s.faction('player').credits.toDouble(),
        closeTo(250 + 10000 * (1 - math.exp(-0.001)), 1e-9),
      );
      expect(s.body('kora').stock['iron_ore'], n(30));
      expect(s.market.saturation['iron_ore'], closeTo(math.exp(-0.001), 1e-12));
    });

    test('selling what the body does not hold fails', () {
      final s = fresh();
      expect(
        expectFails(
          s,
          SellCommand('player', 'kora', 'steel', n(5)),
          CommandError.invalidAmount,
        ),
        'Kora has no Steel to sell',
      );
    });

    test('amount must be positive', () {
      final s = fresh();
      expectFails(
        s,
        SellCommand('player', 'kora', 'iron_ore', n(0)),
        CommandError.invalidAmount,
      );
    });
  });

  test('setAutoSell adds, updates and removes a rule', () {
    final s = fresh();
    final rules = s.faction('player').autoSell;
    expectOk(s, SetAutoSellCommand('player', 'kora', 'iron_ore', n(20)));
    expect(rules.single.bodyId, 'kora');
    expect(rules.single.resourceId, 'iron_ore');
    expect(rules.single.keepAtLeast, n(20));
    expectOk(s, SetAutoSellCommand('player', 'kora', 'steel', n(0)));
    expectOk(s, SetAutoSellCommand('player', 'kora', 'iron_ore', n(5)));
    expect(rules.map((r) => r.resourceId), ['iron_ore', 'steel']);
    expect(rules.first.keepAtLeast, n(5));
    expectOk(s, SetAutoSellCommand('player', 'kora', 'iron_ore', null));
    expect(rules.map((r) => r.resourceId), ['steel']);
    expectFails(
      s,
      SetAutoSellCommand('player', 'kora', 'iron_ore', n(-1)),
      CommandError.invalidAmount,
    );
  });

  group('claimBody', () {
    test('the first claim costs credits only; later ones a kit per body '
        'owned', () {
      // Shipped content with the claim numbers these tests assume.
      final c4 = withClaims(content, base: 5000, growth: 4);
      final s = fresh();
      s.faction('player').credits = n(1e6);
      expect(claimCost(s, c4, 'player'), {'credits': n(5000)});
      expectOk(s, ClaimBodyCommand('player', 'brine', 'kora'), using: c4);
      expect(s.body('brine').ownerId, 'player');
      expect(s.faction('player').credits, n(1e6 - 5000));

      // Two bodies owned: two kits.
      expect(claimCost(s, c4, 'player'), {
        'credits': n(20000),
        'outpost_kit': n(2),
      });
      s.body('kora').stock['outpost_kit'] = n(1);
      expectFails(
        s,
        ClaimBodyCommand('player', 'hollow_reach', 'kora'),
        CommandError.cannotAfford,
        using: c4,
      );
      s.body('kora').stock['outpost_kit'] = n(2);
      expectOk(
        s,
        ClaimBodyCommand('player', 'hollow_reach', 'kora'),
        using: c4,
      );
      expect(s.body('hollow_reach').ownerId, 'player');
      expect(s.faction('player').credits, n(1e6 - 25000));
      expect(s.body('kora').stock['outpost_kit'], n(0));
      expect(claimCost(s, c4, 'player'), {
        'credits': n(80000),
        'outpost_kit': n(3),
      });
    });

    test('validation', () {
      final s = fresh();
      s.faction('player').credits = n(1e6);
      expectFails(
        s,
        ClaimBodyCommand('player', 'kora', 'kora'),
        CommandError.alreadyOwned,
      );
      expectFails(
        s,
        ClaimBodyCommand('player', 'brine', 'cinder'),
        CommandError.notOwner,
      );
      expectFails(
        s,
        ClaimBodyCommand('player', 'nowhere', 'kora'),
        CommandError.unknownBody,
      );
    });
  });

  test("cannot act on another faction's body", () {
    final s = withRival();
    s.body('kora').stock['cargo_ship'] = n(1);
    final cases = <Command>[
      BuildCommand(
        'player',
        'brine',
        'ice_drill',
        depositResourceId: 'ammonia',
      ),
      UpgradeCommand('player', 'rb1', UpgradeTrack.speed),
      AssignCrewCommand('player', 'rb1', 1),
      DemolishCommand('player', 'rb1'),
      CreateRouteCommand('player', 'brine', 'kora', 'water_ice', n(1), 1),
      SellCommand('player', 'brine', 'water_ice', n(1)),
      SetAutoSellCommand('player', 'brine', 'water_ice', n(0)),
    ];
    for (final cmd in cases) {
      expectFails(s, cmd, CommandError.notOwner);
    }
    s.body('brine').stock['cargo_ship'] = n(1);
    s.body('cinder').ownerId = 'rival';
    final rivalRoute = expectOk(
      s,
      CreateRouteCommand('rival', 'brine', 'cinder', 'water_ice', n(1), 1),
    )!;
    expectFails(
      s,
      RemoveRouteCommand('player', rivalRoute),
      CommandError.notOwner,
    );
    expectFails(
      s,
      ClaimBodyCommand('player', 'brine', 'kora'),
      CommandError.alreadyOwned,
    );
  });

  test('command json round trip', () {
    final cmds = <Command>[
      BuildCommand('player', 'kora', 'mine', depositResourceId: 'silicon'),
      BuildCommand('player', 'kora', 'smelter'),
      DemolishCommand('player', 'b1'),
      AssignCrewCommand('player', 'b1', 3),
      UpgradeCommand('player', 'b1', UpgradeTrack.capacity),
      CreateRouteCommand('player', 'kora', 'brine', 'steel', n(2.5), 2),
      RemoveRouteCommand('player', 'r4'),
      SellCommand('player', 'kora', 'steel', BigNum.parse('1.5e20')),
      SetAutoSellCommand('player', 'kora', 'steel', n(100)),
      SetAutoSellCommand('player', 'kora', 'steel', null),
      ClaimBodyCommand('player', 'brine', 'kora'),
      ExpandSlotsCommand('player', 'kora'),
    ];
    for (final cmd in cmds) {
      final json = jsonDecode(jsonEncode(cmd.toJson())) as Map<String, Object?>;
      final back = Command.fromJson(json);
      expect(back.runtimeType, cmd.runtimeType);
      expect(back.factionId, 'player');
      expect(back.toJson(), cmd.toJson());
    }
    expect(BuildCommand('p', 'k', 'mine').toJson()['cmd'], 'build');
    expect(
      () => Command.fromJson({'cmd': 'teleport', 'factionId': 'p'}),
      throwsFormatException,
    );
    expect(
      () => Command.fromJson({'cmd': 'demolish', 'factionId': 'p'}),
      throwsFormatException,
    );
  });

  group('failure messages use display names and formatted numbers', () {
    test('short of credits', () {
      final s = fresh()..faction('player').credits = n(250);
      expect(
        expectFails(
          s,
          BuildCommand('player', 'kora', 'habitat'),
          CommandError.cannotAfford,
        ),
        'Needs 1.5K credits (you have 250)',
      );
    });

    test('short of a resource', () {
      final s = fresh()..faction('player').credits = n(1e6);
      expect(
        expectFails(
          s,
          BuildCommand('player', 'kora', 'habitat'),
          CommandError.cannotAfford,
        ),
        'Needs 1 Habitat Module on Kora (you have 0)',
      );
    });

    test('not the owner', () {
      final s = withRival();
      expect(
        expectFails(
          s,
          BuildCommand('player', 'brine', 'smelter'),
          CommandError.notOwner,
        ),
        "You don't own Brine",
      );
      expect(
        expectFails(
          s,
          const AssignCrewCommand('player', 'rb1', 1),
          CommandError.notOwner,
        ),
        "You don't own the Ice Drill on Brine",
      );
    });

    test('already owned', () {
      expect(
        expectFails(
          withRival(),
          const ClaimBodyCommand('player', 'brine', 'kora'),
          CommandError.alreadyOwned,
        ),
        'Brine is already owned by Rival',
      );
    });

    test('no deposit', () {
      expect(
        expectFails(
          fresh(),
          BuildCommand('player', 'kora', 'mine', depositResourceId: 'nickel'),
          CommandError.depositMissing,
        ),
        "Mine can't mine Nickel on Kora "
        '(Kora has Iron Ore, Copper Ore, Silicon)',
      );
      expect(
        expectFails(
          fresh(),
          BuildCommand('player', 'kora', 'mine'),
          CommandError.depositMissing,
        ),
        'Mine needs a deposit to mine (Kora has Iron Ore, Copper Ore, Silicon)',
      );
      // The body has the deposit, but this extractor cannot mine it.
      expect(
        expectFails(
          fresh(),
          BuildCommand(
            'player',
            'kora',
            'ice_drill',
            depositResourceId: 'iron_ore',
          ),
          CommandError.depositMissing,
        ),
        "Ice Drill can't mine Iron Ore on Kora "
        '(Kora has Iron Ore, Copper Ore, Silicon; '
        'Ice Drill mines Water Ice, Ammonia)',
      );
    });

    test('crew limits', () {
      final s = fresh();
      expect(
        expectFails(
          s,
          const AssignCrewCommand('player', 'b3', 5),
          CommandError.crewSlotsExceeded,
        ),
        'Smelter on Kora holds at most 1 crew',
      );
      s.faction('player').baseCrew = 3;
      final id = expectOk(
        s,
        BuildCommand('player', 'kora', 'mine', depositResourceId: 'silicon'),
      )!;
      expect(
        expectFails(
          s,
          AssignCrewCommand('player', id, 1),
          CommandError.crewUnavailable,
        ),
        'Needs 1 more crew (you have 0 free)',
      );
    });

    test('no such upgrade', () {
      expect(
        expectFails(
          fresh(),
          const UpgradeCommand('player', 'b1', UpgradeTrack.efficiency),
          CommandError.unknownDef,
        ),
        'Mine has no efficiency upgrade',
      );
    });
  });
}

/// [c] with its rules' claim base credits set to [base] and claim growth
/// to [growth].
Content withClaims(Content c, {required double base, required double growth}) {
  final r = c.rules;
  return Content(
    rules: RulesDef(
      speedPerLevel: r.speedPerLevel,
      speedMilestoneEvery: r.speedMilestoneEvery,
      speedMilestoneMult: r.speedMilestoneMult,
      efficiencyPerLevel: r.efficiencyPerLevel,
      efficiencyFloor: r.efficiencyFloor,
      capacityCrewPerLevel: r.capacityCrewPerLevel,
      capacityStoragePerLevel: r.capacityStoragePerLevel,
      baseStorageCap: r.baseStorageCap,
      offlineCapSeconds: r.offlineCapSeconds,
      marketFloor: r.marketFloor,
      marketRecoverySeconds: r.marketRecoverySeconds,
      claimBaseCredits: BigNum.from(base),
      claimGrowth: growth,
      slotBaseCredits: r.slotBaseCredits,
      slotGrowth: r.slotGrowth,
      outpostKitResource: r.outpostKitResource,
      shipCapacityPerSecond: r.shipCapacityPerSecond,
      cargoShipResource: r.cargoShipResource,
      baseTravelSeconds: r.baseTravelSeconds,
    ),
    resources: c.resources,
    buildings: c.buildings,
    bodyTypes: c.bodyTypes,
    galaxy: c.galaxy,
    milestones: c.milestones,
  );
}
