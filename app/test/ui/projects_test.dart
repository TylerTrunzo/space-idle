import 'package:flutter_test/flutter_test.dart';
import 'package:game_core/game_core.dart';
import 'package:material_ui/material_ui.dart';
import 'package:space_idle/game/clock.dart';
import 'package:space_idle/game/content_source.dart';
import 'package:space_idle/game/game_controller.dart';
import 'package:space_idle/game/save_store.dart';
import 'package:space_idle/theme.dart';
import 'package:space_idle/ui/controller_scope.dart';
import 'package:space_idle/ui/projects/projects_tab.dart';
import 'package:space_idle/ui/shell.dart';
import 'package:space_idle/view/messages.dart';

final Content content = loadEmbeddedContent();
const _p = 'player';

Finder _key(String k) => find.byKey(ValueKey(k));

void main() {
  late GameController c;
  late List<VoidCallback> fills;
  String? shown;

  setUp(() {
    fills = [];
    shown = null;
    c = GameController(
      content: content,
      store: MemorySaveStore(),
      clock: FakeClock(DateTime.utc(2026, 11, 27)),
      newGameSeed: 1,
      scheduleFill: fills.add,
    );
  });

  Future<void> pump(
    WidgetTester tester, {
    Size size = const Size(800, 4000),
    double textScale = 1,
    Widget tab = const ProjectsTab(),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    if (textScale != 1) {
      tester.platformDispatcher.textScaleFactorTestValue = textScale;
      addTearDown(tester.platformDispatcher.clearAllTestValues);
    }
    await tester.pumpWidget(
      ControllerScope(
        controller: c,
        child: MaterialApp(
          theme: buildTheme(),
          home: ShellScope(
            selectedId: null,
            selectBody: (_) {},
            clearSelection: () {},
            showOnMap: (id) => shown = id,
            child: Scaffold(body: tab),
          ),
        ),
      ),
    );
  }

  /// Plenty of credits, and of every good on Kora.
  void enrich() {
    c.state.faction(_p).credits = BigNum.parse('1e15');
    for (final id in content.resources.keys) {
      c.state.body('kora').stock[id] = BigNum.from(1e7);
    }
  }

  ContractState post({
    String id = 'c_one',
    String resourceId = 'copper_ore',
    int quantity = 1000,
    int reward = 7500,
  }) {
    final k = ContractState(
      id: id,
      templateId: 'veyra_bulk',
      resourceId: resourceId,
      quantity: BigNum.from(quantity),
      rewardCredits: BigNum.from(reward),
      postedAt: c.state.time,
    );
    c.state.faction(_p).contracts.add(k);
    return k;
  }

  String textOf(WidgetTester tester, Finder f) {
    final texts = tester
        .widgetList<Text>(find.descendant(of: f, matching: find.byType(Text)))
        .map((t) => t.data ?? t.textSpan?.toPlainText() ?? '');
    final rich = tester
        .widgetList<RichText>(
          find.descendant(of: f, matching: find.byType(RichText)),
        )
        .map((t) => t.text.toPlainText());
    return [...texts, ...rich].join(' | ');
  }

  group('active projects and surveys', () {
    testWidgets('starting a survey shows a project row with a countdown', (
      tester,
    ) async {
      c.state.faction(_p).credits = BigNum.from(1e6);
      c.state.body('kora').stock['survey_drone'] = BigNum.from(3);
      await pump(tester);
      expect(_key('projects-none'), findsOneWidget);
      final row = _key('survey-veyra');
      expect(textOf(tester, row), contains('20K credits and 3 Survey Drone'));
      expect(textOf(tester, row), contains('3h'));
      await tester.tap(_key('survey-start-veyra'));
      await tester.pump();
      final p = c.state.projects.single;
      expect(p.kind, ProjectKind.survey);
      final project = _key('project-${p.id}');
      expect(project, findsOneWidget);
      expect(textOf(tester, project), contains('3h left'));
      c.tickSeconds(600);
      await tester.pump();
      expect(textOf(tester, project), contains('2h 50m left'));
      expect(
        tester
            .widget<LinearProgressIndicator>(
              find.descendant(
                of: project,
                matching: find.byType(LinearProgressIndicator),
              ),
            )
            .value,
        closeTo(600 / 10800, 1e-6),
      );
    });

    testWidgets('a survey over half the credits takes a second tap', (
      tester,
    ) async {
      c.state.faction(_p).credits = BigNum.from(30000);
      c.state.body('kora').stock['survey_drone'] = BigNum.from(3);
      await pump(tester);
      await tester.tap(_key('survey-start-veyra'));
      await tester.pump();
      expect(c.state.projects, isEmpty);
      expect(find.textContaining('Spend 20K of 30K credits'), findsOneWidget);
      await tester.tap(_key('confirm-survey-veyra'));
      await tester.pump();
      expect(c.state.projects.single.kind, ProjectKind.survey);
    });

    testWidgets('a survey it cannot pay for is disabled, with the reason', (
      tester,
    ) async {
      await pump(tester);
      final b = tester.widget<ButtonStyleButton>(_key('survey-start-veyra'));
      expect(b.onPressed, isNull);
      expect(
        textOf(tester, _key('survey-veyra')),
        contains('needs 20K credits'),
      );
    });

    testWidgets('no signals left: Survey is disabled and says so', (
      tester,
    ) async {
      for (final b in c.state.bodies) {
        b.surveyed = true;
      }
      await pump(tester);
      expect(_key('survey-none'), findsOneWidget);
      final b = tester.widget<ButtonStyleButton>(_key('survey-start-none'));
      expect(b.onPressed, isNull);
      expect(
        textOf(tester, _key('survey-none')),
        contains('No signals left to survey'),
      );
    });

    testWidgets('a claim under way has a Go to its body', (tester) async {
      c.state.faction(_p).credits = BigNum.from(1e6);
      c.state.body('kora').stock['outpost_kit'] = BigNum.from(10);
      c.run(const ClaimBodyCommand(_p, 'brine', 'kora'));
      await pump(tester);
      final p = c.state.projects.single;
      expect(textOf(tester, _key('project-${p.id}')), contains('Brine'));
      await tester.tap(_key('project-go-${p.id}'));
      expect(shown, 'brine');
    });
  });

  group('megaproject cards', () {
    testWidgets('both megaprojects show, the Mass Driver locked', (
      tester,
    ) async {
      await pump(tester);
      expect(_key('mp-orbital_station'), findsOneWidget);
      expect(_key('mp-mass_driver'), findsOneWidget);
      expect(
        textOf(tester, _key('mp-mass_driver')),
        contains('Opens at Orbital Station level 1'),
      );
    });

    testWidgets('delivering part of a cost raises its bar, no timer', (
      tester,
    ) async {
      c.state.body('kora').stock['hull_plate'] = BigNum.from(300);
      await pump(tester);
      final line = _key('mp-line-orbital_station-hull_plate');
      expect(textOf(tester, line), contains('0 of 1.5K'));
      expect(
        textOf(tester, _key('mp-deliver-orbital_station-hull_plate')),
        contains('Deliver 300 from Kora'),
      );
      await tester.tap(_key('mp-deliver-orbital_station-hull_plate'));
      await tester.pump();
      expect(textOf(tester, line), contains('300 of 1.5K'));
      final bar = tester.widget<LinearProgressIndicator>(
        find.descendant(
          of: line,
          matching: find.byType(LinearProgressIndicator),
        ),
      );
      expect(bar.value, closeTo(0.2, 1e-9));
      expect(_key('mp-running-orbital_station'), findsNothing);
      expect(c.state.projects, isEmpty);
    });

    testWidgets('delivering the rest starts the stage, with a countdown; '
        'delivering during it is queued', (tester) async {
      enrich();
      await pump(tester);
      await tester.tap(_key('mp-all-orbital_station'));
      await tester.pump();
      expect(_key('mp-running-orbital_station'), findsNothing);
      await tester.tap(_key('mp-deliver-orbital_station-credits'));
      await tester.pump();
      final running = _key('mp-running-orbital_station');
      expect(running, findsOneWidget);
      expect(textOf(tester, running), contains('left'));
      expect(c.state.projects.single.kind, ProjectKind.megaprojectStage);
      expect(_key('mp-queued-orbital_station'), findsNothing);
      // The next stage, paid in full while this one runs.
      await tester.tap(_key('mp-all-orbital_station'));
      await tester.pump();
      await tester.tap(_key('mp-deliver-orbital_station-credits'));
      await tester.pump();
      expect(
        textOf(tester, _key('mp-queued-orbital_station')),
        contains('queued: starts when this stage finishes'),
      );
    });

    testWidgets('Deliver all goods stops once the stage starts: nothing '
        'spills into the next', (tester) async {
      final def = content.megaprojects['orbital_station']!;
      final cost = megaprojectCost(content, def, 0);
      c.state.faction(_p).credits = cost[creditsKey]! * BigNum.from(2);
      c.run(
        DeliverToMegaprojectCommand(_p, 'orbital_station', 'kora', {
          creditsKey: cost[creditsKey]!,
        }),
      );
      final brine = c.state.body('brine')..ownerId = _p;
      for (final MapEntry(key: id, value: need) in cost.entries) {
        if (id == creditsKey) continue;
        c.state.body('kora').stock[id] = need;
        brine.stock[id] = BigNum.from(500);
      }
      await pump(tester);
      await tester.tap(_key('mp-all-orbital_station'));
      await tester.pump();
      expect(c.state.projects.single.kind, ProjectKind.megaprojectStage);
      for (final id in cost.keys) {
        if (id == creditsKey) continue;
        expect(brine.stock[id], BigNum.from(500), reason: id);
      }
      expect(
        c.state.faction(_p).megaprojectProgress['orbital_station'] ?? {},
        isEmpty,
        reason: 'nothing paid toward level 2',
      );
    });

    testWidgets('Deliver all goods says what every body gave, in one '
        'message', (tester) async {
      c.state.body('brine').ownerId = _p;
      c.state.body('kora').stock['hull_plate'] = BigNum.from(300);
      c.state.body('brine').stock['hull_plate'] = BigNum.from(200);
      await pump(tester);
      await tester.tap(_key('mp-all-orbital_station'));
      await tester.pump();
      expect(c.state.body('kora').stock['hull_plate'], BigNum.zero());
      expect(c.state.body('brine').stock['hull_plate'], BigNum.zero());
      final bar = find.byType(SnackBar);
      expect(bar, findsOneWidget);
      final said = textOf(tester, bar);
      expect(said, contains('Kora'));
      expect(said, contains('Brine'));
    });

    testWidgets('the card shows the bonus it gives now beside the next', (
      tester,
    ) async {
      final def = content.megaprojects['orbital_station']!;
      await pump(tester);
      expect(
        textOf(tester, _key('mp-now-orbital_station')),
        contains('Now: no bonus yet'),
      );
      c.state.faction(_p).megaprojectLevels['orbital_station'] = 2;
      c.tickSeconds(1);
      await tester.pump();
      expect(
        textOf(tester, _key('mp-now-orbital_station')),
        contains('Now: ${megaprojectBonusText(def, 2)}'),
      );
      expect(
        textOf(tester, _key('mp-orbital_station')),
        contains('Level 3: ${megaprojectBonusText(def, 3)}'),
      );
    });

    testWidgets('credits over half of those held take a second tap', (
      tester,
    ) async {
      c.state.faction(_p).credits = BigNum.parse('3e7');
      await pump(tester);
      expect(
        textOf(tester, _key('mp-deliver-orbital_station-credits')),
        contains('Deliver 20M credits'),
      );
      await tester.tap(_key('mp-deliver-orbital_station-credits'));
      await tester.pump();
      expect(c.state.faction(_p).credits, BigNum.parse('3e7'));
      await tester.tap(_key('confirm-mp-orbital_station-credits'));
      await tester.pump();
      expect(c.state.faction(_p).credits, BigNum.parse('1e7'));
    });

    testWidgets('a long press on Deliver picks the body', (tester) async {
      c.state.body('brine').ownerId = _p;
      c.state.body('brine').stock['hull_plate'] = BigNum.from(20);
      c.state.body('kora').stock['hull_plate'] = BigNum.from(300);
      await pump(tester);
      await tester.longPress(_key('mp-deliver-orbital_station-hull_plate'));
      await tester.pumpAndSettle();
      await tester.tap(_key('mp-pick-orbital_station-hull_plate-brine'));
      await tester.pumpAndSettle();
      expect(c.state.body('brine').stock['hull_plate'], BigNum.zero());
      expect(c.state.body('kora').stock['hull_plate'], BigNum.from(300));
    });

    testWidgets('the auto settings: goods mode, credits, weight', (
      tester,
    ) async {
      await pump(tester);
      Future<void> tap(String k) async {
        await tester.tap(_key(k));
        await tester.pump();
      }

      MegaprojectAuto? auto() =>
          c.state.faction(_p).megaprojectAuto['orbital_station'];
      await tap('mp-goods-orbital_station-always');
      expect(auto()?.goods, GoodsFeedMode.always);
      expect(
        textOf(tester, _key('mp-feed-orbital_station')),
        contains('Goods go in from every body'),
      );
      await tap('mp-credits-orbital_station');
      expect(auto()?.credits, isTrue);
      await tap('mp-weight-up-orbital_station');
      expect(auto()?.creditWeight, 2);
      await tap('mp-weight-down-orbital_station');
      await tap('mp-weight-down-orbital_station');
      expect(auto()?.creditWeight, 0);
      await tap('mp-goods-orbital_station-nearReady');
      expect(auto()?.goods, GoodsFeedMode.nearReady);
      expect(auto()?.credits, isTrue);
      expect(auto()?.creditWeight, 0);
    });

    testWidgets('unfunded by choice: the card says so plainly', (tester) async {
      c.run(
        const SetMegaprojectAutoCommand(
          _p,
          'orbital_station',
          goods: GoodsFeedMode.always,
        ),
      );
      await pump(tester);
      expect(
        textOf(tester, _key('mp-unfunded-orbital_station')),
        contains('Not funded'),
      );
      expect(_key('mp-unfunded-mass_driver'), findsNothing);
    });

    testWidgets('a contract holding its goods is named, with a Go to it', (
      tester,
    ) async {
      c.run(
        const SetMegaprojectAutoCommand(
          _p,
          'orbital_station',
          goods: GoodsFeedMode.always,
        ),
      );
      post(id: 'c_hull', resourceId: 'hull_plate', quantity: 100);
      c.state.body('kora').stock['hull_plate'] = BigNum.from(60);
      c.tickSeconds(1);
      // A short screen, so the contract starts below the fold.
      await pump(tester, size: const Size(400, 700));
      expect(
        textOf(tester, _key('mp-orbital_station')),
        contains("Veyra Exchange's contract holds 60 Hull Plate this needs"),
      );
      await tester.ensureVisible(_key('mp-block-go-orbital_station-c_hull'));
      await tester.pump();
      expect(_key('contract-c_hull'), findsNothing, reason: 'below the fold');
      await tester.tap(_key('mp-block-go-orbital_station-c_hull'));
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      final card = _key('contract-c_hull');
      expect(card, findsOneWidget);
      final top = tester.getTopLeft(card).dy;
      expect(top, inInclusiveRange(0, 700), reason: 'scrolled into view');
    });
  });

  group('contracts', () {
    testWidgets('delivering a contract in full pays the reward', (
      tester,
    ) async {
      post(quantity: 100, reward: 7500);
      c.state.body('kora').stock['copper_ore'] = BigNum.from(400);
      final before = c.state.faction(_p).credits;
      await pump(tester);
      final card = _key('contract-c_one');
      expect(textOf(tester, card), contains('7.5K credits'));
      expect(
        textOf(tester, _key('contract-deliver-c_one-kora')),
        contains('Deliver 100 from Kora'),
      );
      await tester.tap(_key('contract-deliver-c_one-kora'));
      await tester.pump();
      expect(c.state.faction(_p).credits, before + BigNum.from(7500));
      expect(card, findsNothing);
      expect(find.textContaining('paid 7.5K credits'), findsOneWidget);
    });

    testWidgets('Deliver all previews each body, warns, then delivers', (
      tester,
    ) async {
      post(id: 'c_ore', resourceId: 'iron_ore', quantity: 100, reward: 900);
      c.state.body('brine').ownerId = _p;
      c.state.body('kora').stock['iron_ore'] = BigNum.from(70);
      c.state.body('brine').stock['iron_ore'] = BigNum.from(50);
      await pump(tester);
      await tester.tap(_key('contract-all-c_ore'));
      await tester.pump();
      expect(c.state.body('kora').stock['iron_ore'], BigNum.from(70));
      final preview = textOf(tester, _key('contract-preview-c_ore'));
      expect(preview, contains('70 from Kora'));
      expect(preview, contains('30 from Brine'));
      expect(preview, contains("Kora's own buildings use Iron Ore"));
      await tester.tap(_key('contract-all-confirm-c_ore'));
      await tester.pump();
      expect(c.state.body('kora').stock['iron_ore'], BigNum.zero());
      expect(c.state.body('brine').stock['iron_ore'], BigNum.from(20));
    });

    testWidgets('Deliver all with nothing held says why, delivers nothing', (
      tester,
    ) async {
      post();
      await pump(tester);
      await tester.tap(_key('contract-all-c_one'));
      await tester.pump();
      expect(_key('contract-all-confirm-c_one'), findsNothing);
      expect(textOf(tester, _key('contract-preview-c_one')), isNotEmpty);
    });

    testWidgets('Discard needs two taps', (tester) async {
      post();
      await pump(tester);
      await tester.tap(_key('contract-discard-c_one'));
      await tester.pump();
      expect(c.state.faction(_p).contracts, hasLength(1));
      expect(find.textContaining('Discard this contract?'), findsOneWidget);
      await tester.tap(_key('contract-discard-confirm-c_one'));
      await tester.pump();
      expect(c.state.faction(_p).contracts, isEmpty);
      expect(_key('contract-c_one'), findsNothing);
    });

    testWidgets('a refilling slot says when the next contract comes', (
      tester,
    ) async {
      final f = c.state.faction(_p);
      f.contractRefillAt
        ..clear()
        ..add(c.state.time + 7200);
      await pump(tester);
      expect(textOf(tester, _key('next-contract')), contains('2h'));
      f.contractRefillAt.clear();
      c.tickSeconds(1);
      await tester.pump();
      expect(_key('next-contract'), findsNothing);
    });
  });

  testWidgets('a focused system scrolls its Survey row into view, marked', (
    tester,
  ) async {
    await pump(
      tester,
      size: const Size(400, 700),
      tab: const ProjectsTab(focus: SurveyFocus('veyra', 1)),
    );
    await tester.pump();
    expect(_key('survey-focus-veyra'), findsOneWidget);
  });

  testWidgets('360x640 at 2x text: no overflow anywhere in the tab', (
    tester,
  ) async {
    enrich();
    c.state.body('brine').ownerId = _p;
    c.run(const SurveyCommand(_p, null, 'kora'));
    c.run(const StartMegaprojectStageCommand(_p, 'orbital_station', 'kora'));
    c.run(
      const SetMegaprojectAutoCommand(
        _p,
        'mass_driver',
        goods: GoodsFeedMode.nearReady,
      ),
    );
    post(id: 'c_a', quantity: 100);
    post(id: 'c_b', resourceId: 'iron_ore', quantity: 5000);
    c.state.faction(_p).credits = BigNum.parse('1e40');
    await pump(tester, size: const Size(360, 640), textScale: 2);
    expect(tester.takeException(), isNull);
    for (var i = 0; i < 40; i++) {
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -400));
      await tester.pump();
    }
    expect(tester.takeException(), isNull);
  });
}
