import 'dart:convert';

import 'package:game_core/game_core.dart';
import 'package:game_core/src/sim/contracts.dart' show incomeBasis;
import 'package:game_core/src/sim/megaproject_auto.dart';
import 'package:test/test.dart';

import '../state/helpers.dart';

BigNum n(num v) => BigNum.from(v);

String encode(GameState s) => jsonEncode(s.toJson());

void main() {
  final content = shippedContent();
  final e = GameEngine(content);

  CommandOk ok(GameState s, Command cmd) {
    final r = e.apply(s, cmd);
    expect(r, isA<CommandOk>(), reason: r is CommandFailed ? r.message : '');
    return r as CommandOk;
  }

  void fails(GameState s, Command cmd, CommandError error) {
    final before = encode(s);
    final r = e.apply(s, cmd);
    expect(r, isA<CommandFailed>().having((f) => f.error, 'error', error));
    expect(encode(s), before);
  }

  group('setMegaprojectAuto', () {
    test('sets, changes and clears a megaproject\'s auto-delivery', () {
      final s = e.newGame(1);
      final auto = s.faction('player').megaprojectAuto;
      final r = ok(
        s,
        const SetMegaprojectAutoCommand(
          'player',
          'orbital_station',
          goods: GoodsFeedMode.always,
          credits: true,
        ),
      );
      expect(
        r.outcome,
        isA<MegaprojectAutoSet>()
            .having((o) => o.megaprojectId, 'megaprojectId', 'orbital_station')
            .having((o) => o.goods, 'goods', GoodsFeedMode.always)
            .having((o) => o.credits, 'credits', isTrue)
            .having((o) => o.bodyId, 'bodyId', isNull),
      );
      expect(auto['orbital_station']!.goods, GoodsFeedMode.always);
      expect(auto['orbital_station']!.credits, isTrue);
      ok(
        s,
        const SetMegaprojectAutoCommand(
          'player',
          'mass_driver',
          goods: GoodsFeedMode.always,
        ),
      );
      ok(
        s,
        const SetMegaprojectAutoCommand(
          'player',
          'orbital_station',
          credits: true,
        ),
      );
      expect(auto.keys, ['orbital_station', 'mass_driver']);
      expect(auto['orbital_station']!.goods, GoodsFeedMode.off);
      expect(auto['orbital_station']!.credits, isTrue);
      expect(auto['mass_driver']!.credits, isFalse);
      // Neither goods nor credits: the setting goes.
      ok(s, const SetMegaprojectAutoCommand('player', 'mass_driver'));
      expect(auto.keys, ['orbital_station']);
    });

    test('a locked megaproject can be set up ahead of time', () {
      final s = e.newGame(1);
      ok(
        s,
        const SetMegaprojectAutoCommand(
          'player',
          'mass_driver',
          goods: GoodsFeedMode.always,
        ),
      );
      expect(
        s.faction('player').megaprojectAuto['mass_driver']!.goods,
        GoodsFeedMode.always,
      );
    });

    test('refuses an unknown megaproject and an unknown faction', () {
      final s = e.newGame(1);
      fails(
        s,
        const SetMegaprojectAutoCommand(
          'player',
          'dyson',
          goods: GoodsFeedMode.always,
        ),
        CommandError.unknownDef,
      );
      fails(
        s,
        const SetMegaprojectAutoCommand(
          'ghost',
          'orbital_station',
          goods: GoodsFeedMode.always,
        ),
        CommandError.unknownFaction,
      );
    });

    test('the auto-pay reserve is one for the faction, 0 or more', () {
      final s = e.newGame(1);
      final f = s.faction('player');
      expect(f.autoPayReserve, const BigNum.zero());
      final r = ok(s, SetAutoPayReserveCommand('player', n(500)));
      expect(
        r.outcome,
        isA<AutoPayReserveSet>().having((o) => o.reserve, 'reserve', n(500)),
      );
      expect(f.autoPayReserve, n(500));
      fails(
        s,
        SetAutoPayReserveCommand('player', n(-1)),
        CommandError.invalidAmount,
      );
      fails(
        s,
        SetAutoPayReserveCommand('ghost', n(1)),
        CommandError.unknownFaction,
      );
    });

    test('round-trips through JSON', () {
      for (final cmd in [
        const SetMegaprojectAutoCommand(
          'player',
          'orbital_station',
          goods: GoodsFeedMode.always,
          credits: true,
        ),
        const SetMegaprojectAutoCommand('player', 'mass_driver'),
        SetAutoPayReserveCommand('player', n(5e6)),
      ]) {
        final back = Command.fromJson(
          jsonDecode(jsonEncode(cmd.toJson())) as Map<String, Object?>,
        );
        expect(back.runtimeType, cmd.runtimeType);
        expect(back.toJson(), cmd.toJson());
      }
    });
  });

  group('the goods mode and credit weight', () {
    test('are set, kept and shown in the outcome', () {
      final s = e.newGame(1);
      final r = ok(
        s,
        const SetMegaprojectAutoCommand(
          'player',
          'orbital_station',
          goods: GoodsFeedMode.nearReady,
          credits: true,
          creditWeight: 3,
        ),
      );
      expect(
        r.outcome,
        isA<MegaprojectAutoSet>()
            .having((o) => o.goods, 'goods', GoodsFeedMode.nearReady)
            .having((o) => o.credits, 'credits', isTrue)
            .having((o) => o.creditWeight, 'creditWeight', 3),
      );
      final a = s.faction('player').megaprojectAuto['orbital_station']!;
      expect(a.goods, GoodsFeedMode.nearReady);
      expect(a.credits, isTrue);
      expect(a.creditWeight, 3);
      // The defaults: no goods, no credits, weight 1; nothing left set.
      const plain = SetMegaprojectAutoCommand('player', 'mass_driver');
      expect(plain.goods, GoodsFeedMode.off);
      expect(plain.credits, isFalse);
      expect(plain.creditWeight, 1);
      ok(s, plain);
      expect(s.faction('player').megaprojectAuto.keys, ['orbital_station']);
      expect(s.faction('player').megaprojectAutoSet, {
        'orbital_station',
        'mass_driver',
      });
    });

    test('a weight outside 0-10 is refused, changing nothing', () {
      final s = e.newGame(1);
      for (final w in [-1, 11, 100]) {
        fails(
          s,
          SetMegaprojectAutoCommand(
            'player',
            'orbital_station',
            credits: true,
            creditWeight: w,
          ),
          CommandError.invalidAmount,
        );
      }
      for (final w in [0, 10]) {
        ok(
          s,
          SetMegaprojectAutoCommand(
            'player',
            'orbital_station',
            credits: true,
            creditWeight: w,
          ),
        );
      }
    });

    test('a command written with goods as true or false reads as always or '
        'off, at weight 1', () {
      for (final (goods, mode) in [
        (true, GoodsFeedMode.always),
        (false, GoodsFeedMode.off),
      ]) {
        final cmd =
            Command.fromJson({
                  'cmd': 'setMegaprojectAuto',
                  'factionId': 'player',
                  'megaprojectId': 'orbital_station',
                  'goods': goods,
                  'credits': true,
                })
                as SetMegaprojectAutoCommand;
        expect(cmd.goods, mode);
        expect(cmd.credits, isTrue);
        expect(cmd.creditWeight, 1);
      }
      expect(
        () => Command.fromJson({
          'cmd': 'setMegaprojectAuto',
          'factionId': 'player',
          'megaprojectId': 'orbital_station',
          'goods': 'sometimes',
        }),
        throwsFormatException,
      );
    });

    test('changing the weight of a stage being fed near ready keeps it '
        'fed; turning the goods off ends it', () {
      final s = e.newGame(1);
      final f = s.faction('player');
      ok(
        s,
        const SetMegaprojectAutoCommand(
          'player',
          'orbital_station',
          goods: GoodsFeedMode.nearReady,
        ),
      );
      f.megaprojectAuto['orbital_station'] = f
          .megaprojectAuto['orbital_station']!
          .feeding(0);
      ok(
        s,
        const SetMegaprojectAutoCommand(
          'player',
          'orbital_station',
          goods: GoodsFeedMode.nearReady,
          credits: true,
          creditWeight: 2,
        ),
      );
      expect(f.megaprojectAuto['orbital_station']!.feedingLevel, 0);
      ok(
        s,
        const SetMegaprojectAutoCommand(
          'player',
          'orbital_station',
          goods: GoodsFeedMode.always,
          credits: true,
        ),
      );
      expect(f.megaprojectAuto['orbital_station']!.feedingLevel, isNull);
    });
  });

  group('saves with auto-delivery', () {
    GameState withAuto() {
      final s = e.newGame(1);
      ok(
        s,
        const SetMegaprojectAutoCommand(
          'player',
          'orbital_station',
          goods: GoodsFeedMode.always,
          credits: true,
        ),
      );
      ok(
        s,
        const SetMegaprojectAutoCommand(
          'player',
          'mass_driver',
          goods: GoodsFeedMode.always,
        ),
      );
      ok(s, SetAutoPayReserveCommand('player', n(250)));
      return s;
    }

    test('round-trip and copy', () {
      final s = withAuto();
      final back =
          (SaveCodec.decode(SaveCodec.encode(s), content) as SaveOk).state;
      expect(encode(back), encode(s));
      expect(back.faction('player').autoPayReserve, n(250));
      final copy = s.copy();
      expect(encode(copy), encode(s));
      copy.faction('player')
        ..megaprojectAuto.clear()
        ..autoPayReserve = n(1);
      expect(s.faction('player').megaprojectAuto, hasLength(2));
      expect(s.faction('player').autoPayReserve, n(250));
    });

    test('an older save without it has none', () {
      final m = jsonDecode(encode(withAuto())) as Map<String, Object?>;
      for (final f in (m['factions']! as List).cast<Map<String, Object?>>()) {
        f
          ..remove('megaprojectAuto')
          ..remove('autoPayReserve');
      }
      final r = SaveCodec.decode(jsonEncode(m), content);
      expect(r, isA<SaveOk>(), reason: r is SaveError ? r.message : '');
      final f = (r as SaveOk).state.faction('player');
      expect(f.megaprojectAuto, isEmpty);
      expect(f.autoPayReserve, const BigNum.zero());
    });

    Map<String, Object?> playerOf(Map<String, Object?> m) =>
        (m['factions']! as List).cast<Map<String, Object?>>().first;

    test('a save with a reserve per megaproject feeds credits to those '
        'that had one, above the lowest', () {
      final m = jsonDecode(encode(withAuto())) as Map<String, Object?>;
      playerOf(m)
        ..remove('autoPayReserve')
        ..['megaprojectAuto'] = {
          'orbital_station': {'goods': true, 'creditReserve': '900'},
          'mass_driver': {'goods': false, 'creditReserve': '300'},
        };
      final f = (SaveCodec.decode(jsonEncode(m), content) as SaveOk).state
          .faction('player');
      expect(f.megaprojectAuto['orbital_station']!.credits, isTrue);
      expect(f.megaprojectAuto['mass_driver']!.credits, isTrue);
      expect(f.autoPayReserve, n(300));
    });

    test('an unknown megaproject is an unknown id', () {
      final m = jsonDecode(encode(withAuto())) as Map<String, Object?>;
      (playerOf(m)['megaprojectAuto']! as Map)['dyson'] = {'goods': true};
      final r = SaveCodec.decode(jsonEncode(m), content);
      expect((r as SaveError).kind, SaveErrorKind.unknownContentId);
    });

    test('an auto-pay reserve that is not an encoded number is refused, '
        'not read as an older save', () {
      for (final bad in [5, true, 'lots', <String, Object?>{}]) {
        final m = jsonDecode(encode(withAuto())) as Map<String, Object?>;
        playerOf(m)['autoPayReserve'] = bad;
        final r = SaveCodec.decode(jsonEncode(m), content);
        expect(r, isA<SaveError>(), reason: '$bad');
      }
    });

    test('a negative auto-pay reserve is refused', () {
      final m = jsonDecode(encode(withAuto())) as Map<String, Object?>;
      playerOf(m)['autoPayReserve'] = '-1';
      final r = SaveCodec.decode(jsonEncode(m), content);
      expect((r as SaveError).kind, SaveErrorKind.invalidValue);
      expect(r.message, contains('auto-pay reserve'));
    });

    test('the goods mode, weight and a stage being fed survive save and '
        'load, and copies', () {
      final s = e.newGame(1);
      ok(
        s,
        const SetMegaprojectAutoCommand(
          'player',
          'orbital_station',
          goods: GoodsFeedMode.nearReady,
          credits: true,
          creditWeight: 4,
        ),
      );
      final f = s.faction('player');
      f
        ..megaprojectAuto['orbital_station'] = f
            .megaprojectAuto['orbital_station']!
            .feeding(0)
        ..incomeMark = (time: 0, sales: n(1234));
      final back =
          (SaveCodec.decode(SaveCodec.encode(s), content) as SaveOk).state;
      expect(encode(back), encode(s));
      final a = back.faction('player').megaprojectAuto['orbital_station']!;
      expect(
        (a.goods, a.credits, a.creditWeight, a.feedingLevel),
        (GoodsFeedMode.nearReady, true, 4, 0),
      );
      expect(back.faction('player').incomeMark, (time: 0.0, sales: n(1234)));
      expect(encode(s.copy()), encode(s));
    });

    test('an older save\'s goods true reads as always, its credits at '
        'weight 1, and what it set counts as chosen', () {
      final m = jsonDecode(encode(withAuto())) as Map<String, Object?>;
      playerOf(m)
        ..remove('megaprojectAutoSet')
        ..['megaprojectAuto'] = {
          'orbital_station': {'goods': true, 'credits': false},
          'mass_driver': {'goods': false, 'credits': true},
        };
      final r = SaveCodec.decode(jsonEncode(m), content);
      expect(r, isA<SaveOk>(), reason: r is SaveError ? r.message : '');
      final f = (r as SaveOk).state.faction('player');
      final station = f.megaprojectAuto['orbital_station']!;
      final driver = f.megaprojectAuto['mass_driver']!;
      expect(station.goods, GoodsFeedMode.always);
      expect(station.credits, isFalse);
      expect(driver.goods, GoodsFeedMode.off);
      expect((driver.credits, driver.creditWeight), (true, 1));
      // An explicit credits-off survives the load: the station counts as
      // chosen not to fund.
      expect(f.megaprojectAutoSet, {'orbital_station', 'mass_driver'});
      expect(f.incomeMark, isNull);
    });

    test('a setting for a megaproject not in the chosen set is refused', () {
      final m = jsonDecode(encode(withAuto())) as Map<String, Object?>;
      playerOf(m)['megaprojectAutoSet'] = ['orbital_station'];
      final r = SaveCodec.decode(jsonEncode(m), content);
      expect((r as SaveError).kind, SaveErrorKind.invalidValue);
      expect(r.message, contains('mass_driver'));
    });

    test('a weight outside 0-10, an unknown mode or a bad stage being fed '
        'is refused', () {
      for (final bad in <Map<String, Object?>>[
        {'goods': 'always', 'credits': true, 'creditWeight': 11},
        {'goods': 'always', 'credits': true, 'creditWeight': -1},
        {'goods': 'whenever'},
        {'goods': 'nearReady', 'feeding': -1},
        {'goods': 'nearReady', 'feeding': SaveCodec.maxMegaprojectLevel + 1},
      ]) {
        final m = jsonDecode(encode(withAuto())) as Map<String, Object?>;
        (playerOf(m)['megaprojectAuto']! as Map)['orbital_station'] = bad;
        final r = SaveCodec.decode(jsonEncode(m), content);
        expect(r, isA<SaveError>(), reason: '$bad');
      }
    });

    test('an income mark from the future or below zero is refused', () {
      for (final bad in [
        {'time': 1e9, 'sales': '0'},
        {'time': 0, 'sales': '-5'},
        {'time': -1, 'sales': '0'},
      ]) {
        final m = jsonDecode(encode(withAuto())) as Map<String, Object?>;
        playerOf(m)['incomeMark'] = bad;
        final r = SaveCodec.decode(jsonEncode(m), content);
        expect(r, isA<SaveError>(), reason: '$bad');
      }
    });

    test('a setting that is not an object is malformed', () {
      final m = jsonDecode(encode(withAuto())) as Map<String, Object?>;
      (playerOf(m)['megaprojectAuto']! as Map)['orbital_station'] = 5;
      final r = SaveCodec.decode(jsonEncode(m), content);
      expect(r, isA<SaveError>());
    });
  });

  group('auto-delivery', () {
    // These tests feed the Mass Driver Kora's starting steel, so they run
    // on the shipped content with steel added to its cost, whatever the
    // shipped cost asks for.
    final content = _withDriverSteel();
    final e = GameEngine(content);
    final driver = content.megaprojects['mass_driver']!;

    CommandOk ok(GameState s, Command cmd) {
      final r = e.apply(s, cmd);
      expect(r, isA<CommandOk>(), reason: r is CommandFailed ? r.message : '');
      return r as CommandOk;
    }

    /// Feeds [m] goods always when [goods] (or as [mode] says), and
    /// credits above the shared [reserve] at [weight] when one is given.
    void feed(
      GameState s,
      String m,
      bool goods,
      BigNum? reserve, {
      GoodsFeedMode? mode,
      int weight = 1,
    }) {
      ok(
        s,
        SetMegaprojectAutoCommand(
          'player',
          m,
          goods: mode ?? (goods ? GoodsFeedMode.always : GoodsFeedMode.off),
          credits: reserve != null,
          creditWeight: weight,
        ),
      );
      if (reserve != null) ok(s, SetAutoPayReserveCommand('player', reserve));
    }

    /// A new game at Orbital Station level 2, past where the Mass Driver
    /// opens, with no contracts on the board and none due, and
    /// [goods]/[reserve] auto-delivery to the Mass Driver.
    GameState open({bool goods = true, BigNum? reserve}) {
      final s = e.newGame(1);
      final f = s.faction('player');
      f.megaprojectLevels['orbital_station'] = 2;
      f.contracts.clear();
      f.contractRefillAt
        ..clear()
        ..addAll(List.filled(RulesDef.contractSlots, 1e12));
      feed(s, 'mass_driver', goods, reserve);
      return s;
    }

    Map<String, BigNum> progress(GameState s) =>
        s.faction('player').megaprojectProgress['mass_driver'] ?? const {};

    test('delivers what each body holds above its keep, once a game '
        'minute', () {
      final s = open();
      s.body('kora').stock['steel'] = n(500.7);
      // Not across a whole minute: nothing.
      s.time = 10;
      expect(stepMegaprojectAuto(s, content, 30), isEmpty);
      expect(progress(s), isEmpty);
      // Across one: the whole units above the keep (nothing uses steel on
      // Kora, no rule, no contract).
      final got = stepMegaprojectAuto(s, content, 60);
      expect(got['player']!['mass_driver'], {'steel': n(500)});
      expect(progress(s), {'steel': n(500)});
      expect(s.body('kora').stock['steel']!.toDouble(), closeTo(0.7, 1e-9));
    });

    test('leaves the local use, keepAtLeast and open contract needs', () {
      final s = open();
      final f = s.faction('player');
      final kora = s.body('kora');
      // A plate press uses 3 steel per 8 s: 22.5 over a 60 s step.
      kora.buildings.add(
        BuildingState(id: 'pp', defId: 'plate_press', crew: 1),
      );
      kora.stock['steel'] = n(1000);
      ok(s, SetAutoSellCommand('player', 'kora', 'steel', n(100)));
      f.contracts.add(
        ContractState(
          id: 'c1',
          templateId: content.contractTemplates.keys.first,
          resourceId: 'steel',
          quantity: n(250),
          delivered: n(50),
          rewardCredits: n(1),
          postedAt: 0,
        ),
      );
      f.contractRefillAt.removeLast();
      stepMegaprojectAuto(s, content, 60);
      // 1000 - (100 + 22.5 + 200), in whole units.
      expect(progress(s), {'steel': n(677)});
    });

    test('a contract need stays on bodies with no rule for it', () {
      final s = open();
      final f = s.faction('player');
      // Brine is the faction's too, with steel and no rule on it.
      s.body('brine').ownerId = 'player';
      s.body('brine').stock['steel'] = n(150);
      s.body('kora').stock['steel'] = n(100);
      f.contracts.add(
        ContractState(
          id: 'c1',
          templateId: content.contractTemplates.keys.first,
          resourceId: 'steel',
          quantity: n(200),
          rewardCredits: n(1),
          postedAt: 0,
        ),
      );
      f.contractRefillAt.removeLast();
      stepMegaprojectAuto(s, content, 60);
      final left =
          s.body('kora').stock['steel']! + s.body('brine').stock['steel']!;
      expect(left.toDouble(), closeTo(200, 1e-9));
      expect(progress(s), {'steel': n(50)});
    });

    test('pays no credits without a reserve, and only above one', () {
      final s = open();
      final f = s.faction('player')..credits = n(5000);
      stepMegaprojectAuto(s, content, 60);
      stepMegaprojectCredits(s, content, 60);
      expect(f.credits, n(5000));
      feed(s, 'mass_driver', false, n(1200));
      f.credits = n(5000.5);
      s.time = 60;
      // Goods go in before the market, credits after it.
      expect(stepMegaprojectAuto(s, content, 60), isEmpty);
      expect(f.credits, n(5000.5));
      final got = stepMegaprojectCredits(s, content, 60);
      expect(got['player']!['mass_driver'], {'credits': n(3800)});
      expect(f.credits.toDouble(), closeTo(1200.5, 1e-9));
      // At the reserve, nothing more; and none between minutes.
      s.time = 120;
      expect(stepMegaprojectCredits(s, content, 60), isEmpty);
      f.credits = n(5000);
      s.time = 181;
      expect(stepMegaprojectCredits(s, content, 30), isEmpty);
    });

    test('starts the stage it pays for, then pays for the next, which '
        'waits', () {
      final s = open(reserve: n(0));
      final f = s.faction('player')..credits = n(1e12);
      for (final MapEntry(key: id, value: v) in megaprojectCost(
        content,
        driver,
        0,
      ).entries) {
        if (id != 'credits') s.body('kora').stock[id] = v.mulDouble(10);
      }
      stepMegaprojectAuto(s, content, 60);
      stepMegaprojectCredits(s, content, 60);
      final stage = megaprojectStageOf(s, 'player', 'mass_driver');
      expect(stage, isNotNull);
      // The credits go on to the next stage at once, its goods at the next
      // minute, as goods go in before the market and credits after it.
      expect(progress(s), {
        'credits': megaprojectCost(content, driver, 1)['credits'],
      });
      s.time = 60;
      stepMegaprojectAuto(s, content, 60);
      expect(megaprojectStageQueued(s, content, 'player', driver), isTrue);
      expect(progress(s), megaprojectCost(content, driver, 1));
      // Nothing more goes in while the paid stage waits.
      final credits = f.credits;
      s.time = 120;
      expect(stepMegaprojectAuto(s, content, 60), isEmpty);
      expect(stepMegaprojectCredits(s, content, 60), isEmpty);
      expect(f.credits, credits);
      // Once the first is done, the second starts and deliveries go on.
      e.advance(s, stage!.finishAt - s.time + 120);
      expect(f.megaprojectLevels['mass_driver'], 1);
      expect(megaprojectStageOf(s, 'player', 'mass_driver'), isNotNull);
      expect(progress(s).keys, isNotEmpty);
      expect(f.credits < credits, isTrue);
    });

    test('a stage it starts runs from the game minute, whatever the step', () {
      ProjectState started(double from, double step) {
        final s = open(reserve: n(0));
        s.time = from;
        s.faction('player')
          ..credits = n(1e12)
          ..megaprojectProgress['mass_driver'] = {
            for (final MapEntry(key: id, value: v) in megaprojectCost(
              content,
              driver,
              0,
            ).entries)
              if (id != 'credits') id: v,
          };
        e.advance(s, 120, maxStep: step);
        return megaprojectStageOf(s, 'player', 'mass_driver')!;
      }

      for (final (from, step) in [(0.0, 1.0), (0.0, 60.0), (30.0, 60.0)]) {
        final p = started(from, step);
        expect(p.startedAt, 60, reason: '$from, $step');
        expect(p.finishAt, 60 + megaprojectStageSeconds(driver, 0));
      }
    });

    test('a stage that ends within a step is done before the next is paid '
        'for, so the next starts at the same minute at 1 s and 60 s', () {
      // Level 0 under way, ending at 7230, with level 1's goods on hand
      // and credits paid in on their own: the minute at 7260 pays for
      // level 1, which then starts at once, however long the steps.
      List<(String, double, double)> run(double step) {
        final s = open(reserve: n(0));
        s.faction('player').credits = n(1e12);
        final kora = s.body('kora');
        for (final MapEntry(key: id, value: v) in megaprojectCost(
          content,
          driver,
          0,
        ).entries) {
          if (id != 'credits') kora.stock[id] = v;
        }
        s.time = 30;
        ok(
          s,
          const StartMegaprojectStageCommand('player', 'mass_driver', 'kora'),
        );
        for (final MapEntry(key: id, value: v) in megaprojectCost(
          content,
          driver,
          1,
        ).entries) {
          if (id != 'credits') kora.stock[id] = v;
        }
        s.time = 7201;
        e.advance(s, 119, maxStep: step);
        return [
          for (final p in s.projects) (p.targetId, p.startedAt, p.finishAt),
        ];
      }

      final live = run(1);
      expect(live, [
        ('mass_driver', 7260.0, 7260 + megaprojectStageSeconds(driver, 1)),
      ]);
      expect(run(60), live);
    });

    test('credits held at the end of an hour differ by a few seconds of '
        'income at most at 1 s and 60 s steps', () {
      // Credits go in after the market, so a 60 s step pays in the minute
      // it earned, as 1 s steps do.
      GameState fed() {
        final s = open(reserve: n(1000));
        ok(s, SetAutoSellCommand('player', 'kora', 'steel', n(0)));
        ok(s, SetAutoSellCommand('player', 'kora', 'copper_ore', n(0)));
        s.body('kora').stock['iron_ore'] = n(900);
        return s;
      }

      final live = fed();
      final ticks = fed();
      e.advance(live, 3600, maxStep: 1);
      e.advance(ticks, 3600);
      final income = buildFlowReport(live, content, 'player').creditsPerSec;
      expect(income.toDouble(), greaterThan(0));
      expect(
        ticks.faction('player').credits.toDouble(),
        closeTo(
          live.faction('player').credits.toDouble(),
          income.toDouble() * 5,
        ),
      );
    });

    test('a body with two rules on one good keeps what the lower one '
        'keeps, as auto-sell does', () {
      final s = open();
      final f = s.faction('player');
      final kora = s.body('kora');
      kora.stock['steel'] = n(500);
      f.autoSell
        ..add(
          AutoSellRule(
            bodyId: 'kora',
            resourceId: 'steel',
            keepAtLeast: n(300),
          ),
        )
        ..add(
          AutoSellRule(
            bodyId: 'kora',
            resourceId: 'steel',
            keepAtLeast: n(100),
          ),
        );
      stepMegaprojectAuto(s, content, 60);
      // Auto-sell sells down to the lower keep (the hold for the Mass
      // Driver aside); auto-delivery leaves as much.
      expect(progress(s), {'steel': n(400)});
      expect(kora.stock['steel'], n(100));
    });

    test('delivers nothing to a locked megaproject, and auto-sell sells '
        'its goods', () {
      final s = open();
      s.faction('player').megaprojectLevels['orbital_station'] = 0;
      s.body('kora').stock['steel'] = n(500);
      expect(stepMegaprojectAuto(s, content, 60), isEmpty);
      final rule = AutoSellRule(
        bodyId: 'kora',
        resourceId: 'steel',
        keepAtLeast: const BigNum.zero(),
      );
      expect(autoSellKeep(s, content, rule, 60).megaprojectHold.isZero, isTrue);
    });

    test('auto-sell holds back what a fed megaproject still needs, up to '
        'the storage cap', () {
      final s = open();
      final kora = s.body('kora');
      kora.stock['steel'] = n(400);
      ok(s, SetAutoSellCommand('player', 'kora', 'steel', n(0)));
      final rule = s.faction('player').autoSell.single;
      final k = autoSellKeep(s, content, rule, 60);
      expect(k.megaprojectHold, megaprojectCost(content, driver, 0)['steel']);
      expect(k.keeps, storageCap(s, content, kora));
      expect(k.cappedAtStorage, isTrue);
      stepMarket(s, content, 60);
      expect(kora.stock['steel'], n(400));
      // Goods only: credits alone hold nothing back.
      feed(s, 'mass_driver', false, n(0));
      expect(autoSellKeep(s, content, rule, 60).megaprojectHold.isZero, isTrue);
    });

    /// [open], with Kora's steel and copper ore auto-sold and its steel
    /// fed to the Mass Driver, credits above 1000 too.
    GameState economy() {
      final s = open(reserve: n(1000));
      ok(s, SetAutoSellCommand('player', 'kora', 'steel', n(0)));
      ok(s, SetAutoSellCommand('player', 'kora', 'copper_ore', n(0)));
      s.body('kora').stock['iron_ore'] = n(900);
      return s;
    }

    group('credits above the shared reserve', () {
      final station = content.megaprojects['orbital_station']!;

      /// [open] with both megaprojects fed credits above [reserve], each
      /// with a stage under way (so the one after waits once paid) and
      /// the next one's goods in, owing [owed] credits of it.
      GameState both(Map<String, num> owed, {num reserve = 1000}) {
        final s = open(goods: false, reserve: n(reserve));
        feed(s, 'orbital_station', false, n(reserve));
        final f = s.faction('player');
        for (final m in [station, driver]) {
          s.projects.add(
            ProjectState(
              id: s.newId('p'),
              factionId: 'player',
              kind: ProjectKind.megaprojectStage,
              targetId: m.id,
              startedAt: 0,
              finishAt: 1e9,
            ),
          );
          final cost = megaprojectCost(
            content,
            m,
            megaprojectDeliveryLevel(s, 'player', m),
          );
          f.megaprojectProgress[m.id] = {
            for (final MapEntry(key: id, value: v) in cost.entries)
              id: id == 'credits' ? v - n(owed[m.id]!) : v,
          };
        }
        return s;
      }

      BigNum paid(GameState s, String m) =>
          s.faction('player').megaprojectProgress[m]!['credits']!;

      test('are split evenly, so both progress', () {
        final s = both({'orbital_station': 1e6, 'mass_driver': 1e6});
        final f = s.faction('player')..credits = n(101000);
        final before = {
          for (final m in [station, driver]) m.id: paid(s, m.id),
        };
        stepMegaprojectCredits(s, content, 60);
        for (final m in [station, driver]) {
          expect(paid(s, m.id) - before[m.id]!, n(50000), reason: m.id);
        }
        expect(f.credits, n(1000));
      });

      test('a share one cannot use goes to the other', () {
        // The station lacks 10K: it is topped off, and the rest of the
        // 100K above the reserve goes to the Mass Driver.
        final s = both({'orbital_station': 10000, 'mass_driver': 1e6});
        final f = s.faction('player')..credits = n(101000);
        final owed = megaprojectRemaining(s, content, 'player', station);
        final rest = n(100000) - owed['credits']!;
        final before = paid(s, 'mass_driver');
        final got = stepMegaprojectCredits(s, content, 60)['player']!;
        expect(got['orbital_station'], owed);
        expect(got['mass_driver'], {'credits': rest});
        expect(megaprojectStageQueued(s, content, 'player', station), isTrue);
        expect(paid(s, 'mass_driver') - before, rest);
        expect(f.credits, n(1000));
      });

      test('odd credits go one each in content order, and none below the '
          'reserve', () {
        final s = both({'orbital_station': 1e6, 'mass_driver': 1e6});
        final f = s.faction('player')..credits = n(1003);
        final got = stepMegaprojectCredits(s, content, 60)['player']!;
        expect(got['orbital_station'], {'credits': n(2)});
        expect(got['mass_driver'], {'credits': n(1)});
        expect(f.credits, n(1000));
        // At the reserve nothing goes in.
        s.time = 60;
        expect(stepMegaprojectCredits(s, content, 60), isEmpty);
      });

      test('credits never end below the reserve, float residue '
          'included', () {
        // BigNum keeps a mantissa, so 200,001 less 200,000 paid can leave a
        // hair under a reserve of 1.
        const owed = [1, 7, 500, 1e5, 1e6];
        for (final a in owed) {
          for (final b in owed) {
            for (final reserve in [0, 1, 1000, 123457]) {
              for (final spare in [0, 1, 2, 3, 99, 5000, 2e5, 9e6]) {
                final s = both({'orbital_station': a, 'mass_driver': b});
                final f = s.faction('player')
                  ..autoPayReserve = n(reserve)
                  ..credits = n(reserve + spare);
                stepMegaprojectCredits(s, content, 60);
                expect(
                  f.credits >= n(reserve),
                  isTrue,
                  reason: '$a, $b, $reserve + $spare: ${f.credits} left',
                );
              }
            }
          }
        }
      });

      /// Sets the station's credit weight to [station] and the Mass
      /// Driver's to [driverWeight], both fed credits, no goods.
      void weigh(GameState s, int station, int driverWeight) {
        final reserve = s.faction('player').autoPayReserve;
        feed(s, 'orbital_station', false, reserve, weight: station);
        feed(s, 'mass_driver', false, reserve, weight: driverWeight);
      }

      test('weights 1:3 give a 1:3 split', () {
        final s = both({'orbital_station': 1e6, 'mass_driver': 1e6});
        weigh(s, 1, 3);
        final f = s.faction('player')..credits = n(101000);
        final got = stepMegaprojectCredits(s, content, 60)['player']!;
        expect(got['orbital_station'], {'credits': n(25000)});
        expect(got['mass_driver'], {'credits': n(75000)});
        expect(f.credits, n(1000));
      });

      test('the odd credits of a weighted split go in content order', () {
        final s = both({'orbital_station': 1e6, 'mass_driver': 1e6});
        weigh(s, 1, 3);
        // 1,003 above the reserve: 250 and 752 by weight, one left over.
        s.faction('player').credits = n(2003);
        final got = stepMegaprojectCredits(s, content, 60)['player']!;
        expect(got['orbital_station'], {'credits': n(251)});
        expect(got['mass_driver'], {'credits': n(752)});
      });

      test('weight 0 gets nothing while another owes, and takes the rest '
          'once it is the only one owing', () {
        final s = both({'orbital_station': 1e6, 'mass_driver': 1e6});
        weigh(s, 0, 1);
        s.faction('player').credits = n(101000);
        var got = stepMegaprojectCredits(s, content, 60)['player']!;
        expect(got.keys, ['mass_driver']);
        expect(got['mass_driver'], {'credits': n(100000)});
        // The Mass Driver owes 10K: it is topped off and queued, and the
        // station, now the only one owing, takes the rest.
        final t = both({'orbital_station': 1e6, 'mass_driver': 10000});
        weigh(t, 0, 1);
        t.faction('player').credits = n(101000);
        final owed = megaprojectRemaining(t, content, 'player', driver);
        got = stepMegaprojectCredits(t, content, 60)['player']!;
        expect(got['mass_driver'], owed);
        expect(got['orbital_station'], {
          'credits': n(100000) - owed['credits']!,
        });
      });

      test('a locked megaproject takes no share, whatever its weight', () {
        final s = both({'orbital_station': 1e6, 'mass_driver': 1e6});
        weigh(s, 1, 3);
        final f = s.faction('player')
          ..megaprojectLevels['orbital_station'] = 0
          ..credits = n(101000);
        // The station's next stage, at its new level, owes 1M credits.
        f.megaprojectProgress['orbital_station'] = {
          for (final MapEntry(key: id, value: v) in megaprojectCost(
            content,
            station,
            megaprojectDeliveryLevel(s, 'player', station),
          ).entries)
            id: id == 'credits' ? v - n(1e6) : v,
        };
        expect(megaprojectLockedBy(s, content, 'player', driver), isNotNull);
        final got = stepMegaprojectCredits(s, content, 60)['player']!;
        expect(got.keys, ['orbital_station']);
        expect(got['orbital_station'], {'credits': n(100000)});
      });

      test('weights of 0 for all of them share evenly', () {
        final s = both({'orbital_station': 1e6, 'mass_driver': 1e6});
        weigh(s, 0, 0);
        s.faction('player').credits = n(101000);
        final got = stepMegaprojectCredits(s, content, 60)['player']!;
        expect(got['orbital_station'], {'credits': n(50000)});
        expect(got['mass_driver'], {'credits': n(50000)});
      });

      test('a share one owing less cannot use goes to the others by '
          'weight, and the reserve always holds', () {
        const owed = [1, 7, 500, 1e5, 1e6];
        for (final (a, b) in [(1, 3), (0, 1), (3, 1), (0, 0), (10, 1)]) {
          for (final x in owed) {
            for (final y in owed) {
              for (final spare in [0, 1, 2, 3, 99, 5000, 2e5, 9e6]) {
                final s = both({'orbital_station': x, 'mass_driver': y});
                weigh(s, a, b);
                final f = s.faction('player')..credits = n(1000 + spare);
                final before = {
                  for (final m in [station, driver])
                    m.id: megaprojectRemaining(s, content, 'player', m),
                };
                final got =
                    stepMegaprojectCredits(s, content, 60)['player'] ??
                    const {};
                final why = '$a:$b, owed $x and $y, $spare spare';
                expect(f.credits >= n(1000), isTrue, reason: why);
                var paid = 0.0;
                for (final m in [station, driver]) {
                  final give = got[m.id]?['credits']?.toDouble() ?? 0;
                  paid += give;
                  expect(
                    give,
                    lessThanOrEqualTo(before[m.id]!['credits']!.toDouble()),
                    reason: why,
                  );
                }
                expect(paid, lessThanOrEqualTo(spare + 1e-6), reason: why);
                // Nothing is left above the reserve while anything owes.
                final stillOwing = [
                  for (final m in [station, driver])
                    if (megaprojectTakesDeliveries(s, content, 'player', m) &&
                        megaprojectRemaining(
                          s,
                          content,
                          'player',
                          m,
                        ).containsKey('credits'))
                      m,
                ];
                if (stillOwing.isNotEmpty) {
                  expect(
                    (f.credits - n(1000)).toDouble(),
                    lessThan(1),
                    reason: why,
                  );
                }
              }
            }
          }
        }
      });

      test('weighted, a catch-up pays as 60 s steps do to the credit, and 1 '
          's steps in the same ratio', () {
        GameState start() {
          final s = both({'orbital_station': 4e6, 'mass_driver': 4e6});
          weigh(s, 1, 3);
          ok(s, SetAutoSellCommand('player', 'kora', 'steel', n(0)));
          ok(s, SetAutoSellCommand('player', 'kora', 'copper_ore', n(0)));
          s.faction('player').credits = n(5000);
          return s;
        }

        final from = start();
        final live = start();
        final ticks = start();
        final away = start();
        e.advance(live, 3600, maxStep: 1);
        e.advance(ticks, 3600);
        e.catchUpOffline(away, 3600);
        expect(encode(away), encode(ticks));
        double gained(GameState g, String m) =>
            (paid(g, m) - paid(from, m)).toDouble();
        for (final g in [live, ticks]) {
          final a = gained(g, 'orbital_station');
          final b = gained(g, 'mass_driver');
          expect(a, greaterThan(1000));
          // 1:3, give or take an odd credit a minute.
          expect(b, closeTo(3 * a, 4 * 60));
        }
        expect(
          gained(live, 'mass_driver'),
          closeTo(
            gained(ticks, 'mass_driver'),
            gained(ticks, 'mass_driver') * 0.02,
          ),
        );
      });

      test('1 s and 60 s steps pay both alike, never below the reserve', () {
        GameState run(double step) {
          final s = both({'orbital_station': 4e6, 'mass_driver': 4e6});
          ok(s, SetAutoSellCommand('player', 'kora', 'steel', n(0)));
          ok(s, SetAutoSellCommand('player', 'kora', 'copper_ore', n(0)));
          s.faction('player').credits = n(5000);
          for (var t = 0.0; t < 3600; t += step) {
            e.advance(s, step, maxStep: step);
            expect(
              s.faction('player').credits >= n(1000),
              isTrue,
              reason: 'at ${s.time}',
            );
          }
          return s;
        }

        final start = both({'orbital_station': 4e6, 'mass_driver': 4e6});
        BigNum gained(GameState g, String m) => paid(g, m) - paid(start, m);
        final live = run(1);
        final ticks = run(60);
        final income = buildFlowReport(
          live,
          content,
          'player',
        ).creditsPerSec.toDouble();
        for (final m in ['orbital_station', 'mass_driver']) {
          final want = gained(live, m).toDouble();
          expect(want, greaterThan(income * 1000), reason: m);
          expect(
            gained(ticks, m).toDouble(),
            closeTo(want, income * 5),
            reason: m,
          );
        }
        // An odd credit a minute at most between them.
        expect(
          (gained(live, 'orbital_station') - gained(live, 'mass_driver'))
              .toDouble()
              .abs(),
          lessThanOrEqualTo(60),
        );
      });
    });

    group('goods near ready', () {
      /// [open] with Kora's steel and copper ore auto-sold, 400 steel on
      /// Kora, the Mass Driver fed goods near ready (credits too, above
      /// 1000, with [credits]), owing [owed] credits for its stage, and
      /// [held] credits held.
      GameState near({
        required num owed,
        num held = 1000,
        bool credits = false,
      }) {
        final s = open(goods: false);
        feed(
          s,
          'mass_driver',
          false,
          credits ? n(1000) : null,
          mode: GoodsFeedMode.nearReady,
        );
        ok(s, SetAutoSellCommand('player', 'kora', 'steel', n(0)));
        ok(s, SetAutoSellCommand('player', 'kora', 'copper_ore', n(0)));
        final cost = megaprojectCost(content, driver, 0);
        s.body('kora').stock['steel'] = n(400);
        s.faction('player')
          ..credits = n(held)
          ..megaprojectProgress['mass_driver'] = {
            'credits': cost['credits']! - n(owed),
          };
        return s;
      }

      MegaprojectAuto setting(GameState s) =>
          s.faction('player').megaprojectAuto['mass_driver']!;

      BigNum hold(GameState s) => autoSellKeep(
        s,
        content,
        s.faction('player').autoSell.firstWhere((r) => r.resourceId == 'steel'),
        60,
      ).megaprojectHold;

      /// Kora's steel and copper ore sales a second over [seconds] of 60 s
      /// steps from a copy of [s].
      double income(GameState s, double seconds) {
        final t = s.copy();
        BigNum sales() => t
            .faction('player')
            .salesRevenue
            .values
            .fold(const BigNum.zero(), (a, v) => a + v);
        e.advance(t, 600);
        final from = sales();
        e.advance(t, seconds);
        return (sales() - from).toDouble() / seconds;
      }

      test('a stage days away is not fed, and its goods are sold', () {
        for (final credits in [false, true]) {
          final s = near(owed: 2e9, credits: credits);
          expect(hold(s).isZero, isTrue);
          e.advance(s, 600);
          expect(setting(s).feedingLevel, isNull, reason: '$credits');
          expect(progress(s)['steel'], isNull, reason: '$credits');
          expect(
            s.faction('player').salesRevenue['steel']!.toDouble(),
            greaterThan(0),
          );
          expect(hold(s).isZero, isTrue);
        }
      });

      test('with credit auto-pay off, a stage the credits held pay for is '
          'fed from the next game minute, and held back from auto-sell', () {
        final s = near(owed: 5000, held: 6000);
        e.advance(s, 30);
        expect(setting(s).feedingLevel, isNull);
        e.advance(s, 30);
        expect(setting(s).feedingLevel, 0);
        expect(hold(s), n(20000));
        // Until then its steel sold; from now on it is held and goes in.
        s.body('kora').stock['steel'] = n(400);
        e.advance(s, 60);
        expect(progress(s)['steel']!.toDouble(), greaterThanOrEqualTo(400));
      });

      test('with credit auto-pay on, a stage within 12 h of income is fed; '
          'one 24 h away is not', () {
        final probe = near(owed: 2e9, credits: true);
        final rate = income(probe, 1200);
        expect(rate, greaterThan(0.5));
        for (final (hours, fed) in [(6, true), (24, false)]) {
          final s = near(owed: rate * hours * 3600, credits: true);
          e.advance(s, 600);
          expect(setting(s).feedingLevel, fed ? 0 : isNull, reason: '$hours h');
          expect(progress(s)['steel'] != null, fed, reason: '$hours h');
        }
      });

      test('the credits share counts: weight 0 behind another owing waits', () {
        final probe = near(owed: 2e9, credits: true);
        final rate = income(probe, 1200);
        final s = near(owed: rate * 6 * 3600, credits: true);
        // The station takes every credit above the reserve: the Mass
        // Driver, at weight 0, gets none of them.
        feed(
          s,
          'mass_driver',
          false,
          n(1000),
          mode: GoodsFeedMode.nearReady,
          weight: 0,
        );
        feed(s, 'orbital_station', false, n(1000));
        e.advance(s, 600);
        expect(setting(s).feedingLevel, isNull);
      });

      test('set near ready while the credits held pay for the stage, it is '
          'fed at once: none of its goods sell meanwhile', () {
        final s = near(owed: 2e9);
        s.faction('player').credits = n(3e9);
        expect(setting(s).feedingLevel, isNull);
        feed(s, 'mass_driver', false, null, mode: GoodsFeedMode.nearReady);
        expect(setting(s).feedingLevel, 0);
        expect(hold(s), n(20000));
        e.advance(s, 60);
        expect(progress(s)['steel']!.toDouble(), greaterThanOrEqualTo(400));
        expect(s.faction('player').salesRevenue['steel'], isNull);
      });

      test('once started, feeding goes on until that stage is paid', () {
        final s = near(owed: 5000, held: 6000);
        e.advance(s, 60);
        expect(setting(s).feedingLevel, 0);
        // The credits go elsewhere: the stage is still fed.
        s.faction('player').credits = n(0);
        s.body('kora').stock['steel'] = n(300);
        final before = progress(s)['steel']?.toDouble() ?? 0;
        e.advance(s, 600);
        expect(setting(s).feedingLevel, 0);
        expect(
          progress(s)['steel']!.toDouble(),
          greaterThanOrEqualTo(before + 300),
        );
        // Paid for: the next stage starts unfed, and its steel sells.
        final f = s.faction('player');
        f
          ..credits = n(1e12)
          ..megaprojectProgress['mass_driver'] = {
            for (final MapEntry(key: id, value: v) in megaprojectCost(
              content,
              driver,
              0,
            ).entries)
              if (id != 'credits') id: v,
          };
        ok(
          s,
          DeliverToMegaprojectCommand('player', 'mass_driver', 'kora', {
            'credits': megaprojectRemaining(
              s,
              content,
              'player',
              driver,
            )['credits']!,
          }),
        );
        expect(megaprojectDeliveryLevel(s, 'player', driver), 1);
        f.credits = n(0);
        s.body('kora').stock['steel'] = n(300);
        e.advance(s, 120);
        expect(setting(s).feedingLevel, isNull);
        expect(progress(s)['steel'], isNull);
        expect(hold(s).isZero, isTrue);
      });

      test('off feeds no goods; always feeds them at once', () {
        final off = near(owed: 5000, held: 6000);
        feed(off, 'mass_driver', false, null, mode: GoodsFeedMode.off);
        feed(off, 'mass_driver', false, n(1000));
        e.advance(off, 600);
        expect(progress(off)['steel'], isNull);
        final always = near(owed: 2e9);
        feed(always, 'mass_driver', true, null);
        e.advance(always, 60);
        expect(
          progress(always)['steel']!.toDouble(),
          greaterThanOrEqualTo(400),
        );
      });

      test('an away of 14,335 s and of 14,340 s agree: no diversion for a '
          'stage not fed, the same feeding and the same top 3', () {
        for (final owed in [2e9, 5000.0]) {
          final a = near(owed: owed, held: owed < 1e6 ? 6000 : 1000);
          final b = near(owed: owed, held: owed < 1e6 ? 6000 : 1000);
          final x = e.catchUpOffline(a, 14335);
          final y = e.catchUpOffline(b, 14340);
          expect(setting(a).feedingLevel, owed < 1e6 ? 0 : isNull);
          expect(setting(a).feedingLevel, setting(b).feedingLevel);
          expect(
            [for (final n in x.topBottlenecks) n.groupKey],
            [for (final n in y.topBottlenecks) n.groupKey],
            reason: '$owed',
          );
          if (setting(a).feedingLevel == null) {
            expect(
              x.topBottlenecks.map((n) => n.kind),
              isNot(contains(BottleneckKind.megaprojectDiversion)),
            );
          }
        }
      });

      test('mixed settings: near ready at weight 3 beside always at weight '
          '0; the reserve holds at every step and steps agree', () {
        GameState make() {
          final s = near(owed: 2e6, credits: true);
          feed(s, 'mass_driver', true, n(1000), weight: 0);
          feed(
            s,
            'orbital_station',
            false,
            n(1000),
            mode: GoodsFeedMode.nearReady,
            weight: 3,
          );
          s.faction('player').credits = n(5000);
          return s;
        }

        final live = make();
        final ticks = make();
        final away = make();
        for (var t = 0; t < 1800; t++) {
          e.advance(live, 1, maxStep: 1);
          expect(
            live.faction('player').credits >= n(1000),
            isTrue,
            reason: 'at ${live.time}',
          );
        }
        e.advance(ticks, 1800);
        e.catchUpOffline(away, 1800);
        expect(encode(away), encode(ticks));
        BigNum paid(GameState g, String m) =>
            g.faction('player').megaprojectProgress[m]?['credits'] ?? n(0);
        final start = make();
        for (final g in [live, ticks]) {
          // The station owes credits, so the Mass Driver, at weight 0,
          // takes none; its goods go in every minute.
          expect(paid(g, 'mass_driver'), paid(start, 'mass_driver'));
          expect(progress(g)['steel']!.toDouble(), greaterThan(400));
          // The station is far from ready: credits go in, goods do not.
          final f = g.faction('player');
          expect(f.megaprojectAuto['orbital_station']!.feedingLevel, isNull);
          expect(
            (paid(g, 'orbital_station') - paid(start, 'orbital_station'))
                .toDouble(),
            greaterThan(1000),
          );
        }
        final want = paid(ticks, 'orbital_station').toDouble();
        expect(
          paid(live, 'orbital_station').toDouble(),
          closeTo(want, want * 0.02),
        );
      });

      test('1 s steps, 60 s steps, 55 s and 5 s, and a catch-up start '
          'feeding at the same minute and deliver alike', () {
        final rate = income(near(owed: 2e9, credits: true), 1200);
        for (final credits in [false, true]) {
          GameState make() => credits
              ? near(owed: rate * 6 * 3600, credits: true)
              : near(owed: 5000, held: 6000);
          double? startedAt(GameState s, double step, double until) {
            double? at;
            while (s.time < until - 1e-9) {
              e.advance(s, step, maxStep: step);
              if (at == null && setting(s).feedingLevel != null) at = s.time;
            }
            return at;
          }

          final live = make();
          final ticks = make();
          final split = make();
          final away = make();
          final a = startedAt(live, 1, 1800);
          final b = startedAt(ticks, 60, 1800);
          final sixty = make();
          e
            ..advance(split, 55)
            ..advance(split, 5)
            ..advance(sixty, 60);
          expect(
            setting(split).feedingLevel,
            setting(sixty).feedingLevel,
            reason: '$credits',
          );
          // Without auto-pay, the first minute decides; with it, the first
          // minute only marks the income, and the second decides.
          expect(setting(sixty).feedingLevel, credits ? isNull : 0);
          e.catchUpOffline(away, 1800);
          expect(a, isNotNull, reason: '$credits');
          expect(a, b, reason: '$credits');
          expect(encode(away), encode(ticks), reason: '$credits');
          final want = progress(ticks)['steel']!.toDouble();
          expect(
            progress(live)['steel']!.toDouble(),
            closeTo(want, want * 0.02 + 1),
            reason: '$credits',
          );
        }
      });
    });

    test('1 s steps, 60 s steps and a catch-up deliver the same', () {
      final live = economy();
      final ticks = economy();
      final away = economy();
      e.advance(live, 3600, maxStep: 1);
      e.advance(ticks, 3600);
      e.catchUpOffline(away, 3600);
      final want = progress(live);
      expect(want['steel']!.toDouble(), greaterThan(100));
      expect(want['credits']!.toDouble(), greaterThan(100));
      // Credits held and paid in, together.
      double total(GameState g) =>
          g.faction('player').credits.toDouble() +
          progress(g)['credits']!.toDouble();
      for (final s in [ticks, away]) {
        expect(
          progress(s)['steel']!.toDouble(),
          closeTo(want['steel']!.toDouble(), want['steel']!.toDouble() * 0.02),
        );
        expect(total(s), closeTo(total(live), total(live) * 0.02));
        // A 60 s step pays in its own minute's income at the next minute;
        // 1 s steps pay all but the last second's at once.
        final minute = 60 * total(live) / 3600;
        expect(
          progress(s)['credits']!.toDouble(),
          closeTo(want['credits']!.toDouble(), minute),
        );
      }
    });

    test('credits per second leave out the goods auto-delivery takes', () {
      final fed = economy();
      final sold = economy();
      feed(sold, 'mass_driver', false, null);
      e.advance(fed, 600);
      e.advance(sold, 600);
      // Steel up to the cap, as between minutes in long steps: auto-sell
      // would sell what is made above it, but auto-delivery takes it.
      final kora = fed.body('kora');
      kora.stock['steel'] = storageCap(fed, content, kora) - n(1);
      final cps = buildFlowReport(fed, content, 'player').creditsPerSec;
      final all = buildFlowReport(sold, content, 'player').creditsPerSec;
      // Only copper ore sells while the steel goes to the Mass Driver.
      final before = fed.faction('player').salesRevenue['copper_ore']!;
      e.advance(fed, 600);
      final copper =
          (fed.faction('player').salesRevenue['copper_ore']! - before)
              .toDouble() /
          600;
      expect(cps.toDouble(), closeTo(copper, copper * 0.05));
      expect(all.toDouble(), greaterThan(cps.toDouble() * 1.5));
    });

    test('the report shows what goes to each megaproject a second, and '
        'its value', () {
      final s = economy();
      e.advance(s, 600);
      // Above the reserve, so what is earned goes in as it comes.
      s.faction('player').credits = n(5000);
      final r = buildFlowReport(s, content, 'player');
      final per = r.autoDeliveredPerSec['mass_driver']!;
      // A smelter makes 0.2 steel a second, all of it fed.
      expect(per['steel']!.toDouble(), closeTo(0.2, 0.01));
      // The credits above the reserve: about the income a second.
      expect(
        per['credits']!.toDouble(),
        closeTo(r.creditsPerSec.toDouble(), r.creditsPerSec.toDouble() * 0.1),
      );
      expect(
        r.autoDeliveredValuePerSec.toDouble(),
        closeTo(
          per['credits']!.toDouble() +
              per['steel']!.toDouble() * price(s, content, 'steel').toDouble(),
          1e-9,
        ),
      );
      // Nothing fed, nothing shown.
      final plain = e.newGame(1);
      final none = buildFlowReport(plain, content, 'player');
      expect(none.autoDeliveredPerSec, isEmpty);
      expect(none.autoDeliveredValuePerSec.isZero, isTrue);
    });

    test('credits paid in a second are a share of the income shown, never '
        'more', () {
      // Kora's smelter runs on a stockpile of ore, which the short run of
      // play sells and the steady figure leaves out: the income shown is
      // the steady one, and so are the credits paid from it.
      final s = open(reserve: n(0));
      ok(s, SetAutoSellCommand('player', 'kora', 'steel', n(0)));
      ok(s, SetAutoSellCommand('player', 'kora', 'copper_ore', n(0)));
      feed(s, 'mass_driver', false, n(0));
      final kora = s.body('kora');
      for (final b in kora.buildings) {
        if (b.defId == 'mine' && b.depositResourceId == 'iron_ore') b.crew = 0;
      }
      kora.stock['iron_ore'] = n(1e5);
      e.advance(s, 120);
      final r = buildFlowReport(s, content, 'player');
      final paid = r.autoDeliveredPerSec['mass_driver']!['credits']!;
      expect(
        paid <= r.creditsPerSec,
        isTrue,
        reason: '$paid of ${r.creditsPerSec}',
      );
      expect(
        paid.toDouble(),
        closeTo(r.creditsPerSec.toDouble(), r.creditsPerSec.toDouble() * 0.05),
      );
    });

    test('credits per second read again for the same state are the same, '
        'and a changed state gets its own', () {
      final s = economy();
      e.advance(s, 600);
      final first = buildFlowReport(s, content, 'player');
      final again = buildFlowReport(s.copy(), content, 'player');
      expect(again.creditsPerSec, first.creditsPerSec);
      expect(
        again.autoDeliveredPerSec.toString(),
        first.autoDeliveredPerSec.toString(),
      );
      // Copper ore no longer sold: less income.
      s
          .faction('player')
          .autoSell
          .removeWhere((r) => r.resourceId == 'copper_ore');
      final changed = buildFlowReport(s, content, 'player').creditsPerSec;
      expect(changed < first.creditsPerSec, isTrue);
    });

    test('feeding a megaproject does not shrink contract rewards', () {
      final fed = economy();
      final sold = economy();
      feed(sold, 'mass_driver', false, null);
      e.advance(fed, 1200);
      e.advance(sold, 1200);
      final withFeed = incomeBasis(
        fed,
        content,
        buildFlowReport(fed, content, 'player'),
      );
      final without = incomeBasis(
        sold,
        content,
        buildFlowReport(sold, content, 'player'),
      );
      expect(withFeed.toDouble(), greaterThan(0));
      expect(withFeed >= without.mulDouble(0.999), isTrue);
    });

    test('the away summary lists what went to each megaproject', () {
      final s = economy();
      final ticks = economy();
      final earnedBefore = s.faction('player').lifetimeCredits;
      final sum = e.catchUpOffline(s, 3600);
      // What was earned, what of it went in, and the change in credits.
      expect(
        sum.creditsEarned,
        s.faction('player').lifetimeCredits - earnedBefore,
      );
      expect(sum.creditsPaidIn, sum.autoDelivered['mass_driver']!['credits']);
      expect(sum.creditsPaidIn > const BigNum.zero(), isTrue);
      expect(
        sum.creditsGained.toDouble(),
        closeTo((sum.creditsEarned - sum.creditsPaidIn).toDouble(), 1e-6),
      );
      e.advance(ticks, 3600);
      expect(
        sum.autoDelivered['mass_driver'],
        ticks.faction('player').megaprojectProgress['mass_driver'],
      );
      final back = OfflineSummary.fromJson(
        jsonDecode(jsonEncode(sum.toJson())) as Map<String, Object?>,
      );
      expect(jsonEncode(back.toJson()), jsonEncode(sum.toJson()));
      expect(back.autoDelivered['mass_driver']!['steel'], isNotNull);
      // A summary from before auto-delivery reads as none.
      final old = sum.toJson()..remove('autoDelivered');
      expect(OfflineSummary.fromJson(old).autoDelivered, isEmpty);
    });

    test('a body making more than it can store a minute feeds as much in 1 '
        's steps as in 60 s steps', () {
      GameState fast() {
        final s = economy();
        final kora = s.body('kora');
        // A smelter at speed level 75 makes about 2K steel a second, far
        // past Kora's cap in a minute, from ore stocked above the cap.
        kora.buildings
                .firstWhere((b) => b.defId == 'smelter')
                .levels[UpgradeTrack.speed] =
            75;
        kora.stock['iron_ore'] = n(1e8);
        // Every good but steel already in, for the first two levels.
        s.faction('player')
          ..credits = n(1e15)
          ..megaprojectProgress['mass_driver'] = {
            for (final MapEntry(key: id, value: v) in megaprojectCost(
              content,
              driver,
              0,
            ).entries)
              if (id != 'credits' && id != 'steel') id: v,
          };
        feed(s, 'mass_driver', true, n(0));
        return s;
      }

      final live = fast();
      final ticks = fast();
      e.advance(live, 600, maxStep: 1);
      e.advance(ticks, 600);
      expect(
        [for (final p in live.projects) (p.targetId, p.startedAt, p.finishAt)],
        [for (final p in ticks.projects) (p.targetId, p.startedAt, p.finishAt)],
      );
      expect(live.projects, isNotEmpty);
      expect(
        megaprojectStageQueued(live, content, 'player', driver),
        megaprojectStageQueued(ticks, content, 'player', driver),
      );
      final want = progress(ticks)['steel']?.toDouble() ?? 0;
      expect(
        progress(live)['steel']?.toDouble() ?? 0,
        closeTo(want, want * 0.02 + 1),
      );
    });

    test('a catch-up is the same as 60 s steps, to the unit', () {
      final ticks = economy();
      final away = economy();
      e.advance(ticks, 7200);
      e.catchUpOffline(away, 7200);
      expect(encode(away), encode(ticks));
    });
  });
}

/// The shipped content with the Mass Driver also asking for 20,000 steel
/// a level, as it did when these tests were written.
Content _withDriverSteel() {
  final b = shippedBundle();
  final driver = (b['megaprojects']! as List)
      .cast<Map<String, Object?>>()
      .firstWhere((m) => m['id'] == 'mass_driver');
  (driver['baseCost']! as Map<String, Object?>)['steel'] = '20000';
  return (Content.fromBundle(b) as ContentOk).content;
}
