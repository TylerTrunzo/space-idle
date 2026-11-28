import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:game_core/game_core.dart';
import 'package:material_ui/material_ui.dart';
import 'package:space_idle/app.dart';
import 'package:space_idle/game/clock.dart';
import 'package:space_idle/game/content_source.dart';
import 'package:space_idle/game/game_controller.dart';
import 'package:space_idle/game/save_store.dart';
import 'package:space_idle/game/settings_store.dart';
import 'package:space_idle/ui/broken_save_screen.dart';
import 'package:space_idle/ui/controller_scope.dart';
import 'package:space_idle/ui/planet/planet_panel.dart';
import 'package:space_idle/ui/shell.dart';
import 'package:space_idle/ui/top_bar.dart';
import 'package:space_idle/version.dart';

final Content content = loadEmbeddedContent();
const _p = 'player';

Finder _key(String k) => find.byKey(ValueKey(k));

GameController _controllerIn(WidgetTester tester) =>
    ControllerScope.of(tester.element(find.byType(Shell)));

void main() {
  late FakeClock clock;
  setUp(() => clock = FakeClock(DateTime.utc(2026, 11, 27, 12)));

  String saved(GameState s) => jsonEncode({
    'savedAt': clock.now().millisecondsSinceEpoch,
    'save': SaveCodec.encode(s),
  });

  GameState newGame() => GameEngine(content).newGame(1);

  Future<void> boot(
    WidgetTester tester, {
    SaveStore? store,
    Size size = const Size(800, 1200),
    double textScale = 1,
    bool still = false,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    if (textScale != 1) {
      tester.platformDispatcher.textScaleFactorTestValue = textScale;
    }
    if (still) {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
    }
    addTearDown(tester.platformDispatcher.clearAllTestValues);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(
      SpaceIdleApp(
        store: store ?? MemorySaveStore(),
        clock: clock,
        settings: MemorySettingsStore(),
      ),
    );
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  /// Back after [away] to [s].
  Future<void> back(
    WidgetTester tester,
    GameState s,
    Duration away, {
    Size size = const Size(800, 1200),
    double textScale = 1,
  }) async {
    final store = MemorySaveStore(saved(s));
    clock.advance(away);
    await boot(tester, store: store, size: size, textScale: textScale);
  }

  String dialogText(WidgetTester tester) => [
    for (final t in tester.widgetList<Text>(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(Text),
      ),
    ))
      t.data ?? t.textSpan?.toPlainText() ?? '',
  ].join(' | ');

  group('the away dialog', () {
    testWidgets('it is worked out once: what it says holds still while open', (
      tester,
    ) async {
      await back(tester, newGame(), const Duration(hours: 2));
      expect(_key('away-attention-0'), findsNothing);
      // A contract hold appears in the live report while it is open.
      final c = _controllerIn(tester);
      c.run(
        const SetMegaprojectAutoCommand(
          _p,
          'orbital_station',
          goods: GoodsFeedMode.always,
        ),
      );
      c.state
          .faction(_p)
          .contracts
          .add(
            ContractState(
              id: 'c_hull',
              templateId: 'veyra_bulk',
              resourceId: 'hull_plate',
              quantity: BigNum.from(100),
              rewardCredits: BigNum.from(900),
              postedAt: c.state.time,
            ),
          );
      c.state.body('kora').stock['hull_plate'] = BigNum.from(60);
      c.tickSeconds(1);
      await tester.pump();
      expect(_key('away-attention-0'), findsNothing);
    });

    /// A Smelter with no crew and an ore store filling up: problems on
    /// Kora worth a Go.
    GameState troubled() {
      final s = newGame();
      s.body('kora').buildings.firstWhere((b) => b.id == 'b3').crew = 0;
      return s;
    }

    testWidgets('shows the headline and the credits; Go selects the body', (
      tester,
    ) async {
      await back(tester, troubled(), const Duration(hours: 2));
      expect(find.byType(AlertDialog), findsOneWidget);
      final text = dialogText(tester);
      expect(text, contains('While you were away'));
      expect(text, contains('Away 2h; +'));
      expect(textOf(tester, _key('away-net')), contains('credits'));
      expect(text, contains('Kora storage is full'));
      // The first problem with somewhere to go.
      await tester.tap(find.widgetWithText(TextButton, 'Go').first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();
      expect(find.byType(AlertDialog), findsNothing);
      expect(_controllerIn(tester).pendingAwaySummaries, isEmpty);
      expect(find.byType(PlanetPanel), findsOneWidget);
    });

    testWidgets('a claim started before a 2 h absence shows as finished', (
      tester,
    ) async {
      final s = newGame();
      s.faction(_p).credits = BigNum.from(1e6);
      GameEngine(content).apply(s, const ClaimBodyCommand(_p, 'brine', 'kora'));
      await back(tester, s, const Duration(hours: 2));
      expect(textOf(tester, _key('away-finished')), contains('Claimed Brine'));
      expect(dialogText(tester), contains('First Claim'));
    });

    testWidgets('a 30 h absence shows the capped line', (tester) async {
      await back(tester, newGame(), const Duration(hours: 30));
      expect(textOf(tester, _key('away-time')), contains('12h counted'));
    });

    testWidgets('a contract holding goods is a "needs your attention" line '
        'whose Go opens the contract', (tester) async {
      await back(tester, newGame(), const Duration(hours: 2));
      // On return: the station fed goods on its own, and a contract
      // holding Hull Plate it owes.
      final c = _controllerIn(tester);
      c.run(
        const SetMegaprojectAutoCommand(
          _p,
          'orbital_station',
          goods: GoodsFeedMode.always,
        ),
      );
      c.state
          .faction(_p)
          .contracts
          .add(
            ContractState(
              id: 'c_hull',
              templateId: 'veyra_bulk',
              resourceId: 'hull_plate',
              quantity: BigNum.from(100),
              rewardCredits: BigNum.from(900),
              postedAt: c.state.time,
            ),
          );
      c.state.body('kora').stock['hull_plate'] = BigNum.from(60);
      c.tickSeconds(1);
      // The dialog is worked out again when a new summary lands.
      clock.advance(const Duration(minutes: 30));
      await c.resume();
      await tester.pump();
      expect(c.pendingAwaySummaries, hasLength(2));
      expect(
        textOf(tester, _key('away-attention-0')),
        contains('Contract #c_hull holds'),
      );
      await tester.tap(_key('away-attention-go-0'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      final bar = tester.widget<NavigationBar>(find.byType(NavigationBar));
      expect(bar.selectedIndex, 4);
      expect(_key('contract-c_hull'), findsOneWidget);
    });

    testWidgets('360x640 at 2x text: no overflow, scrolled through', (
      tester,
    ) async {
      final s = troubled();
      s.faction(_p).credits = BigNum.from(1e6);
      GameEngine(content).apply(s, const ClaimBodyCommand(_p, 'brine', 'kora'));
      await back(
        tester,
        s,
        const Duration(hours: 30),
        size: const Size(360, 640),
        textScale: 2,
      );
      expect(tester.takeException(), isNull);
      // The bar and the strip each keep to their share of the screen.
      expect(
        tester.getSize(find.byType(TopBar)).height,
        lessThanOrEqualTo(192),
      );
      final scroll = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(Scrollable),
      );
      for (var i = 0; i < 20; i++) {
        await tester.drag(scroll.first, const Offset(0, -300));
        await tester.pump();
      }
      expect(tester.takeException(), isNull);
      expect(_key('away-ok'), findsOneWidget);
    });
  });

  group('milestone banners', () {
    testWidgets('reaching one in live play names it for 4 s', (tester) async {
      await boot(tester);
      final c = _controllerIn(tester);
      c.state.body('brine').ownerId = _p;
      c.tickSeconds(1);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(textOf(tester, _key('milestone-banner')), contains('First Claim'));
      await tester.pump(const Duration(seconds: 4));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.textContaining('First Claim'), findsNothing);
    });

    testWidgets('with reduce-motion it shows and goes without animating', (
      tester,
    ) async {
      await boot(tester, still: true);
      final c = _controllerIn(tester);
      c.state.body('brine').ownerId = _p;
      c.tickSeconds(1);
      await tester.pump();
      final fade = tester.widget<AnimatedOpacity>(
        _key('milestone-banner-fade'),
      );
      expect(fade.duration, Duration.zero);
      expect(fade.opacity, 1);
      await tester.pump(const Duration(seconds: 4));
      await tester.pump();
      expect(_key('milestone-banner'), findsNothing);
    });

    testWidgets('a new game clears a banner of the old one', (tester) async {
      await boot(tester);
      final c = _controllerIn(tester);
      c.state.body('brine').ownerId = _p;
      c.tickSeconds(1);
      await tester.pump();
      expect(_key('milestone-banner'), findsOneWidget);
      await c.newGame();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.textContaining('First Claim'), findsNothing);
    });

    testWidgets('one reached in a resume catch-up is left to the away '
        'summary', (tester) async {
      await boot(tester);
      final c = _controllerIn(tester);
      c.state.body('brine').ownerId = _p;
      clock.advance(const Duration(hours: 2));
      await c.resume();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(c.pendingAwaySummaries, isNotEmpty);
      expect(_key('milestone-banner'), findsNothing);
      expect(textOf(tester, _key('away-milestones')), contains('First Claim'));
    });

    testWidgets('one reached under the settings sheet shows once it closes', (
      tester,
    ) async {
      await boot(tester);
      final c = _controllerIn(tester);
      await tester.tap(find.byTooltip('Settings'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      c.state.body('brine').ownerId = _p;
      c.tickSeconds(1);
      await tester.pump();
      // Longer than a banner lasts, while the sheet covers it.
      await tester.pump(const Duration(seconds: 6));
      await tester.tapAt(const Offset(400, 20));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(_key('settings-sheet'), findsNothing);
      expect(textOf(tester, _key('milestone-banner')), contains('First Claim'));
      await tester.pump(const Duration(seconds: 4));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.textContaining('First Claim'), findsNothing);
    });

    testWidgets('two reached under the same sheet are both named once it '
        'closes', (tester) async {
      await boot(tester);
      final c = _controllerIn(tester);
      await tester.tap(find.byTooltip('Settings'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      c.state.body('brine').ownerId = _p;
      c.tickSeconds(1);
      await tester.pump();
      c.state.body('cinder').ownerId = _p;
      c.tickSeconds(1);
      await tester.pump();
      await tester.tapAt(const Offset(400, 20));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      final said = textOf(tester, _key('milestone-banner'));
      expect(said, contains('First Claim'));
      expect(said, contains('Second Claim'));
    });

    testWidgets('an import does not announce what it already has', (
      tester,
    ) async {
      await boot(tester);
      final c = _controllerIn(tester);
      final s = newGame()..body('brine').ownerId = _p;
      s.faction(_p).reachedMilestones.add('own_2_bodies');
      expect(await c.importSave(SaveCodec.encode(s)), isA<Imported>());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.textContaining('First Claim'), findsNothing);
    });
  });

  group('the settings sheet', () {
    Future<void> open(WidgetTester tester) async {
      await tester.tap(find.byTooltip('Settings'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
    }

    testWidgets('Copy save puts the save on the clipboard', (tester) async {
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String?;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await boot(tester);
      _controllerIn(tester).state.faction(_p).credits = BigNum.from(4321);
      await open(tester);
      await tester.tap(_key('settings-copy'));
      await tester.pump();
      expect(copied, isNotNull);
      final decoded = SaveCodec.decode(copied!, content);
      expect((decoded as SaveOk).state.faction(_p).credits, BigNum.from(4321));
      expect(_key('settings-save-text'), findsNothing);
    });

    testWidgets('a clipboard that fails shows the text to select', (
      tester,
    ) async {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            throw PlatformException(code: 'denied');
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await boot(tester);
      await open(tester);
      await tester.tap(_key('settings-copy'));
      await tester.pump();
      await tester.pump();
      final field = tester.widget<SelectableText>(_key('settings-save-text'));
      expect(field.data, _controllerIn(tester).exportSave());
    });

    testWidgets('Load save restores an exported game, after a confirm', (
      tester,
    ) async {
      final other = newGame()..faction(_p).credits = BigNum.from(12345);
      await boot(tester);
      await open(tester);
      await tester.enterText(
        _key('settings-load-field'),
        SaveCodec.encode(other),
      );
      await tester.tap(_key('settings-load'));
      await tester.pump();
      expect(
        _controllerIn(tester).state.faction(_p).credits,
        isNot(BigNum.from(12345)),
        reason: 'not before the confirm',
      );
      await tester.tap(_key('settings-load-confirm'));
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(
        _controllerIn(tester).state.faction(_p).credits,
        BigNum.from(12345),
      );
      expect(find.text('Save loaded'), findsOneWidget);
    });

    testWidgets('a load whose write fails still loads, frees the sheet and '
        'says the save is pending', (tester) async {
      final store = _WriteFails(saved(newGame()));
      await boot(tester, store: store);
      store.fail = true;
      final other = newGame()..faction(_p).credits = BigNum.from(12345);
      await open(tester);
      await tester.enterText(
        _key('settings-load-field'),
        SaveCodec.encode(other),
      );
      await tester.tap(_key('settings-load'));
      await tester.pump();
      await tester.tap(_key('settings-load-confirm'));
      await tester.pump();
      await tester.pump();
      expect(tester.takeException(), isA<StateError>(), reason: 'reported');
      expect(
        _controllerIn(tester).state.faction(_p).credits,
        BigNum.from(12345),
      );
      expect(
        textOf(tester, _key('settings-save-failed')),
        contains("couldn't be saved yet"),
      );
      final load = tester.widget<ButtonStyleButton>(_key('settings-load'));
      expect(load.onPressed, isNotNull, reason: 'not stuck busy');
    });

    testWidgets('a new game whose write fails still starts and says so', (
      tester,
    ) async {
      final store = _WriteFails(saved(newGame()));
      await boot(tester, store: store);
      _controllerIn(tester).state.faction(_p).credits = BigNum.from(99999);
      store.fail = true;
      await open(tester);
      await tester.tap(_key('settings-new-game'));
      await tester.pump();
      await tester.tap(_key('settings-new-game-confirm'));
      await tester.pump();
      await tester.pump();
      expect(tester.takeException(), isA<StateError>(), reason: 'reported');
      expect(
        _controllerIn(tester).state.faction(_p).credits,
        isNot(BigNum.from(99999)),
      );
      expect(
        textOf(tester, _key('settings-save-failed')),
        contains("couldn't be saved yet"),
      );
      final again = tester.widget<ButtonStyleButton>(_key('settings-new-game'));
      expect(again.onPressed, isNotNull, reason: 'not stuck busy');
    });

    testWidgets('Load save of garbage shows why, and changes nothing', (
      tester,
    ) async {
      await boot(tester);
      final before = _controllerIn(tester).exportSave();
      await open(tester);
      await tester.enterText(_key('settings-load-field'), 'garbage');
      await tester.tap(_key('settings-load'));
      await tester.pump();
      await tester.tap(_key('settings-load-confirm'));
      await tester.pump();
      await tester.pump();
      expect(
        textOf(tester, _key('settings-load-error')),
        startsWith("Couldn't load that save"),
      );
      expect(_controllerIn(tester).exportSave(), before);
    });

    testWidgets('New game takes two taps', (tester) async {
      await boot(tester);
      final c = _controllerIn(tester);
      c.state.faction(_p).credits = BigNum.from(99999);
      await open(tester);
      await tester.tap(_key('settings-new-game'));
      await tester.pump();
      expect(c.state.faction(_p).credits, BigNum.from(99999));
      expect(find.textContaining('Start a new game?'), findsOneWidget);
      await tester.tap(_key('settings-new-game-confirm'));
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(
        _controllerIn(tester).state.faction(_p).credits,
        isNot(BigNum.from(99999)),
      );
      expect(_key('settings-sheet'), findsNothing);
    });

    testWidgets('a support placeholder that goes nowhere, and the version', (
      tester,
    ) async {
      await boot(tester);
      await open(tester);
      final tile = tester.widget<ListTile>(_key('settings-support'));
      expect(tile.onTap, isNull);
      expect(tile.enabled, isFalse);
      expect(
        textOf(tester, _key('settings-support')),
        contains('Coming with the store release'),
      );
      expect(textOf(tester, _key('settings-about')), contains(appVersion));
    });

    testWidgets('360x640 at 2x text: no overflow, confirms open', (
      tester,
    ) async {
      await boot(tester, size: const Size(360, 640), textScale: 2);
      await open(tester);
      final scroll = find.descendant(
        of: _key('settings-sheet'),
        matching: find.byType(Scrollable),
      );
      Future<void> tap(String k) async {
        await tester.scrollUntilVisible(_key(k), 200, scrollable: scroll.first);
        await tester.pump();
        await tester.tap(_key(k));
        await tester.pump();
      }

      await tap('settings-new-game');
      await tester.scrollUntilVisible(
        _key('settings-load-field'),
        -200,
        scrollable: scroll.first,
      );
      await tester.enterText(_key('settings-load-field'), 'garbage');
      await tap('settings-load');
      for (var i = 0; i < 20; i++) {
        await tester.drag(scroll.first, const Offset(0, -200));
        await tester.pump();
      }
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('a garbage store shows the broken-save card; Start new game '
      'clears it', (tester) async {
    await boot(tester, store: MemorySaveStore('garbage'));
    expect(find.byType(BrokenSaveScreen), findsOneWidget);
    expect(find.text("Your save couldn't be loaded"), findsOneWidget);
    await tester.tap(find.text('Start new game'));
    await tester.pump();
    await tester.pump();
    expect(find.byType(BrokenSaveScreen), findsNothing);
    expect(find.byType(Shell), findsOneWidget);
  });

  test('the version matches pubspec.yaml', () {
    final line = File('pubspec.yaml')
        .readAsLinesSync()
        .firstWhere((l) => l.startsWith('version:'));
    expect(line, 'version: $appVersion+$appBuild');
  });
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

/// A slot holding [text] whose writes throw while [fail] is set.
final class _WriteFails implements SaveStore {
  _WriteFails(this.text);

  String? text;
  bool fail = false;

  @override
  Future<String?> read() async => text;

  @override
  Future<void> write(String t) async {
    if (fail) throw StateError('storage full');
    text = t;
  }
}
