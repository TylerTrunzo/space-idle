import 'dart:convert';

import 'package:game_core/game_core.dart';
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
        SetMegaprojectAutoCommand('player', 'orbital_station', true, n(500)),
      );
      expect(
        r.outcome,
        isA<MegaprojectAutoSet>()
            .having((o) => o.megaprojectId, 'megaprojectId', 'orbital_station')
            .having((o) => o.goods, 'goods', isTrue)
            .having((o) => o.creditReserve, 'creditReserve', n(500))
            .having((o) => o.bodyId, 'bodyId', isNull),
      );
      expect(auto['orbital_station']!.goods, isTrue);
      expect(auto['orbital_station']!.creditReserve, n(500));
      ok(
        s,
        const SetMegaprojectAutoCommand('player', 'mass_driver', true, null),
      );
      ok(
        s,
        SetMegaprojectAutoCommand('player', 'orbital_station', false, n(0)),
      );
      expect(auto.keys, ['orbital_station', 'mass_driver']);
      expect(auto['orbital_station']!.goods, isFalse);
      expect(auto['orbital_station']!.creditReserve, n(0));
      expect(auto['mass_driver']!.creditReserve, isNull);
      // Neither goods nor credits: the setting goes.
      ok(
        s,
        const SetMegaprojectAutoCommand('player', 'mass_driver', false, null),
      );
      expect(auto.keys, ['orbital_station']);
    });

    test('a locked megaproject can be set up ahead of time', () {
      final s = e.newGame(1);
      ok(
        s,
        const SetMegaprojectAutoCommand('player', 'mass_driver', true, null),
      );
      expect(s.faction('player').megaprojectAuto['mass_driver']!.goods, isTrue);
    });

    test('refuses an unknown megaproject, a negative reserve and an '
        'unknown faction', () {
      final s = e.newGame(1);
      fails(
        s,
        const SetMegaprojectAutoCommand('player', 'dyson', true, null),
        CommandError.unknownDef,
      );
      fails(
        s,
        SetMegaprojectAutoCommand('player', 'orbital_station', true, n(-1)),
        CommandError.invalidAmount,
      );
      fails(
        s,
        const SetMegaprojectAutoCommand('ghost', 'orbital_station', true, null),
        CommandError.unknownFaction,
      );
    });

    test('round-trips through JSON', () {
      for (final cmd in [
        SetMegaprojectAutoCommand('player', 'orbital_station', true, n(5e6)),
        const SetMegaprojectAutoCommand('player', 'mass_driver', false, null),
      ]) {
        final back = Command.fromJson(
          jsonDecode(jsonEncode(cmd.toJson())) as Map<String, Object?>,
        );
        expect(back, isA<SetMegaprojectAutoCommand>());
        expect(back.toJson(), cmd.toJson());
      }
    });
  });

  group('saves with auto-delivery', () {
    GameState withAuto() {
      final s = e.newGame(1);
      ok(
        s,
        SetMegaprojectAutoCommand('player', 'orbital_station', true, n(250)),
      );
      ok(
        s,
        const SetMegaprojectAutoCommand('player', 'mass_driver', true, null),
      );
      return s;
    }

    test('round-trip and copy', () {
      final s = withAuto();
      final back =
          (SaveCodec.decode(SaveCodec.encode(s), content) as SaveOk).state;
      expect(encode(back), encode(s));
      final copy = s.copy();
      expect(encode(copy), encode(s));
      copy.faction('player').megaprojectAuto.clear();
      expect(s.faction('player').megaprojectAuto, hasLength(2));
    });

    test('an older save without it has none', () {
      final m = jsonDecode(encode(withAuto())) as Map<String, Object?>;
      for (final f in (m['factions']! as List).cast<Map<String, Object?>>()) {
        f.remove('megaprojectAuto');
      }
      final r = SaveCodec.decode(jsonEncode(m), content);
      expect(r, isA<SaveOk>(), reason: r is SaveError ? r.message : '');
      expect((r as SaveOk).state.faction('player').megaprojectAuto, isEmpty);
    });

    Map<String, Object?> playerOf(Map<String, Object?> m) =>
        (m['factions']! as List).cast<Map<String, Object?>>().first;

    test('an unknown megaproject is an unknown id', () {
      final m = jsonDecode(encode(withAuto())) as Map<String, Object?>;
      (playerOf(m)['megaprojectAuto']! as Map)['dyson'] = {'goods': true};
      final r = SaveCodec.decode(jsonEncode(m), content);
      expect((r as SaveError).kind, SaveErrorKind.unknownContentId);
    });

    test('a negative credit reserve is refused', () {
      final m = jsonDecode(encode(withAuto())) as Map<String, Object?>;
      (playerOf(m)['megaprojectAuto']! as Map)['orbital_station'] = {
        'goods': true,
        'creditReserve': '-1',
      };
      final r = SaveCodec.decode(jsonEncode(m), content);
      expect((r as SaveError).kind, SaveErrorKind.invalidValue);
      expect(r.message, contains('orbital_station'));
    });

    test('a setting that is not an object is malformed', () {
      final m = jsonDecode(encode(withAuto())) as Map<String, Object?>;
      (playerOf(m)['megaprojectAuto']! as Map)['orbital_station'] = 5;
      final r = SaveCodec.decode(jsonEncode(m), content);
      expect(r, isA<SaveError>());
    });
  });

  group('auto-delivery', () {
    final driver = content.megaprojects['mass_driver']!;

    /// A new game at Orbital Station level 2, so the Mass Driver is open,
    /// with no contracts on the board and none due, and
    /// [goods]/[reserve] auto-delivery to the Mass Driver.
    GameState open({bool goods = true, BigNum? reserve}) {
      final s = e.newGame(1);
      final f = s.faction('player');
      f.megaprojectLevels['orbital_station'] = 2;
      f.contracts.clear();
      f.contractRefillAt
        ..clear()
        ..addAll(List.filled(RulesDef.contractSlots, 1e12));
      ok(s, SetMegaprojectAutoCommand('player', 'mass_driver', goods, reserve));
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
      expect(f.credits, n(5000));
      ok(s, SetMegaprojectAutoCommand('player', 'mass_driver', false, n(1200)));
      f.credits = n(5000.5);
      s.time = 60;
      final got = stepMegaprojectAuto(s, content, 60);
      expect(got['player']!['mass_driver'], {'credits': n(3800)});
      expect(f.credits.toDouble(), closeTo(1200.5, 1e-9));
      // At the reserve, nothing more.
      s.time = 120;
      expect(stepMegaprojectAuto(s, content, 60), isEmpty);
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
      final stage = megaprojectStageOf(s, 'player', 'mass_driver');
      expect(stage, isNotNull);
      expect(megaprojectStageQueued(s, content, 'player', driver), isTrue);
      expect(progress(s), megaprojectCost(content, driver, 1));
      // Nothing more goes in while the paid stage waits.
      final credits = f.credits;
      s.time = 60;
      expect(stepMegaprojectAuto(s, content, 60), isEmpty);
      expect(f.credits, credits);
      // Once the first is done, the second starts and deliveries go on.
      e.advance(s, stage!.finishAt - s.time + 120);
      expect(f.megaprojectLevels['mass_driver'], 1);
      expect(megaprojectStageOf(s, 'player', 'mass_driver'), isNotNull);
      expect(progress(s).keys, isNotEmpty);
      expect(f.credits < credits, isTrue);
    });

    test('delivers nothing to a locked megaproject, and auto-sell sells '
        'its goods', () {
      final s = open();
      s.faction('player').megaprojectLevels['orbital_station'] = 1;
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
      ok(s, SetMegaprojectAutoCommand('player', 'mass_driver', false, n(0)));
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
      ok(
        sold,
        const SetMegaprojectAutoCommand('player', 'mass_driver', false, null),
      );
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

    test('feeding a megaproject does not shrink contract rewards', () {
      final fed = economy();
      final sold = economy();
      ok(
        sold,
        const SetMegaprojectAutoCommand('player', 'mass_driver', false, null),
      );
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
      final sum = e.catchUpOffline(s, 3600);
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

    test('a catch-up is the same as 60 s steps, to the unit', () {
      final ticks = economy();
      final away = economy();
      e.advance(ticks, 7200);
      e.catchUpOffline(away, 7200);
      expect(encode(away), encode(ticks));
    });
  });
}
