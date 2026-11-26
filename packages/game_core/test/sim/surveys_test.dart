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

List<String> rulesErrors(Map<String, Object?> rules) {
  final b = shippedBundle();
  b['rules'] = {...(b['rules']! as Map).cast<String, Object?>(), ...rules};
  return switch (Content.fromBundle(b)) {
    ContentOk() => const [],
    ContentInvalid(:final errors) => errors,
  };
}

void main() {
  final content = shippedContent();
  final e = GameEngine(content);

  /// A new game whose player has a billion credits and 3 survey drones
  /// on Kora.
  GameState rich() => e.newGame(1)
    ..faction('player').credits = n(1e9)
    ..body('kora').stock['survey_drone'] = n(3);

  String? ok(GameState s, Command cmd) {
    final r = e.apply(s, cmd);
    expect(r, isA<CommandOk>(), reason: r is CommandFailed ? r.message : '');
    return (r as CommandOk).createdId;
  }

  String fails(GameState s, Command cmd, CommandError error) {
    final before = encode(s);
    final r = e.apply(s, cmd);
    expect(r, isA<CommandFailed>().having((f) => f.error, 'error', error));
    expect(encode(s), before);
    return (r as CommandFailed).message;
  }

  const surveyTessaly = SurveyCommand('player', 'tessaly', 'kora');

  group('hidden bodies', () {
    test('start unsurveyed, every other body surveyed', () {
      final s = e.newGame(1);
      expect(s.body('tessaly').surveyed, isFalse);
      expect(s.body('dusk_cairn').surveyed, isFalse);
      expect(s.bodies.where((b) => !b.surveyed), hasLength(2));
    });

    test('are not visible to the player until surveyed', () {
      final s = e.newGame(1);
      expect(isVisible(s, s.body('tessaly'), 'player'), isFalse);
      expect(isVisible(s, s.body('brine'), 'player'), isTrue);
      expect(visibleBodies(s, 'player'), hasLength(5));
    });

    test('are unknownBody to every command', () {
      final s = rich();
      s.body('kora').stock['ship'] = n(5);
      final cmds = <Command>[
        const ClaimBodyCommand('player', 'tessaly', 'kora'),
        const ClaimBodyCommand('player', 'brine', 'tessaly'),
        const BuildCommand('player', 'tessaly', 'mine'),
        const ExpandSlotsCommand('player', 'tessaly'),
        SellCommand('player', 'tessaly', 'iron_ore', n(1)),
        SetAutoSellCommand('player', 'tessaly', 'iron_ore', n(1)),
        CreateRouteCommand('player', 'kora', 'tessaly', 'iron_ore', n(1), 1),
        CreateRouteCommand('player', 'tessaly', 'kora', 'iron_ore', n(1), 1),
        const StartMegaprojectStageCommand(
          'player',
          'orbital_station',
          'tessaly',
        ),
        DeliverContractCommand('player', 'c1', 'tessaly', n(1)),
        const SurveyCommand('player', 'tessaly', 'tessaly'),
      ];
      for (final cmd in cmds) {
        final before = encode(s);
        final r = e.apply(s, cmd);
        expect(
          r,
          isA<CommandFailed>().having(
            (f) => f.error,
            'error',
            // A delivery checks its contract first.
            cmd is DeliverContractCommand
                ? CommandError.unknownContract
                : CommandError.unknownBody,
          ),
          reason: '${cmd.toJson()}',
        );
        expect(encode(s), before);
      }
    });

    test('are not claimable even by a faction with everything', () {
      final s = rich();
      s.body('kora').stock['outpost_kit'] = n(9);
      fails(
        s,
        const ClaimBodyCommand('player', 'dusk_cairn', 'kora'),
        CommandError.unknownBody,
      );
      expect(s.projects, isEmpty);
    });

    test('do not count toward claim cost or time', () {
      final s = rich();
      final before = claimCost(s, content, 'player');
      ok(s, surveyTessaly);
      expect(claimCost(s, content, 'player'), before);
      expect(claimSeconds(s, content, 'player'), 1800);
    });
  });

  group('SurveyCommand', () {
    test('round trips through JSON', () {
      final back = Command.fromJson(
        jsonDecode(jsonEncode(surveyTessaly.toJson())) as Map<String, Object?>,
      );
      expect(back, isA<SurveyCommand>());
      expect(back.toJson(), surveyTessaly.toJson());
    });

    test('pays credits and drones from the source and starts a project', () {
      final s = rich();
      final credits = s.faction('player').credits;
      final id = ok(s, surveyTessaly);
      final p = e.projectsFor(s, 'player').single;
      expect(p.id, id);
      expect(p.kind, ProjectKind.survey);
      expect(p.targetId, 'tessaly');
      expect(p.finishAt - p.startedAt, 10800);
      expect(s.faction('player').credits, credits - n(2e4));
      expect(s.body('kora').stock['survey_drone']!.isZero, isTrue);
      expect(s.body('tessaly').surveyed, isFalse);
      expect(projectTargetName(s, content, p), 'an unsurveyed body');
    });

    test('costs come from the rules', () {
      final c = contentWithRules({
        'surveyDrones': 1,
        'surveyCredits': '500',
        'surveySeconds': 3600,
      });
      final eng = GameEngine(c);
      final s = eng.newGame(1)
        ..faction('player').credits = n(1000)
        ..body('kora').stock['survey_drone'] = n(1);
      expect(surveyCost(c), {'credits': n(500), 'survey_drone': n(1)});
      final r = eng.apply(s, surveyTessaly);
      expect(r, isA<CommandOk>());
      expect(s.faction('player').credits, n(500));
      expect(eng.projectsFor(s, 'player').single.finishAt, 3600);
    });

    test('survey time is kept between 10 minutes and 6 hours', () {
      expect(rulesErrors({'surveySeconds': 599}), isNotEmpty);
      expect(rulesErrors({'surveySeconds': 21601}), isNotEmpty);
      expect(rulesErrors({'surveySeconds': 600}), isEmpty);
      expect(rulesErrors({'surveySeconds': 21600}), isEmpty);
      // Whatever a hand-built rules object holds is clamped on use.
      final c = contentWithRules({'surveySeconds': 600});
      expect(surveySeconds(c), 600);
    });

    test('rules default to 3 drones, 3 hours and the stock drone', () {
      final b = shippedBundle();
      final rules = (b['rules']! as Map).cast<String, Object?>()
        ..remove('surveyDrones')
        ..remove('surveyCredits')
        ..remove('surveySeconds');
      b['rules'] = rules;
      final c = (Content.fromBundle(b) as ContentOk).content;
      expect(c.rules.surveyDrones, 3);
      expect(c.rules.surveySeconds, 10800);
      expect(c.rules.surveyDroneResource, 'survey_drone');
      expect(c.rules.surveyCredits, greaterThan(BigNum.zero()));
    });

    test('fails when the drones or credits are short, changing nothing', () {
      final s = rich();
      s.body('kora').stock['survey_drone'] = n(2);
      expect(
        fails(s, surveyTessaly, CommandError.cannotAfford),
        contains('Survey Drone'),
      );
      s.body('kora').stock['survey_drone'] = n(3);
      s.faction('player').credits = n(100);
      expect(
        fails(s, surveyTessaly, CommandError.cannotAfford),
        contains('credits'),
      );
    });

    test('fails from a source the faction does not own', () {
      final s = rich();
      fails(
        s,
        const SurveyCommand('player', 'tessaly', 'brine'),
        CommandError.notOwner,
      );
    });

    test('fails on an unknown body or source', () {
      final s = rich();
      fails(
        s,
        const SurveyCommand('player', 'nowhere', 'kora'),
        CommandError.unknownBody,
      );
      fails(
        s,
        const SurveyCommand('player', 'tessaly', 'dusk_cairn'),
        CommandError.unknownBody,
      );
    });

    test('fails on a body that is already surveyed', () {
      final s = rich();
      fails(
        s,
        const SurveyCommand('player', 'brine', 'kora'),
        CommandError.alreadySurveyed,
      );
    });

    test('a body is surveyed once at a time', () {
      final s = rich();
      s.body('kora').stock['survey_drone'] = n(6);
      ok(s, surveyTessaly);
      expect(
        fails(s, surveyTessaly, CommandError.projectInProgress),
        contains('already under way'),
      );
    });
  });

  group('a survey', () {
    test('reveals the body on completion, and not before', () {
      final s = rich();
      ok(s, surveyTessaly);
      e.advance(s, 10740);
      expect(s.body('tessaly').surveyed, isFalse);
      expect(isVisible(s, s.body('tessaly'), 'player'), isFalse);
      e.advance(s, 120);
      expect(s.body('tessaly').surveyed, isTrue);
      expect(isVisible(s, s.body('tessaly'), 'player'), isTrue);
      expect(s.body('dusk_cairn').surveyed, isFalse);
      expect(e.projectsFor(s, 'player'), isEmpty);
    });

    test('lets the body be claimed afterwards', () {
      final s = rich();
      ok(s, surveyTessaly);
      e.advance(s, 10860);
      ok(s, const ClaimBodyCommand('player', 'tessaly', 'kora'));
      e.advance(s, 1860);
      expect(s.body('tessaly').ownerId, 'player');
    });

    test('and a claim run side by side without interfering', () {
      final s = rich();
      final kit = s.body('kora').stock;
      kit['outpost_kit'] = n(9);
      ok(s, const ClaimBodyCommand('player', 'brine', 'kora'));
      final claim = e.projectsFor(s, 'player').single;
      ok(s, surveyTessaly);
      final projects = e.projectsFor(s, 'player');
      expect(projects, hasLength(2));
      // The claim keeps its own timer and cost.
      expect(claim.finishAt, 1800);
      expect(projects.firstWhere((p) => p.id == claim.id).finishAt, 1800);

      e.advance(s, 1860);
      expect(s.body('brine').ownerId, 'player');
      expect(s.body('tessaly').surveyed, isFalse);
      expect(e.projectsFor(s, 'player').single.kind, ProjectKind.survey);

      e.advance(s, 9000);
      expect(s.body('tessaly').surveyed, isTrue);
      expect(s.body('brine').ownerId, 'player');
      expect(s.body('tessaly').ownerId, isNull);
    });

    test('two surveys run side by side', () {
      final s = rich();
      s.body('kora').stock['survey_drone'] = n(6);
      ok(s, surveyTessaly);
      ok(s, const SurveyCommand('player', 'dusk_cairn', 'kora'));
      e.advance(s, 10860);
      expect(s.body('tessaly').surveyed, isTrue);
      expect(s.body('dusk_cairn').surveyed, isTrue);
    });

    test('completes while away and is named in the offline summary', () {
      final s = rich();
      ok(s, surveyTessaly);
      final sum = e.catchUpOffline(s, 12000);
      expect(sum.projectsCompleted, hasLength(1));
      expect(sum.projectsCompleted.single.kind, ProjectKind.survey);
      expect(sum.projectsCompleted.single.name, 'Tessaly');
      expect(s.body('tessaly').surveyed, isTrue);
    });
  });

  group('saves', () {
    GameState roundTrip(GameState s) =>
        (SaveCodec.decode(SaveCodec.encode(s), content) as SaveOk).state;

    test('keep surveyed, with a survey under way, through save/load', () {
      final s = rich();
      ok(s, surveyTessaly);
      final loaded = roundTrip(s);
      expect(encode(loaded), encode(s));
      expect(loaded.body('tessaly').surveyed, isFalse);
      expect(loaded.copy().body('tessaly').surveyed, isFalse);
      e.advance(loaded, 11000);
      expect(loaded.body('tessaly').surveyed, isTrue);
      expect(encode(roundTrip(loaded)), encode(loaded));
    });

    test('from before surveys load every body surveyed', () {
      final m = jsonDecode(encode(e.newGame(1))) as Map<String, Object?>;
      for (final b in (m['bodies']! as List).cast<Map<String, Object?>>()) {
        b.remove('surveyed');
      }
      final r = SaveCodec.decode(jsonEncode(m), content);
      expect(r, isA<SaveOk>());
      expect((r as SaveOk).state.bodies.every((b) => b.surveyed), isTrue);
    });

    Map<String, Object?> bodyJson(Map<String, Object?> m, String id) =>
        (m['bodies']! as List).cast<Map<String, Object?>>().singleWhere(
          (b) => b['id'] == id,
        );

    test('reject an unsurveyed body that is owned', () {
      final m = jsonDecode(encode(e.newGame(1))) as Map<String, Object?>;
      bodyJson(m, 'tessaly')['ownerId'] = 'player';
      final r = SaveCodec.decode(jsonEncode(m), content);
      expect(r, isA<SaveError>());
      expect((r as SaveError).kind, SaveErrorKind.invalidValue);
    });

    test('reject a survey of a body that is surveyed', () {
      final s = rich();
      ok(s, surveyTessaly);
      final m = jsonDecode(encode(s)) as Map<String, Object?>;
      bodyJson(m, 'tessaly')['surveyed'] = true;
      final r = SaveCodec.decode(jsonEncode(m), content);
      expect(r, isA<SaveError>());
      expect((r as SaveError).kind, SaveErrorKind.invalidValue);
    });

    test('reject a second survey of one body', () {
      final s = rich();
      ok(s, surveyTessaly);
      final m = jsonDecode(encode(s)) as Map<String, Object?>;
      final ps = (m['projects']! as List).cast<Map<String, Object?>>();
      ps.add({...ps.first, 'id': 'p9000'});
      m['nextId'] = 9001;
      final r = SaveCodec.decode(jsonEncode(m), content);
      expect(r, isA<SaveError>());
      expect((r as SaveError).kind, SaveErrorKind.invalidValue);
    });
  });

  group('content validation', () {
    List<String> galaxyErrors(void Function(Map<String, Object?> g) edit) {
      final b = shippedBundle();
      edit(b['galaxy']! as Map<String, Object?>);
      return switch (Content.fromBundle(b)) {
        ContentOk() => const [],
        ContentInvalid(:final errors) => errors,
      };
    }

    Map<String, Object?> body(Map<String, Object?> g, String id) {
      final system = (g['systems']! as List).first as Map<String, Object?>;
      return (system['bodies']! as List)
          .cast<Map<String, Object?>>()
          .firstWhere((b) => b['id'] == id);
    }

    test('hidden must be a boolean', () {
      expect(
        galaxyErrors((g) => body(g, 'tessaly')['hidden'] = 'yes'),
        contains(contains('hidden')),
      );
    });

    test('a home body cannot be hidden', () {
      expect(
        galaxyErrors((g) => body(g, 'kora')['hidden'] = true),
        contains(contains('hidden')),
      );
    });

    test('a galaxy with hidden bodies needs the survey drone resource', () {
      expect(
        rulesErrors({'surveyDroneResource': 'nope'}),
        contains(contains('surveyDroneResource')),
      );
    });
  });
}
