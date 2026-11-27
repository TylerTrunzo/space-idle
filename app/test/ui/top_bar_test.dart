import 'package:flutter_test/flutter_test.dart';
import 'package:game_core/game_core.dart';
import 'package:material_ui/material_ui.dart';
import 'package:space_idle/game/clock.dart';
import 'package:space_idle/game/content_source.dart';
import 'package:space_idle/game/game_controller.dart';
import 'package:space_idle/game/save_store.dart';
import 'package:space_idle/theme.dart';
import 'package:space_idle/ui/controller_scope.dart';
import 'package:space_idle/ui/top_bar.dart';

final Content content = loadEmbeddedContent();

GameController _controller() => GameController(
  content: content,
  store: MemorySaveStore(),
  clock: FakeClock(DateTime.utc(2026, 11, 27)),
  newGameSeed: 1,
);

Widget _bar(GameController c, {VoidCallback? onSettings}) => MaterialApp(
  theme: buildTheme(),
  home: ControllerScope(
    controller: c,
    child: Scaffold(
      body: Column(children: [TopBar(onSettings: onSettings ?? () {})]),
    ),
  ),
);

/// The text of every [Text] and [RichText] under the bar, joined.
String _barText(WidgetTester tester) => [
  for (final t in tester.widgetList<RichText>(
    find.descendant(of: find.byType(TopBar), matching: find.byType(RichText)),
  ))
    t.text.toPlainText(),
].join(' | ');

void main() {
  testWidgets('shows credits with their rate, crew and pinned stock', (
    tester,
  ) async {
    final c = _controller();
    await tester.pumpWidget(_bar(c));

    final text = _barText(tester);
    expect(text, contains('250'));
    expect(text, contains('/s'));
    final crew = crewTotals(c.state, content, 'player');
    expect(text, contains('${crew.free}/${crew.supported}'));
    expect(find.bySemanticsLabel(RegExp(r'^Credits 250')), findsOneWidget);
  });

  testWidgets('ticks live: the shown credits follow the game', (tester) async {
    final c = _controller();
    await tester.pumpWidget(_bar(c));
    c.state.faction('player').credits = BigNum.from(1234);
    c.tickSeconds(1);
    await tester.pump();
    expect(_barText(tester), contains('1.23K'));
  });

  testWidgets('numbers are in the monospace face', (tester) async {
    await tester.pumpWidget(_bar(_controller()));
    final spans = <TextSpan>[];
    for (final t in tester.widgetList<RichText>(
      find.descendant(of: find.byType(TopBar), matching: find.byType(RichText)),
    )) {
      t.text.visitChildren((s) {
        if (s is TextSpan && (s.text ?? '').contains('250')) spans.add(s);
        return true;
      });
    }
    expect(spans, isNotEmpty);
    expect(spans.first.style?.fontFamily, monoFontFamily);
  });

  testWidgets('the settings button is a labelled 48 px target', (tester) async {
    var opened = 0;
    await tester.pumpWidget(_bar(_controller(), onSettings: () => opened++));
    final button = find.byTooltip('Settings');
    // The tap target: the button with its padding, not its 40 px visual.
    final target = find.ancestor(of: button, matching: find.byType(IconButton));
    expect(tester.getSize(target).shortestSide, greaterThanOrEqualTo(48));
    await tester.tap(button);
    expect(opened, 1);
  });

  group('Buy max', () {
    Finder key(String k) => find.byKey(ValueKey(k));

    testWidgets('is a 48 px button labelled for screen readers', (
      tester,
    ) async {
      await tester.pumpWidget(_bar(_controller()));
      expect(find.byTooltip('Buy max'), findsOneWidget);
      final target = find.ancestor(
        of: find.byTooltip('Buy max'),
        matching: find.byType(IconButton),
      );
      expect(tester.getSize(target).shortestSide, greaterThanOrEqualTo(48));
      // Nothing is previewed until it is tapped.
      expect(find.textContaining('levels'), findsNothing);
    });

    testWidgets('a tap shows what it would buy; Buy buys it', (tester) async {
      final c = _controller();
      c.state.faction('player').credits = BigNum.from(300);
      // What the command itself buys on this state, whatever its rule.
      final dry = c.engine.apply(
        c.state.copy(),
        BuyUpgradesCommand('player', BigNum.from(300)),
      );
      final o = (dry as CommandOk).outcome! as UpgradesBought;
      expect(o.levels, greaterThan(0), reason: 'the test needs a buy');
      String n(int count, String one) =>
          count == 1 ? '1 $one' : '$count ${one}s';
      final levels = n(o.levels, 'upgrade level');
      final buildings = n(
        {for (final p in o.purchases) p.buildingId}.length,
        'building',
      );
      final cost = formatNumber(o.total);

      await tester.pumpWidget(_bar(c));
      await tester.tap(key('buy-max'));
      await tester.pump();
      expect(
        find.textContaining('Buy $levels on $buildings for $cost of 300'),
        findsOneWidget,
      );
      expect(
        c.state.faction('player').credits,
        BigNum.from(300),
        reason: 'not yet',
      );

      await tester.tap(key('buy-max-confirm'));
      await tester.pump();
      expect(key('buy-max-confirm'), findsNothing);
      expect(
        find.textContaining('Bought $levels on $buildings'),
        findsOneWidget,
      );
      final spent = BigNum.from(300) - c.state.faction('player').credits;
      expect(formatNumber(spent), cost, reason: 'what it showed');
    });

    testWidgets('Cancel buys nothing', (tester) async {
      final c = _controller();
      await tester.pumpWidget(_bar(c));
      await tester.tap(key('buy-max'));
      await tester.pump();
      await tester.tap(key('buy-max-cancel'));
      await tester.pump();
      expect(key('buy-max-confirm'), findsNothing);
      expect(c.state.faction('player').credits, BigNum.from(250));
    });

    testWidgets('with nothing affordable it says why, with a lock', (
      tester,
    ) async {
      final c = _controller();
      c.state.faction('player').credits = const BigNum.zero();
      await tester.pumpWidget(_bar(c));
      await tester.tap(key('buy-max'));
      await tester.pump();
      expect(key('buy-max-confirm'), findsNothing);
      expect(find.textContaining('the cheapest costs'), findsOneWidget);
      expect(find.byIcon(Icons.lock_outline), findsOneWidget);
    });

    testWidgets('its confirm fits a 360x640 phone at 2x text', (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearAllTestValues);
      final c = _controller();
      c.state.faction('player').credits = BigNum.from(1e6);
      await tester.pumpWidget(_bar(c));
      await tester.tap(key('buy-max'));
      await tester.pump();
      expect(key('buy-max-confirm'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('no overflow on a 360x640 phone at 2x text', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearAllTestValues);
    final c = _controller();
    c.state.body('kora').stock
      ..['iron_ore'] = BigNum.from(123456)
      ..['copper_ore'] = BigNum.from(98765)
      ..['steel'] = BigNum.from(45678);
    c.tickSeconds(1);

    await tester.pumpWidget(_bar(c));
    expect(tester.takeException(), isNull);
  });

  testWidgets('1e40 credits read 1e40 with no overflow', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final c = _controller();
    c.state.faction('player').credits = BigNum.parse('1e40');
    c.tickSeconds(1);

    await tester.pumpWidget(_bar(c));
    expect(_barText(tester), contains('1e40'));
    expect(tester.takeException(), isNull);
  });
}
