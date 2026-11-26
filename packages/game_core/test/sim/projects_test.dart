import 'dart:convert';

import 'package:game_core/game_core.dart';
import 'package:test/test.dart';

import '../state/helpers.dart';

BigNum n(num v) => BigNum.from(v);

String encode(GameState s) => jsonEncode(s.toJson());

/// The shipped content with [rules] laid over its rules file.
Content contentWithRules(Map<String, Object?> rules) {
  final b = shippedBundle();
  b['rules'] = {...(b['rules']! as Map).cast<String, Object?>(), ...rules};
  return switch (Content.fromBundle(b)) {
    ContentOk(:final content) => content,
    ContentInvalid(:final errors) => throw StateError('$errors'),
  };
}

void main() {
  final content = shippedContent();
  final e = GameEngine(content);

  /// A new game whose player has a billion credits.
  GameState rich() => e.newGame(1)..faction('player').credits = n(1e9);

  /// Applies [cmd], expects success, and returns the created id.
  String? ok(GameState s, Command cmd, {GameEngine? using}) {
    final r = (using ?? e).apply(s, cmd);
    expect(r, isA<CommandOk>(), reason: r is CommandFailed ? r.message : '');
    return (r as CommandOk).createdId;
  }

  /// Applies [cmd], expects [error] with the state unchanged, and returns
  /// the failure's message.
  String fails(GameState s, Command cmd, CommandError error) {
    final before = encode(s);
    final r = e.apply(s, cmd);
    expect(r, isA<CommandFailed>().having((f) => f.error, 'error', error));
    expect(encode(s), before);
    return (r as CommandFailed).message;
  }

  /// Adds a rival faction that owns Cinder.
  void addRival(GameState s) {
    s.factions.add(
      FactionState(
        id: 'rival',
        name: 'Rival',
        isPlayer: false,
        credits: n(1e9),
        baseCrew: 0,
      ),
    );
    s.body('cinder').ownerId = 'rival';
  }

  const claimBrine = ClaimBodyCommand('player', 'brine', 'kora');
  const expandKora = ExpandSlotsCommand('player', 'kora');

  group('a claim', () {
    test('completes after its duration, and not before', () {
      final s = rich();
      final id = ok(s, claimBrine);
      expect(id, startsWith('p'));
      final p = e.projectsFor(s, 'player').single;
      expect(p.id, id);
      expect(p.kind, ProjectKind.claim);
      expect(p.targetId, 'brine');
      expect(p.startedAt, 0);
      expect(p.finishAt, 1800);
      expect(s.body('brine').ownerId, isNull);

      e.advance(s, 1740);
      expect(s.body('brine').ownerId, isNull);
      expect(e.projectsFor(s, 'player'), hasLength(1));
      // The tick that starts at its finish time completes it, as a
      // shipment due then lands at the start of that tick.
      e.tick(s, 60);
      expect(s.time, 1800);
      expect(s.body('brine').ownerId, isNull);
      e.tick(s, 60);
      expect(s.body('brine').ownerId, 'player');
      expect(e.projectsFor(s, 'player'), isEmpty);
    });

    test('a completed claim reaches the bodies-owned milestone', () {
      final s = rich();
      ok(s, claimBrine);
      e.advance(s, 1860);
      expect(s.faction('player').reachedMilestones, contains('own_2_bodies'));
    });

    test('makes the body owned exactly once', () {
      final s = rich();
      ok(s, claimBrine);
      e.advance(s, 1700);
      // Saved and loaded close to its finish, then caught up past it.
      final loaded =
          (SaveCodec.decode(SaveCodec.encode(s), content) as SaveOk).state;
      final sum = e.catchUpOffline(loaded, 600);
      expect(sum.projectsCompleted, hasLength(1));
      expect(loaded.body('brine').ownerId, 'player');
      expect(loaded.projects, isEmpty);
      final owned = loaded.bodies.where((b) => b.ownerId == 'player').length;
      expect(owned, 2);
      expect(e.catchUpOffline(loaded, 7200).projectsCompleted, isEmpty);
      expect(loaded.bodies.where((b) => b.ownerId == 'player'), hasLength(2));
      fails(loaded, claimBrine, CommandError.alreadyOwned);
    });
  });

  group('durations', () {
    test('the n-th claim takes base + perOwned × (owned − 1)', () {
      final s = rich();
      expect(content.rules.claimSecondsBase, 1800);
      expect(content.rules.claimSecondsPerOwned, 1800);
      expect(claimSeconds(s, content, 'player'), 1800);
      s.body('cinder').ownerId = 'player';
      expect(claimSeconds(s, content, 'player'), 3600);
      // A claim under way counts as owned for the next one.
      s.body('kora').stock['outpost_kit'] = n(10);
      ok(s, claimBrine);
      expect(e.projectsFor(s, 'player').single.finishAt, 3600);
      expect(claimSeconds(s, content, 'player'), 5400);
    });

    test('claims are clamped to [600, 21600] seconds', () {
      final quick = contentWithRules({
        'claimSecondsBase': 60,
        'claimSecondsPerOwned': 0,
      });
      expect(claimSeconds(rich(), quick, 'player'), 600);
      final slow = contentWithRules({
        'claimSecondsBase': 7200,
        'claimSecondsPerOwned': 10000,
      });
      final s = rich();
      expect(claimSeconds(s, slow, 'player'), 7200);
      s.body('cinder').ownerId = 'player';
      expect(claimSeconds(s, slow, 'player'), 17200);
      s.body('vastmere').ownerId = 'player';
      expect(claimSeconds(s, slow, 'player'), 21600);
    });

    test('the rules default when the file leaves them out', () {
      final b = shippedBundle();
      (b['rules']! as Map)
        ..remove('claimSecondsBase')
        ..remove('claimSecondsPerOwned')
        ..remove('expandSlotsSeconds');
      final r = (Content.fromBundle(b) as ContentOk).content.rules;
      expect(r.claimSecondsBase, 1800);
      expect(r.claimSecondsPerOwned, 1800);
      expect(r.expandSlotsSeconds, 3600);
    });

    test('the rules are validated', () {
      final b = shippedBundle();
      (b['rules']! as Map)
        ..['claimSecondsBase'] = -1
        ..['claimSecondsPerOwned'] = 'slow'
        ..['expandSlotsSeconds'] = 60;
      final errors = (Content.fromBundle(b) as ContentInvalid).errors;
      expect(
        errors,
        containsAll([
          'rules.claimSecondsBase: must be >= 0',
          'rules.claimSecondsPerOwned: expected a number',
          'rules.expandSlotsSeconds: must be >= 600',
        ]),
      );
      (b['rules']! as Map)
        ..['claimSecondsBase'] = 0
        ..['claimSecondsPerOwned'] = 0
        ..['expandSlotsSeconds'] = 21601;
      expect((Content.fromBundle(b) as ContentInvalid).errors, [
        'rules.expandSlotsSeconds: must be <= 21600',
      ]);
    });

    test('a slot expansion takes expandSlotsSeconds', () {
      final s = rich();
      expect(content.rules.expandSlotsSeconds, 3600);
      ok(s, expandKora);
      final p = e.projectsFor(s, 'player').single;
      expect(
        (p.kind, p.targetId, p.finishAt),
        (ProjectKind.expandSlots, 'kora', 3600),
      );
      expect(s.body('kora').extraSlots, 0);
      e.advance(s, 3660);
      expect(s.body('kora').extraSlots, 1);
      expect(s.projects, isEmpty);
    });
  });

  group('costs are taken at start', () {
    test('so a second claim cannot spend the same credits', () {
      final s = e.newGame(1);
      final cost = claimCost(s, content, 'player');
      expect(cost.keys, ['credits']);
      s.faction('player').credits = cost['credits']!;
      ok(s, claimBrine);
      expect(s.faction('player').credits, const BigNum.zero());
      // The claim under way counts toward the next one's price.
      expect(claimCost(s, content, 'player'), {
        'credits':
            content.rules.claimBaseCredits * n(content.rules.claimGrowth),
        'outpost_kit': n(
          content.rules.claimKitsBase + content.rules.claimKitsPerOwned,
        ),
      });
      fails(
        s,
        const ClaimBodyCommand('player', 'hollow_reach', 'kora'),
        CommandError.cannotAfford,
      );
    });

    test('so a second expansion cannot spend the same credits', () {
      final s = e.newGame(1)..body('cinder').ownerId = 'player';
      final cost = slotCost(content, s.body('kora'))['credits']!;
      s.faction('player').credits = cost;
      ok(s, expandKora);
      expect(s.faction('player').credits, const BigNum.zero());
      fails(
        s,
        const ExpandSlotsCommand('player', 'cinder'),
        CommandError.cannotAfford,
      );
    });

    test('and the kits too', () {
      final s = rich()..body('cinder').ownerId = 'player';
      final kits = claimCost(s, content, 'player')['outpost_kit']!;
      s.body('kora').stock['outpost_kit'] = kits;
      ok(s, claimBrine);
      expect(s.body('kora').stock['outpost_kit'], const BigNum.zero());
    });
  });

  group('projectInProgress', () {
    test('a second claim on the same body', () {
      final s = rich();
      ok(s, claimBrine);
      expect(
        fails(s, claimBrine, CommandError.projectInProgress),
        'You are already claiming Brine (30m left)',
      );
    });

    test("another faction's claim on the same body", () {
      final s = rich();
      addRival(s);
      ok(s, const ClaimBodyCommand('rival', 'brine', 'cinder'));
      expect(
        fails(s, claimBrine, CommandError.projectInProgress),
        'Rival is already claiming Brine',
      );
    });

    test('a second expansion on the same body', () {
      final s = rich();
      ok(s, expandKora);
      e.advance(s, 600);
      expect(
        fails(s, expandKora, CommandError.projectInProgress),
        'Kora is already getting an extra build slot (50m left)',
      );
      // Another body is free to expand meanwhile.
      s.body('cinder').ownerId = 'player';
      ok(s, const ExpandSlotsCommand('player', 'cinder'));
    });

    test('claims of different bodies run side by side', () {
      final s = rich();
      s.body('kora').stock['outpost_kit'] = n(10);
      ok(s, claimBrine);
      ok(s, const ClaimBodyCommand('player', 'cinder', 'kora'));
      expect(e.projectsFor(s, 'player').map((p) => p.targetId), [
        'brine',
        'cinder',
      ]);
    });

    test('other checks still come first', () {
      final s = rich();
      fails(
        s,
        const ClaimBodyCommand('player', 'kora', 'kora'),
        CommandError.alreadyOwned,
      );
      fails(
        s,
        const ExpandSlotsCommand('player', 'brine'),
        CommandError.notOwner,
      );
    });
  });

  group('a body being claimed', () {
    test('is still being claimed, not "not yours", for every command', () {
      final s = rich();
      s.body('kora').stock['cargo_ship'] = n(5);
      ok(s, claimBrine);
      s.body('brine').stock['steel'] = n(5);
      s
          .faction('player')
          .contracts
          .add(
            ContractState(
              id: 'c99',
              templateId: content.contractTemplates.keys.first,
              resourceId: 'steel',
              quantity: n(10),
              rewardCredits: n(100),
              postedAt: 0,
            ),
          );
      final cmds = <Command>[
        DeliverContractCommand('player', 'c99', 'brine', n(1)),
        const BuildCommand('player', 'brine', 'smelter'),
        CreateRouteCommand('player', 'kora', 'brine', 'steel', n(1), 1),
        const MoveShipsCommand('player', 'kora', 'brine', 1),
        const ExpandSlotsCommand('player', 'brine'),
        SellCommand('player', 'brine', 'steel', n(1)),
        SetAutoSellCommand('player', 'brine', 'steel', n(0)),
        const ClaimBodyCommand('player', 'cinder', 'brine'),
        const SurveyCommand('player', null, 'brine'),
        DeliverToMegaprojectCommand('player', 'orbital_station', 'brine', {
          'credits': n(1),
        }),
      ];
      for (final cmd in cmds) {
        expect(
          fails(s, cmd, CommandError.stillClaiming),
          'Brine is still being claimed (30m left)',
          reason: cmd.toJson()['cmd'] as String,
        );
      }
      // A rival's claim is no claim of the player's.
      addRival(s);
      s.projects[0] = ProjectState(
        id: 'p99',
        factionId: 'rival',
        kind: ProjectKind.claim,
        targetId: 'brine',
        startedAt: 0,
        finishAt: 1800,
      );
      fails(s, cmds.first, CommandError.notOwner);
    });
  });

  group('stepProjects', () {
    test('completes due projects in finishAt-then-id order', () {
      final s = rich()..body('kora').stock['outpost_kit'] = n(10);
      ok(s, expandKora); // p: finishes at 3600
      e.advance(s, 1800);
      ok(s, claimBrine); // finishes at 1800 + 1800 = 3600 too
      ok(s, const ClaimBodyCommand('player', 'cinder', 'kora'));
      final running = e.projectsFor(s, 'player');
      expect(running.map((p) => p.finishAt), [3600, 3600, 5400]);
      expect(running.map((p) => p.kind), [
        ProjectKind.expandSlots,
        ProjectKind.claim,
        ProjectKind.claim,
      ]);
      final sum = e.catchUpOffline(s, 1860);
      expect(
        [for (final p in sum.projectsCompleted) (p.kind, p.targetId, p.name)],
        [
          (ProjectKind.expandSlots, 'kora', 'Kora'),
          (ProjectKind.claim, 'brine', 'Brine'),
        ],
      );
      expect(e.projectsFor(s, 'player').single.targetId, 'cinder');
    });

    test('breaks a finishAt tie by creation order, so p9 before p10', () {
      final s = rich();
      for (final (id, target) in [('p10', 'brine'), ('p9', 'cinder')]) {
        s.projects.add(
          ProjectState(
            id: id,
            factionId: 'player',
            kind: ProjectKind.claim,
            targetId: target,
            startedAt: 0,
            finishAt: 600,
          ),
        );
      }
      expect(e.projectsFor(s, 'player').map((p) => p.id), ['p9', 'p10']);
      s.nextId = 11;
      final sum = e.catchUpOffline(s, 700);
      expect(sum.projectsCompleted.map((p) => p.targetId), ['cinder', 'brine']);
    });

    test('leaves projects not yet due', () {
      final s = rich();
      ok(s, claimBrine);
      s.time = 1799;
      stepProjects(s, content);
      expect(s.projects, hasLength(1));
      s.time = 1800;
      stepProjects(s, content);
      expect(s.projects, isEmpty);
      expect(s.body('brine').ownerId, 'player');
    });

    test('projectsFor lists only that faction, soonest first', () {
      final s = rich();
      addRival(s);
      ok(s, expandKora);
      ok(s, claimBrine);
      ok(s, const ExpandSlotsCommand('rival', 'cinder'));
      expect(e.projectsFor(s, 'player').map((p) => p.targetId), [
        'brine',
        'kora',
      ]);
      expect(e.projectsFor(s, 'rival').single.targetId, 'cinder');
    });
  });

  group('a project survives', () {
    test('save/load and copy()', () {
      final s = rich();
      ok(s, claimBrine);
      ok(s, expandKora);
      s.projects.first.data['note'] = {
        'list': [1, 2],
      };
      e.advance(s, 600);
      final loaded =
          (SaveCodec.decode(SaveCodec.encode(s), content) as SaveOk).state;
      final copied = s.copy();
      expect(encode(loaded), encode(s));
      expect(encode(copied), encode(s));
      expect(loaded.projects, hasLength(2));

      // The copy is independent, data included.
      ((copied.projects.first.data['note']! as Map)['list']! as List).add(3);
      copied.projects.removeLast();
      expect(s.projects, hasLength(2));
      expect((s.projects.first.data['note']! as Map)['list'], [1, 2]);

      for (final x in [s, loaded]) {
        e.advance(x, 3600);
        expect(x.body('brine').ownerId, 'player');
        expect(x.body('kora').extraSlots, 1);
      }
      expect(encode(loaded), encode(s));
    });

    test('a save without projects loads with none', () {
      final m = e.newGame(1).toJson()..remove('projects');
      final r = SaveCodec.decode(jsonEncode(m), content);
      expect(r, isA<SaveOk>(), reason: r is SaveError ? r.message : '');
      expect((r as SaveOk).state.projects, isEmpty);
    });
  });

  test('completion during catchUpOffline is listed', () {
    final s = rich();
    ok(s, claimBrine);
    final sum = e.catchUpOffline(s, 3600);
    expect(sum.projectsCompleted, hasLength(1));
    final done = sum.projectsCompleted.single;
    expect(
      (done.kind, done.targetId, done.name),
      (ProjectKind.claim, 'brine', 'Brine'),
    );
    expect(s.body('brine').ownerId, 'player');
    // Nothing left to complete next time.
    expect(e.catchUpOffline(s, 3600).projectsCompleted, isEmpty);
  });

  test('a rival project completing offline is not the player\'s', () {
    final s = rich();
    addRival(s);
    ok(s, const ClaimBodyCommand('rival', 'brine', 'cinder'));
    final sum = e.catchUpOffline(s, 3600);
    expect(sum.projectsCompleted, isEmpty);
    expect(s.body('brine').ownerId, 'rival');
  });

  group('saves with projects are checked:', () {
    Map<String, Object?> project({
      String id = 'p50',
      String factionId = 'player',
      String kind = 'claim',
      String targetId = 'brine',
      num startedAt = 0,
      num finishAt = 1800,
    }) => {
      'id': id,
      'factionId': factionId,
      'kind': kind,
      'targetId': targetId,
      'startedAt': startedAt,
      'finishAt': finishAt,
      'data': <String, Object?>{},
    };

    Map<String, Object?> save(List<Map<String, Object?>> projects) =>
        e.newGame(1).toJson()
          ..['time'] = 100
          ..['nextId'] = 100
          ..['projects'] = projects;

    SaveResult decode(Map<String, Object?> m) =>
        SaveCodec.decode(jsonEncode(m), content);

    test('a valid one loads', () {
      final r = decode(
        save([
          project(),
          project(id: 'p51', kind: 'expandSlots', targetId: 'kora'),
        ]),
      );
      expect(r, isA<SaveOk>(), reason: r is SaveError ? r.message : '');
    });

    test('one without data loads with empty data it can add to', () {
      final r = decode(save([project()..remove('data')]));
      final data = (r as SaveOk).state.projects.single.data;
      expect(data, isEmpty);
      data['level'] = 1;
      expect(r.state.projects.single.data, {'level': 1});
    });

    final invalid = <String, List<Map<String, Object?>>>{
      'owner is not a faction': [project(factionId: 'ghost')],
      'finishes before it starts': [project(startedAt: 50, finishAt: 40)],
      'starts after the save time': [project(startedAt: 200, finishAt: 400)],
      'duplicate id': [
        project(),
        project(kind: 'expandSlots', targetId: 'kora'),
      ],
      'id at nextId': [project(id: 'p100')],
      'id above nextId': [project(id: 'p4000')],
      'claim of an owned body': [project(targetId: 'kora')],
      'two claims of one body': [project(), project(id: 'p51')],
      'expansion of a body its faction does not own': [
        project(kind: 'expandSlots', targetId: 'brine'),
      ],
      'two expansions of one body': [
        project(kind: 'expandSlots', targetId: 'kora'),
        project(id: 'p51', kind: 'expandSlots', targetId: 'kora'),
      ],
    };
    for (final MapEntry(key: name, value: projects) in invalid.entries) {
      test(name, () {
        final r = decode(save(projects));
        expect(r, isA<SaveError>(), reason: name);
        expect(
          (r as SaveError).kind,
          SaveErrorKind.invalidValue,
          reason: r.message,
        );
      });
    }

    test('a body at the most extra slots cannot be expanding', () {
      final m = save([project(kind: 'expandSlots', targetId: 'kora')]);
      (m['bodies']! as List).cast<Map<String, Object?>>().firstWhere(
        (b) => b['id'] == 'kora',
      )['extraSlots'] = SaveCodec.maxExtraSlots;
      expect((decode(m) as SaveError).kind, SaveErrorKind.invalidValue);
    });

    test('a target that does not exist is an unknown id', () {
      for (final p in [
        project(targetId: 'nowhere'),
        project(kind: 'expandSlots', targetId: 'nowhere'),
        project(kind: 'megaprojectStage', targetId: 'nothing'),
      ]) {
        final r = decode(save([p]));
        expect((r as SaveError).kind, SaveErrorKind.unknownContentId);
      }
    });

    test('an unknown kind is malformed', () {
      final r = decode(save([project(kind: 'teleport')]));
      expect((r as SaveError).kind, SaveErrorKind.missingField);
    });
  });

  test('formatDuration', () {
    expect(formatDuration(0), '0s');
    expect(formatDuration(0.2), '1s');
    expect(formatDuration(45), '45s');
    expect(formatDuration(600), '10m');
    expect(formatDuration(1830), '30m 30s');
    expect(formatDuration(3600), '1h');
    expect(formatDuration(5400), '1h 30m');
    expect(formatDuration(21599), '6h');
  });
}
