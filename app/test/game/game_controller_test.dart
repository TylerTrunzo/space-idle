import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:game_core/game_core.dart';
import 'package:space_idle/game/clock.dart';
import 'package:space_idle/game/content_source.dart';
import 'package:space_idle/game/game_controller.dart';
import 'package:space_idle/game/save_store.dart';

final Content content = loadEmbeddedContent();

/// A new game's player can afford a smelter (150) but not a fusion
/// refinery (3,000) on its home body.
const _home = 'kora';
const _affordable = BuildCommand('player', _home, 'smelter');
const _tooDear = BuildCommand('player', _home, 'fusion_refinery');

GameController _controller(MemorySaveStore store, FakeClock clock) =>
    GameController(
      content: content,
      store: store,
      clock: clock,
      newGameSeed: 7,
    );

/// The save text inside the envelope [store] holds.
String _storedSave(MemorySaveStore store) =>
    (jsonDecode(store.text!) as Map<String, Object?>)['save']! as String;

/// A save slot that cannot be read, as when platform storage fails.
final class _FailingReadStore implements SaveStore {
  int writes = 0;

  @override
  Future<String?> read() async => throw StateError('disk on fire');

  @override
  Future<void> write(String text) async => writes++;
}

/// Epoch milliseconds past `DateTime`'s ±8.64e15 range (the review probe).
const _outOfRangeMs = 9999999999999999;

/// A stored envelope around a valid new game, with [savedAt] as given
/// (left out when null).
String _envelope({required Object? savedAt}) => jsonEncode({
  'savedAt': ?savedAt,
  'save': SaveCodec.encode(GameEngine(content).newGame(1)),
});

/// Starts a new game in [store] at [clock]'s time and lets it run [played]
/// seconds before it is saved, as a session that then closes.
Future<double> _playAndClose(
  MemorySaveStore store,
  FakeClock clock, {
  double played = 5,
}) async {
  final first = _controller(store, clock);
  await first.start();
  first.tickSeconds(played);
  await first.save();
  final time = first.state.time;
  first.dispose();
  return time;
}

void main() {
  late MemorySaveStore store;
  late FakeClock clock;

  setUp(() {
    store = MemorySaveStore();
    clock = FakeClock(DateTime.utc(2026, 11, 27, 12));
  });

  group('before start', () {
    test('save() before start() leaves the stored save alone', () async {
      store.text = 'garbage';
      final c = _controller(store, clock);

      await c.save();
      c.tickSeconds(60);
      await pumpEventQueue();
      expect(store.text, 'garbage');
      expect(store.writes, 0);
    });

    test('resume() before start() does nothing', () async {
      final c = _controller(store, clock);
      final before = c.state.time;
      clock.advance(const Duration(hours: 1));

      expect(await c.resume(), isNull);
      expect(c.state.time, before);
      expect(store.writes, 0);
    });

    testWidgets('the timer does nothing before start()', (tester) async {
      final c = _controller(store, clock);
      final before = c.state.time;

      c.startTimer();
      clock.advance(const Duration(minutes: 5));
      await tester.pump(const Duration(seconds: 1));
      expect(c.state.time, before);
      expect(c.pendingAwaySummary, isNull);
      c.dispose();
    });

    test('start() twice reads the store once and gives one result', () async {
      final c = _controller(store, clock);

      final first = c.start();
      final second = c.start();
      expect(identical(await first, await second), isTrue);
      expect(store.reads, 1);
      expect(store.writes, 1);
    });

    test('a store whose read throws gives LoadFailed and no write', () async {
      final failing = _FailingReadStore();
      final c = GameController(
        content: content,
        store: failing,
        clock: clock,
        newGameSeed: 7,
      );

      final result = await c.start();
      expect(
        result,
        isA<LoadFailed>().having(
          (r) => r.reason,
          'reason',
          contains('disk on fire'),
        ),
      );
      await c.save();
      c.tickSeconds(60);
      await pumpEventQueue();
      expect(failing.writes, 0);
    });
  });

  group('start', () {
    test('an empty store starts a new game and writes it', () async {
      final c = _controller(store, clock);

      expect(await c.start(), isA<StartedNew>());
      expect(store.writes, 1);
      expect(_storedSave(store), SaveCodec.encode(c.state));
      expect(c.pendingAwaySummary, isNull);
    });

    test('the envelope records savedAt from the injected clock', () async {
      await _controller(store, clock).start();

      final envelope = jsonDecode(store.text!) as Map<String, Object?>;
      expect(envelope['savedAt'], clock.now().millisecondsSinceEpoch);
    });

    test('a save 2 h old loads and catches up 7200 s', () async {
      final savedTime = await _playAndClose(store, clock);
      clock.advance(const Duration(hours: 2));

      final c = _controller(store, clock);
      expect(await c.start(), isA<Loaded>());
      expect(c.pendingAwaySummary?.secondsSimulated, 7200);
      expect(c.state.time, closeTo(savedTime + 7200, 1e-6));
    });

    test('30 h away simulates only the 12 h offline cap', () async {
      final savedTime = await _playAndClose(store, clock);
      clock.advance(const Duration(hours: 30));

      final c = _controller(store, clock);
      await c.start();
      expect(c.pendingAwaySummary?.secondsSimulated, 43200);
      expect(c.state.time, closeTo(savedTime + 43200, 1e-6));
    });

    test(
      'a clock moved back 1 h simulates nothing and does not throw',
      () async {
        final savedTime = await _playAndClose(store, clock);
        clock.advance(const Duration(hours: -1));

        final c = _controller(store, clock);
        expect(await c.start(), isA<Loaded>());
        expect(c.state.time, savedTime);
        expect(c.pendingAwaySummary, isNull);
      },
    );

    test('under 60 s away catches up without an away summary', () async {
      final savedTime = await _playAndClose(store, clock);
      clock.advance(const Duration(seconds: 30));

      final c = _controller(store, clock);
      await c.start();
      expect(c.state.time, closeTo(savedTime + 30, 1e-6));
      expect(c.pendingAwaySummary, isNull);
    });

    test('clearAwaySummary drops the summary and notifies', () async {
      await _playAndClose(store, clock);
      clock.advance(const Duration(hours: 2));
      final c = _controller(store, clock);
      await c.start();
      var notified = 0;
      c.addListener(() => notified++);

      c.clearAwaySummary();
      expect(c.pendingAwaySummary, isNull);
      expect(notified, 1);
    });

    test(
      'garbage in the store fails to load and is kept until newGame',
      () async {
        store.text = 'not a save';
        final c = _controller(store, clock);

        final result = await c.start();
        expect(
          result,
          isA<LoadFailed>().having(
            (r) => r.brokenText,
            'brokenText',
            'not a save',
          ),
        );
        expect((result as LoadFailed).reason, isNotEmpty);
        // A new game runs in memory, but nothing overwrites the broken save.
        c.tickSeconds(40);
        await c.save();
        expect(store.text, 'not a save');
        expect(store.writes, 0);

        await c.newGame();
        expect(store.writes, 1);
        expect(_storedSave(store), SaveCodec.encode(c.state));
      },
    );

    test(
      'an envelope holding a save the codec rejects fails to load',
      () async {
        store.text = jsonEncode({'savedAt': 0, 'save': '{"saveVersion": 999}'});

        final result = await _controller(store, clock).start();
        expect(result, isA<LoadFailed>());
        expect(store.writes, 0);
      },
    );

    test('a savedAt outside the DateTime range fails to load', () async {
      store.text = _envelope(savedAt: _outOfRangeMs);

      final result = await _controller(store, clock).start();
      expect(
        result,
        isA<LoadFailed>().having(
          (r) => r.reason,
          'reason',
          contains('savedAt'),
        ),
      );
      expect(store.writes, 0);
    });
  });

  group('commands', () {
    test('a failed command sets lastError and changes nothing', () async {
      final c = _controller(store, clock);
      await c.start();
      final before = SaveCodec.encode(c.state);
      var notified = 0;
      c.addListener(() => notified++);

      expect(c.run(_tooDear), isA<CommandFailed>());
      expect(c.lastError, isNotNull);
      expect(SaveCodec.encode(c.state), before);
      expect(notified, 1);
    });

    test('a successful command clears lastError and notifies', () async {
      final c = _controller(store, clock);
      await c.start();
      c.run(_tooDear);
      var notified = 0;
      c.addListener(() => notified++);

      expect(c.run(_affordable), isA<CommandOk>());
      expect(c.lastError, isNull);
      expect(notified, 1);
      expect(
        c.state.bodies
            .singleWhere((b) => b.id == _home)
            .buildings
            .where((b) => b.defId == 'smelter'),
        isNotEmpty,
      );
    });

    test('flow is rebuilt after a command', () async {
      final c = _controller(store, clock);
      await c.start();
      final before = c.flow;

      c.run(_affordable);
      expect(identical(c.flow, before), isFalse);
      expect(c.playerId, 'player');
    });
  });

  test('a claim started before closing completes during catch-up '
      '(Review Focus 6)', () async {
    final first = _controller(store, clock);
    await first.start();
    // Fixture: enough credits and outpost kits for the first claim.
    first.state.faction('player').credits = BigNum.from(1e7);
    first.state.body(_home).stock['outpost_kit'] = BigNum.from(100);
    final claim = first.run(
      const ClaimBodyCommand('player', 'hollow_reach', _home),
    );
    expect(claim, isA<CommandOk>(), reason: first.lastError);
    final project = first.engine.projectsFor(first.state, 'player').single;
    final left = project.finishAt - first.state.time;
    expect(left, greaterThan(GameController.awaySummarySeconds));
    await first.save();
    first.dispose();

    clock.advance(Duration(seconds: left.ceil() + 60));
    final c = _controller(store, clock);
    expect(await c.start(), isA<Loaded>());

    final done = c.pendingAwaySummary!.projectsCompleted;
    expect(
      done.map((p) => (p.kind, p.targetId)),
      contains((ProjectKind.claim, 'hollow_reach')),
    );
    expect(c.state.body('hollow_reach').ownerId, 'player');
    // Its countdown is gone, not stuck at or below zero.
    expect(c.engine.projectsFor(c.state, 'player'), isEmpty);
  });

  group('time', () {
    test('tickSeconds(10) advances state.time by 10 and notifies', () async {
      final c = _controller(store, clock);
      await c.start();
      final before = c.state.time;
      var notified = 0;
      c.addListener(() => notified++);

      c.tickSeconds(10);
      expect(c.state.time, closeTo(before + 10, 1e-9));
      expect(notified, 1);
    });

    test('tickSeconds ignores zero, negative and non-finite seconds', () async {
      final c = _controller(store, clock);
      await c.start();
      final before = c.state.time;

      for (final s in [0.0, -5.0, double.nan, double.infinity]) {
        c.tickSeconds(s);
      }
      expect(c.state.time, before);
    });

    test('30 s of ticks autosaves exactly once', () async {
      final c = _controller(store, clock);
      await c.start();
      final writes = store.writes;

      c.tickSeconds(10);
      c.tickSeconds(10);
      await pumpEventQueue();
      expect(store.writes, writes);

      c.tickSeconds(10);
      await pumpEventQueue();
      expect(store.writes, writes + 1);

      c.tickSeconds(10);
      await pumpEventQueue();
      expect(store.writes, writes + 1);
    });

    test('resume catches up from the last save and saves', () async {
      final c = _controller(store, clock);
      await c.start();
      await c.save();
      final before = c.state.time;
      final writes = store.writes;
      clock.advance(const Duration(minutes: 10));

      final summary = await c.resume();
      expect(summary?.secondsSimulated, 600);
      expect(c.pendingAwaySummary, same(summary));
      expect(c.state.time, closeTo(before + 600, 1e-6));
      expect(store.writes, writes + 1);
    });

    test('resume after a clock moved back simulates nothing', () async {
      final c = _controller(store, clock);
      await c.start();
      final before = c.state.time;
      clock.advance(const Duration(hours: -3));

      expect(await c.resume(), isNull);
      expect(c.state.time, before);
    });

    testWidgets('the timer ticks by the wall time between fires', (
      tester,
    ) async {
      final c = _controller(store, clock);
      await tester.runAsync(c.start);
      final before = c.state.time;

      c.startTimer();
      clock.advance(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      clock.advance(const Duration(seconds: 2));
      await tester.pump(const Duration(seconds: 1));
      expect(c.state.time, closeTo(before + 3, 1e-9));

      c.stopTimer();
      clock.advance(const Duration(seconds: 5));
      await tester.pump(const Duration(seconds: 5));
      expect(c.state.time, closeTo(before + 3, 1e-9));
      c.dispose();
    });

    testWidgets('a long gap between timer fires is an away catch-up', (
      tester,
    ) async {
      final c = _controller(store, clock);
      await tester.runAsync(c.start);
      final before = c.state.time;

      c.startTimer();
      clock.advance(const Duration(minutes: 5));
      await tester.pump(const Duration(seconds: 1));
      expect(c.state.time, closeTo(before + 300, 1e-6));
      expect(c.pendingAwaySummary?.secondsSimulated, 300);
      c.dispose();
    });
  });

  group('export and import', () {
    test('a round trip restores the exported state exactly', () async {
      final c = _controller(store, clock);
      await c.start();
      c.run(_affordable);
      c.tickSeconds(12);
      final exported = c.exportSave();

      c.tickSeconds(100);
      expect(await c.importSave(exported), isA<Imported>());
      expect(SaveCodec.encode(c.state), exported);
      expect(_storedSave(store), exported);
    });

    test('importing an envelope whose savedAt is out of range fails', () async {
      final c = _controller(store, clock);
      await c.start();
      final before = SaveCodec.encode(c.state);

      final result = await c.importSave(_envelope(savedAt: _outOfRangeMs));
      expect(
        result,
        isA<ImportFailed>().having(
          (r) => r.reason,
          'reason',
          contains('savedAt'),
        ),
      );
      expect(SaveCodec.encode(c.state), before);
    });

    test('import also takes a whole stored envelope', () async {
      final c = _controller(store, clock);
      await c.start();
      c.tickSeconds(12);
      await c.save();
      final envelope = store.text!;
      final saved = SaveCodec.encode(c.state);

      c.tickSeconds(100);
      expect(await c.importSave(envelope), isA<Imported>());
      expect(SaveCodec.encode(c.state), saved);
    });

    test('importing garbage fails and keeps the game', () async {
      final c = _controller(store, clock);
      await c.start();
      final before = SaveCodec.encode(c.state);
      final writes = store.writes;

      final result = await c.importSave('nope');
      expect(
        result,
        isA<ImportFailed>().having((r) => r.reason, 'reason', isNotEmpty),
      );
      expect(SaveCodec.encode(c.state), before);
      expect(store.writes, writes);
    });

    test('a successful import unlocks saving after a failed load', () async {
      store.text = 'broken';
      final c = _controller(store, clock);
      await c.start();
      final good = GameEngine(content).newGame(3);

      expect(await c.importSave(SaveCodec.encode(good)), isA<Imported>());
      expect(_storedSave(store), SaveCodec.encode(c.state));
    });
  });

  test('newGame replaces the game, clears messages and saves', () async {
    final c = _controller(store, clock);
    await c.start();
    c.tickSeconds(50);
    c.run(_tooDear);
    final writes = store.writes;

    await c.newGame();
    expect(c.state.time, GameEngine(content).newGame(7).time);
    expect(c.lastError, isNull);
    expect(store.writes, writes + 1);
  });
}
