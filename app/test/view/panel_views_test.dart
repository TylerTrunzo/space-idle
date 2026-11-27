import 'package:flutter_test/flutter_test.dart';
import 'package:game_core/game_core.dart';
import 'package:space_idle/game/clock.dart';
import 'package:space_idle/game/content_source.dart';
import 'package:space_idle/game/game_controller.dart';
import 'package:space_idle/game/save_store.dart';
import 'package:space_idle/view/body_actions_view.dart';
import 'package:space_idle/view/catalog_view.dart';
import 'package:space_idle/view/spend_view.dart';
import 'package:space_idle/view/view_models.dart';

final Content content = loadEmbeddedContent();
const _p = 'player';

GameController _controller() => GameController(
  content: content,
  store: MemorySaveStore(),
  clock: FakeClock(DateTime.utc(2026, 11, 27)),
  newGameSeed: 1,
);

CatalogEntryView _entry(List<CatalogEntryView> all, String name) =>
    all.singleWhere((e) => e.name == name);

void main() {
  late GameController c;
  setUp(() => c = _controller());

  group('catalogView', () {
    test('an extractor has one entry per resource it can mine', () {
      final names = catalogView(c).map((e) => e.name).toList();
      expect(names, containsAll(['Mine (Iron Ore)', 'Mine (Copper Ore)']));
      expect(names, contains('Smelter'));
      expect(names, isNot(contains('Mine')));
    });

    test('shows cost, crew slots and level-1 rates a second', () {
      final smelter = _entry(catalogView(c), 'Smelter');
      expect(smelter.cost, '150 credits');
      expect(smelter.crewSlots, 1);
      // 2 Iron Ore in, 1 Steel out, every 5 s.
      expect(smelter.uses.single.name, 'Iron Ore');
      expect(smelter.uses.single.value, '-0.4/s');
      expect(smelter.makes.single.value, '+0.2/s');
    });

    test('a body without the deposit cannot host it, and says why', () {
      c.state.body('brine').ownerId = _p;
      c.state.faction(_p).credits = BigNum.from(1e6);
      final copper = _entry(catalogView(c), 'Mine (Copper Ore)');
      final kora = copper.hosts.singleWhere((h) => h.bodyId == 'kora');
      final brine = copper.hosts.singleWhere((h) => h.bodyId == 'brine');
      expect(kora.canBuild, isTrue);
      expect(kora.reason, isNull);
      expect(brine.canBuild, isFalse);
      expect(brine.reason, 'needs a Copper Ore deposit');
    });

    test('a full body or short credits say so', () {
      final smelter = _entry(catalogView(c), 'Fusion Refinery');
      expect(smelter.hosts.single.canBuild, isFalse);
      expect(smelter.hosts.single.reason, 'needs 3K credits (you have 250)');

      final kora = c.state.body('kora');
      c.state.faction(_p).credits = BigNum.from(1e6);
      while (kora.buildings.length < buildSlots(content, kora)) {
        c.run(const BuildCommand(_p, 'kora', 'smelter'));
      }
      final full = _entry(catalogView(c), 'Smelter').hosts.single;
      expect(full.canBuild, isFalse);
      expect(full.reason, 'no free build slot');
    });

    test('filtered to the makers of a resource', () {
      final iron = catalogView(c, makes: 'iron_ore').map((e) => e.name);
      expect(iron, contains('Mine (Iron Ore)'));
      expect(iron, isNot(contains('Smelter')));
      expect(iron, isNot(contains('Mine (Copper Ore)')));
      final steel = catalogView(c, makes: 'steel').map((e) => e.name);
      expect(steel, containsAll(['Smelter', 'Hydrogen Furnace']));
    });
  });

  group('claim and slots', () {
    test('a claim view says how long the claim takes', () {
      final claim = bodyView(c, 'cinder')!.claim!;
      expect(claim.time, '30m');
    });

    test('an unaffordable claim says what is missing', () {
      final claim = bodyView(c, 'cinder')!.claim!;
      expect(claim.affordable, isFalse);
      expect(claim.blockedReason, 'needs 5K credits (you have 250)');
    });

    test('an affordable claim has no blocked reason', () {
      c.state.faction(_p).credits = BigNum.from(1e6);
      expect(bodyView(c, 'cinder')!.claim!.blockedReason, isNull);
    });

    test('a second claim without kits names the kits', () {
      c.state.faction(_p).credits = BigNum.from(1e6);
      c.state.body('brine').ownerId = _p;
      expect(
        bodyView(c, 'cinder')!.claim!.blockedReason,
        'needs 10 Outpost Kit on one of your bodies',
      );
    });

    test('expand slots shows its price and time, then its countdown', () {
      final kora = c.state.body('kora');
      var view = expandSlotsView(c, 'kora')!;
      expect(
        view.cost,
        '${formatNumber(slotCost(content, kora)[creditsKey]!)} '
        'credits',
      );
      expect(view.time, formatDuration(content.rules.expandSlotsSeconds));
      expect(view.running, isNull);

      c.state.faction(_p).credits = BigNum.from(1e9);
      expect(expandSlotsView(c, 'kora')!.affordable, isTrue);
      c.run(const ExpandSlotsCommand(_p, 'kora'));
      view = expandSlotsView(c, 'kora')!;
      expect(view.running?.title, 'Extra build slot on Kora');
      expect(view.affordable, isFalse);
      expect(expandSlotsView(c, 'cinder'), isNull, reason: 'not owned');
    });
  });

  group('buyMaxView', () {
    test('previews what Buy max would buy, changing nothing', () {
      c.state.faction(_p).credits = BigNum.from(1000);
      final before = SaveCodec.encode(c.state);
      final view = buyMaxView(c);
      expect(SaveCodec.encode(c.state), before, reason: 'a dry run');
      expect(view.levels, greaterThan(0));

      // It matches what the command then does.
      final r = c.run(BuyUpgradesCommand(_p, BigNum.from(1000)));
      final o = (r as CommandOk).outcome! as UpgradesBought;
      expect(view.levels, o.levels);
      expect(view.cost, formatNumber(o.total));
      expect(view.confirm, view.share > 0.5);
    });

    test('with too few credits it buys nothing and says what it costs', () {
      c.state.faction(_p).credits = const BigNum.zero();
      final view = buyMaxView(c);
      expect(view.levels, 0);
      expect(view.blockedReason, startsWith('the cheapest costs '));
    });

    test('asks for a confirm when it would spend over half the credits', () {
      c.state.faction(_p).credits = BigNum.from(80);
      final view = buyMaxView(c);
      expect(view.levels, greaterThan(0));
      expect(view.share, greaterThan(0.5));
      expect(view.confirm, isTrue);
    });
  });

  group('spends', () {
    test('over half the credits held asks for a confirm', () {
      expect(needsConfirm(BigNum.from(51), BigNum.from(100)), isTrue);
      expect(needsConfirm(BigNum.from(50), BigNum.from(100)), isFalse);
      expect(needsConfirm(const BigNum.zero(), const BigNum.zero()), isFalse);
      expect(
        needsConfirm(BigNum.from(101), BigNum.from(100)),
        isFalse,
        reason: 'unaffordable: the command says why',
      );
    });

    test('each spend button carries its price in credits', () {
      c.state.body('brine').ownerId = _p;
      final mine = _entry(catalogView(c), 'Mine (Iron Ore)');
      expect(mine.price, content.buildings['mine']!.buildCost[creditsKey]);
      final claim = bodyView(c, 'cinder')!.claim!;
      expect(claim.price, claimCost(c.state, content, _p)[creditsKey]);
      final slots = expandSlotsView(c, 'kora')!;
      expect(slots.price, slotCost(content, c.state.body('kora'))[creditsKey]);
      // An upgrade is priced at the tap (bulkUpgrade with one level).
      final b3 = c.state.body('kora').buildings.firstWhere((b) => b.id == 'b3');
      expect(
        bulkUpgrade(c, 'b3', UpgradeTrack.speed, 1).price,
        upgradeCost(content, b3, UpgradeTrack.speed)[creditsKey],
      );
    });

    test('bulkUpgrade totals the levels a long press would buy', () {
      final before = SaveCodec.encode(c.state);
      c.state.faction(_p).credits = BigNum.from(1e9);
      final ten = bulkUpgrade(c, 'b3', UpgradeTrack.speed, 10);
      expect(ten.levels, 10);
      final b3 = c.state.body('kora').buildings.firstWhere((b) => b.id == 'b3');
      expect(b3.levels[UpgradeTrack.speed], 0, reason: 'a dry run');
      expect(ten.price > BigNum.from(75 * 10), isTrue);

      c.state.faction(_p).credits = BigNum.from(160); // two levels, 75 + ~84
      final some = bulkUpgrade(c, 'b3', UpgradeTrack.speed, 10);
      expect(some.levels, inInclusiveRange(1, 2));
      expect(some.price <= BigNum.from(160), isTrue);
      c.state.faction(_p).credits = BigNum.from(250);
      expect(SaveCodec.encode(c.state), before);
    });
  });

  test('a starved row names the resource it needs', () {
    c.state.body('kora').stock['iron_ore'] = const BigNum.zero();
    c.run(const AssignCrewCommand(_p, 'b1', 0));
    c.tickSeconds(1);
    final smelter = bodyView(
      c,
      'kora',
    )!.buildings.firstWhere((b) => b.name == 'Smelter');
    expect(smelter.neededResourceId, 'iron_ore');
    final mine = bodyView(c, 'kora')!.buildings.firstWhere((b) => b.id == 'b1');
    expect(mine.neededResourceId, isNull);
  });
}
