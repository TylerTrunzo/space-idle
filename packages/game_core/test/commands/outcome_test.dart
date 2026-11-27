import 'package:game_core/game_core.dart';
import 'package:test/test.dart';

import '../state/helpers.dart';

BigNum n(num v) => BigNum.from(v);

void main() {
  final content = shippedContent();
  final e = GameEngine(content);
  final station = content.megaprojects['orbital_station']!;

  /// A new game with a billion credits, Hollow Reach the player's too and
  /// cargo ships on Kora.
  GameState rich() {
    final s = e.newGame(1)..faction('player').credits = n(1e9);
    s.body('hollow_reach').ownerId = 'player';
    s.body('kora').stock['cargo_ship'] = n(5);
    return s;
  }

  /// Applies [cmd], expects success, and returns its outcome as a [T].
  T outcome<T extends CommandOutcome>(GameState s, Command cmd) {
    final r = e.apply(s, cmd);
    expect(r, isA<CommandOk>(), reason: r is CommandFailed ? r.message : '');
    final o = (r as CommandOk).outcome;
    expect(o, isA<T>());
    return o! as T;
  }

  test('a build names the building, its crew and its cost', () {
    final s = rich();
    final o = outcome<Built>(
      s,
      const BuildCommand('player', 'kora', 'smelter'),
    );
    final b = s.body('kora').buildings.last;
    expect(
      (o.bodyId, o.buildingId, o.defId, o.crew),
      ('kora', b.id, 'smelter', b.crew),
    );
    expect(o.spent, content.buildings['smelter']!.buildCost);
    expect(o.gained, isEmpty);
  });

  test('a demolish names the building and its refund', () {
    final s = rich();
    final b = s.body('kora').buildings.first;
    final o = outcome<Demolished>(s, DemolishCommand('player', b.id));
    expect((o.bodyId, o.buildingId, o.defId), ('kora', b.id, b.defId));
    final paid = content.buildings[b.defId]!.buildCost['credits'];
    expect(o.gained, {'credits': ?paid?.mulDouble(0.5)});
  });

  test('crew, upgrades and auto-sell say what they set', () {
    final s = rich();
    final b = s.body('kora').buildings.first;
    final crew = outcome<CrewAssigned>(s, AssignCrewCommand('player', b.id, 0));
    expect((crew.buildingId, crew.crew), (b.id, 0));
    expect(crew.previousCrew, greaterThan(0));
    final track = content.buildings[b.defId]!.upgrades.keys.first;
    final cost = upgradeCost(content, b, track);
    final up = outcome<Upgraded>(s, UpgradeCommand('player', b.id, track));
    expect(
      (up.bodyId, up.buildingId, up.track, up.level),
      ('kora', b.id, track, 1),
    );
    expect(up.spent, cost);
    final rule = outcome<AutoSellSet>(
      s,
      SetAutoSellCommand('player', 'kora', 'steel', n(5)),
    );
    expect(
      (rule.bodyId, rule.resourceId, rule.keepAtLeast),
      ('kora', 'steel', n(5)),
    );
  });

  test('a stop level above the destination storage cap is cut to the cap, '
      'and the outcome says so', () {
    final s = rich();
    final cap = storageCap(s, content, s.body('hollow_reach'));
    final made = outcome<RouteCreated>(
      s,
      CreateRouteCommand(
        'player',
        'kora',
        'hollow_reach',
        'steel',
        n(1),
        1,
        stopAtDestination: cap * n(4),
      ),
    );
    expect(made.stopClampedTo, cap);
    expect(s.routes.single.stopAtDestination, cap);
    final fits = outcome<RouteUpdated>(
      s,
      UpdateRouteCommand('player', made.routeId, stopAtDestination: n(50)),
    );
    expect(fits.stopClampedTo, isNull);
    expect(s.routes.single.stopAtDestination, n(50));
    final over = outcome<RouteUpdated>(
      s,
      UpdateRouteCommand('player', made.routeId, stopAtDestination: cap + n(1)),
    );
    expect(over.stopClampedTo, cap);
    expect(s.routes.single.stopAtDestination, cap);
    final plain = outcome<RouteCreated>(
      s,
      CreateRouteCommand('player', 'kora', 'hollow_reach', 'iron_ore', n(1), 1),
    );
    expect(plain.stopClampedTo, isNull);
  });

  test('routes and ship moves say which ships moved', () {
    final s = rich();
    final made = outcome<RouteCreated>(
      s,
      CreateRouteCommand('player', 'kora', 'hollow_reach', 'steel', n(1), 2),
    );
    expect(made.bodyId, 'kora');
    expect(made.spent, {'cargo_ship': n(2)});
    final more = outcome<RouteUpdated>(
      s,
      UpdateRouteCommand('player', made.routeId, cargoShips: 3),
    );
    expect(more.routeId, made.routeId);
    expect(more.spent, {'cargo_ship': n(1)});
    expect(more.gained, isEmpty);
    final fewer = outcome<RouteUpdated>(
      s,
      UpdateRouteCommand('player', made.routeId, cargoShips: 1),
    );
    expect(fewer.gained, {'cargo_ship': n(2)});
    final gone = outcome<RouteRemoved>(
      s,
      RemoveRouteCommand('player', made.routeId),
    );
    expect(gone.bodyId, 'kora');
    expect(gone.gained, {'cargo_ship': n(1)});
    final sent = outcome<ShipsSent>(
      s,
      const MoveShipsCommand('player', 'kora', 'hollow_reach', 2),
    );
    expect(
      (sent.bodyId, sent.toBodyId, sent.count),
      ('kora', 'hollow_reach', 2),
    );
    expect(sent.spent, {'cargo_ship': n(2)});
    final flight = s.shipments.single;
    expect((sent.shipmentId, sent.arriveAt), (flight.routeId, flight.arriveAt));
  });

  test('a sale says what it sold and earned', () {
    final s = rich()..body('kora').stock['steel'] = n(40);
    final before = s.faction('player').credits;
    final o = outcome<Sold>(s, SellCommand('player', 'kora', 'steel', n(100)));
    expect((o.bodyId, o.resourceId, o.amount), ('kora', 'steel', n(40)));
    expect(
      o.revenue.toDouble(),
      closeTo((s.faction('player').credits - before).toDouble(), 1e-6),
    );
    expect(o.spent, {'steel': n(40)});
    expect(o.gained, {'credits': o.revenue});
  });

  test('claims, surveys and extra slots say when they finish', () {
    final s = rich()
      ..body('kora').stock['survey_drone'] = n(3)
      ..body('kora').stock['outpost_kit'] = n(50);
    final claim = outcome<ProjectStarted>(
      s,
      const ClaimBodyCommand('player', 'brine', 'kora'),
    );
    final p = s.projects.single;
    expect(
      (claim.projectId, claim.kind, claim.targetId, claim.finishAt),
      (p.id, ProjectKind.claim, 'brine', p.finishAt),
    );
    // Hollow Reach is owned already, so this claim takes kits.
    expect(claim.noKitsNeeded, isFalse);
    expect(claim.spent.keys, contains('outpost_kit'));
    final first = e.newGame(1)..faction('player').credits = n(1e9);
    expect(
      outcome<ProjectStarted>(
        first,
        const ClaimBodyCommand('player', 'brine', 'kora'),
      ).noKitsNeeded,
      isTrue,
    );
    final survey = outcome<ProjectStarted>(
      s,
      const SurveyCommand('player', null, 'kora'),
    );
    expect(
      (survey.kind, survey.targetId, survey.bodyId),
      (ProjectKind.survey, 'tessaly', 'kora'),
    );
    expect(survey.spent, surveyCost(content));
    final slot = outcome<ProjectStarted>(
      s,
      const ExpandSlotsCommand('player', 'kora'),
    );
    expect((slot.kind, slot.targetId), (ProjectKind.expandSlots, 'kora'));
    expect(slot.finishAt, s.time + content.rules.expandSlotsSeconds);
  });

  group('megaproject deliveries', () {
    Map<String, BigNum> goods(int level) => {
      for (final MapEntry(:key, :value) in megaprojectCost(
        content,
        station,
        level,
      ).entries)
        if (key != 'credits') key: value,
    };
    BigNum credits(int level) =>
        megaprojectCost(content, station, level)['credits']!;
    DeliverToMegaprojectCommand deliver(Map<String, BigNum> amounts) =>
        DeliverToMegaprojectCommand(
          'player',
          'orbital_station',
          'kora',
          amounts,
        );

    test('a part delivery says what is still needed', () {
      final s = rich()..body('kora').stock['hull_plate'] = n(10);
      final o = outcome<MegaprojectDelivered>(
        s,
        deliver({'hull_plate': n(10)}),
      );
      expect(
        (o.megaprojectId, o.level, o.bodyId),
        ('orbital_station', 1, 'kora'),
      );
      expect(o.delivered, {'hull_plate': n(10)});
      expect(o.spent, o.delivered);
      expect(o.remaining, megaprojectRemaining(s, content, 'player', station));
      expect(
        (o.stageStarted, o.queued, o.projectId, o.finishAt),
        (false, false, null, null),
      );
    });

    test('the final delivery starts the stage', () {
      final s = rich()..body('kora').stock.addAll(goods(0));
      final o = outcome<MegaprojectDelivered>(
        s,
        deliver({...goods(0), 'credits': credits(0)}),
      );
      final p = s.projects.single;
      expect(o.remaining, isEmpty);
      expect(
        (o.stageStarted, o.queued, o.projectId, o.finishAt),
        (true, false, p.id, p.finishAt),
      );
      expect(o.delivered['credits'], credits(0));
    });

    test('paid in full while a stage runs, it is queued', () {
      final s = rich()..body('kora').stock.addAll(goods(0));
      outcome<MegaprojectDelivered>(
        s,
        const StartMegaprojectStageCommand('player', 'orbital_station', 'kora'),
      );
      final running = s.projects.single;
      s.body('kora').stock.addAll(goods(1));
      final o = outcome<MegaprojectDelivered>(
        s,
        const StartMegaprojectStageCommand('player', 'orbital_station', 'kora'),
      );
      expect(o.level, 2);
      expect(
        (o.stageStarted, o.queued, o.projectId, o.finishAt),
        (false, true, null, running.finishAt),
      );
      expect(o.delivered, megaprojectCost(content, station, 1));
    });
  });

  group('contracts', () {
    /// A new game with a full board.
    GameState board() {
      final s = e.newGame(1);
      e.advance(s, content.rules.contractRefillSeconds * 2 + 60);
      return s;
    }

    test('a part delivery says how far it got, the last one what it paid', () {
      final s = board();
      final f = s.faction('player');
      final k = f.contracts.first;
      s.body('kora').stock[k.resourceId] = k.quantity;
      final half = outcome<ContractProgress>(
        s,
        DeliverContractCommand(
          'player',
          k.id,
          'kora',
          k.remaining.mulDouble(0.5),
        ),
      );
      expect(
        (half.contractId, half.resourceId, half.completed, half.rewardPaid),
        (k.id, k.resourceId, false, null),
      );
      expect(half.totalDelivered, half.delivered);
      expect(half.quantity, k.quantity);
      expect(half.nextContractAt, isNull);
      expect(half.gained, isEmpty);
      final rest = outcome<ContractProgress>(
        s,
        DeliverContractCommand('player', k.id, 'kora', k.quantity),
      );
      expect(rest.completed, isTrue);
      expect(rest.rewardPaid, k.rewardCredits);
      expect(rest.gained, {'credits': k.rewardCredits});
      expect(rest.totalDelivered, k.quantity);
      expect(rest.nextContractAt, f.contractRefillAt.first);
    });

    test('a discard says when the next contract arrives', () {
      final s = board();
      final f = s.faction('player');
      final k = f.contracts.first;
      final o = outcome<ContractDiscarded>(
        s,
        DiscardContractCommand('player', k.id),
      );
      expect(
        (o.contractId, o.resourceId, o.quantity),
        (k.id, k.resourceId, k.quantity),
      );
      expect(o.nextContractAt, f.contractRefillAt.first);
    });
  });
}
