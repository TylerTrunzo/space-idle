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
}
