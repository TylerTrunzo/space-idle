import 'dart:math' as math;
import 'package:game_core/game_core.dart';
import 'package:game_sim/src/bots/bot.dart';
import 'package:game_sim/src/content_files.dart';

String? neg(GameState s) {
  for (final b in s.bodies) {
    for (final e in b.stock.entries) {
      if (e.value.isNegative) return '${b.id}/${e.key}=${e.value}';
    }
  }
  return null;
}

void main(List<String> a) {
  final seed = int.parse(a[0]);
  final days = int.parse(a[1]);
  final content =
      (Content.fromBundle(loadContentDir('/home/user/space-idle/content'))
              as ContentOk)
          .content;
  final e = GameEngine(content);
  final s = e.newGame(seed);
  final bot = BalancedBot();
  final f = s.factions.firstWhere((x) => x.isPlayer);
  final end = days * 86400.0;
  var clock = 0.0;
  var ci = 0;
  var found = 0;
  void tickChecked(double dt) {
    final before = s.copy();
    e.tick(s, dt);
    final n = neg(s);
    if (n != null && neg(before) == null) {
      found++;
      final c = before;
      final kept = stockOverCap(c, content);
      deliverShipments(c);
      final a1 = neg(c);
      stepProduction(c, content, dt);
      final a2 = neg(c);
      sendCargo(c, content, dt);
      final a3 = neg(c);
      stepMarket(c, content, dt);
      final a4 = neg(c);
      clampStorage(c, content, kept);
      print(
        't=${s.time} tick neg $n: deliver=$a1 prod=$a2 cargo=$a3 market=$a4',
      );
    }
  }

  while (clock < end && found < 5) {
    final aEnd = math.min(clock + 180, end);
    while (clock < aEnd) {
      for (final c in bot.decide(e, s, f.id)) {
        final had = neg(s);
        e.apply(s, c);
        final n = neg(s);
        if (n != null && had == null) {
          found++;
          print('t=${s.time} cmd ${c.toJson()} -> $n');
        }
      }
      final st = math.min(aEnd - clock, 10.0);
      final whole = (st / 60).floor();
      for (var i = 0; i < whole; i++) {
        tickChecked(60);
      }
      final rest = st - whole * 60;
      if (rest > 60 * 1e-9) tickChecked(rest);
      clock += st;
    }
    final next = math.min((ci + 1) * 21600.0, end);
    if (next > clock) {
      final sim = math.min(next - clock, content.rules.offlineCapSeconds);
      final whole = (sim / 60).floor();
      for (var i = 0; i < whole; i++) {
        tickChecked(60);
      }
      final rest = sim - whole * 60;
      if (rest > 60 * 1e-9) tickChecked(rest);
      clock = next;
    }
    ci++;
  }
  print('done found=$found final=${neg(s)}');
}
