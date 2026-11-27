import 'dart:math' as math;

import 'package:game_core/game_core.dart';
import 'package:space_idle/view/format.dart';

// The app's player-facing sentences: what a bottleneck is, and what a
// command did. They follow the CLI's wording (game_sim's script runner),
// without the ids a player never sees, and are built from typed fields
// only. A later task moves both copies into one shared pure-Dart package,
// so these stay pure functions of (state, content, input).

/// A plain-English sentence for bottleneck [n] of [factionId], such as
/// "Smelter on Kora is running at 50%: not enough Iron Ore", for every
/// [BottleneckKind] and for groups of several buildings.
String bottleneckText(GameState s, Content c, String factionId, Bottleneck n) =>
    _Words(s, c, factionId).bottleneck(n);

/// What [cmd], just applied to [s], did, from its typed outcome [o]: the
/// success line the app shows, such as "Started claiming Brine for 40K
/// credits (no kits needed); done in 30m".
String outcomeMessage(GameState s, Content c, Command cmd, CommandOutcome o) =>
    _Words(s, c, cmd.factionId).outcome(cmd, o);

/// A crewed building's line when the faction's housing supports fewer
/// crew than it has assigned: "Short of crew: 18 of 20 crew housed".
String crewShortText(GameState s, Content c, String factionId) {
  final t = crewTotals(s, c, factionId);
  return 'Short of crew: ${t.supported} of ${t.assigned} crew housed';
}

/// What [m]'s bonuses add up to at [level]: "storage +30%, housing +15%,
/// offline cap +3h" with " (tiers 0-1)" on a bonus limited to some tiers;
/// "no bonus" at level 0.
String megaprojectBonusText(MegaprojectDef m, int level) {
  if (level <= 0) return 'no bonus';
  String pct(double v) => '+${_short(v)}%';
  String times(double v) => '×${_short(v)}';
  return [
    for (final b in megaprojectBonusesAt(m, level))
      '${switch (b.kind) {
        BonusKind.storagePercent => 'storage ${pct(b.value)}',
        BonusKind.housingPercent => 'housing ${pct(b.value)}',
        BonusKind.offlineCapSeconds => 'offline cap +${formatDuration(b.value)}',
        BonusKind.outputPercent => 'output ${pct(b.value)}',
        BonusKind.marketDepthPercent => 'market depth ${pct(b.value)}',
        BonusKind.marketDepthMultiplier => 'market depth ${times(b.value)}',
        BonusKind.productionSpeedMultiplier => 'production speed ${times(b.value)}',
        BonusKind.salePriceMultiplier => 'sale price ${times(b.value)}',
      }}${_tiersText(b.appliesToMinTier ?? 0, b.appliesToMaxTier)}',
  ].join(', ');
}

/// " (tier 0)", " (tiers 0-2)", " (tiers 2 and up)", or nothing for every
/// tier.
String _tiersText(int from, int? to) => switch ((from, to)) {
  (0, null) => '',
  (_, null) => ' (tiers $from and up)',
  (_, final t?) when t == from => ' (tier $t)',
  (_, final t?) => ' (tiers $from-$t)',
};

/// At most two decimals, trailing zeros dropped: 1.728 as "1.73".
String _short(double v) =>
    v.toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '');

/// [name] in the plural: "Station Docks", "Plate Presses", "Fuel
/// Refineries"; a name ending in "Works" stays as it is.
String plural(String name) {
  if (name.endsWith('Works')) return name;
  if (RegExp(r'[^aeiou]y$').hasMatch(name)) {
    return '${name.substring(0, name.length - 1)}ies';
  }
  if (RegExp(r'(s|x|ch|sh)$').hasMatch(name)) return '${name}es';
  return '${name}s';
}

/// The sentence builder: the state and content names come from.
final class _Words {
  _Words(this.s, this.c, this.factionId);

  final GameState s;
  final Content c;
  final String factionId;

  String res(String? id) => c.resources[id]?.name ?? id ?? 'goods';

  String body(String? id) =>
      s.bodies.where((b) => b.id == id).firstOrNull?.name ?? id ?? 'a body';

  String megaproject(String? id) => c.megaprojects[id]?.name ?? id ?? '';

  /// Building [id] and its body: on [bodyId], or on any body when the
  /// outcome names none (`CrewAssigned`).
  (BodyState?, BuildingState?) locate(String? bodyId, String? id) {
    for (final body in s.bodies) {
      if (bodyId != null && body.id != bodyId) continue;
      for (final b in body.buildings) {
        if (b.id == id) return (body, b);
      }
    }
    return (null, null);
  }

  BuildingState? building(String? bodyId, String? id) => locate(bodyId, id).$2;

  /// "Smelter on Kora": building [id] on [bodyId] by its type's name.
  String where(String? bodyId, String? id) {
    final (on, b) = locate(bodyId, id);
    final what = b == null ? 'A building' : c.buildings[b.defId]!.name;
    return '$what on ${on?.name ?? body(bodyId)}';
  }

  /// Rounded, but never 100% while held back.
  static int pct(double f) => math.min(99, (f * 100).round());

  FactionState? get faction =>
      s.factions.where((f) => f.id == factionId).firstOrNull;

  // Bottlenecks ------------------------------------------------------------

  String bottleneck(Bottleneck n) => switch (n.kind) {
    BottleneckKind.input when n.count > 1 =>
      '${groupWho(n)} are running as low as ${pct(n.runFraction)}%: '
          'not enough ${res(n.resourceId)}',
    BottleneckKind.input =>
      '${where(n.bodyId, n.buildingId)} is running at ${pct(n.runFraction)}%: '
          'not enough ${res(n.resourceId)}',
    BottleneckKind.noCrew when n.count > 1 => '${groupWho(n)} have no crew',
    BottleneckKind.noCrew => '${where(n.bodyId, n.buildingId)} has no crew',
    BottleneckKind.understaffed when n.count > 1 =>
      '${groupWho(n)} are understaffed',
    BottleneckKind.understaffed => understaffed(n),
    BottleneckKind.crewShortage => crewShortage(),
    BottleneckKind.storageFull when n.fromAbsence =>
      '${body(n.bodyId)} storage filled up with ${res(n.resourceId)} while '
          'you were away: output was wasted',
    BottleneckKind.storageFull =>
      '${body(n.bodyId)} storage is full of ${res(n.resourceId)}: output is '
          'being wasted',
    BottleneckKind.noSales =>
      'Nothing is being sold: turn on auto-sell or sell goods',
    BottleneckKind.megaprojectDiversion => diversion(n),
    BottleneckKind.keepBlocksDelivery => keepBlocks(n),
    BottleneckKind.routeLimited => '${whoIsRunning(n)}: ${routeLimit(n)}',
  };

  String understaffed(Bottleneck n) {
    final b = building(n.bodyId, n.buildingId);
    final slots = b == null ? 0 : c.buildings[b.defId]!.crewSlots;
    return '${where(n.bodyId, n.buildingId)} is understaffed: '
        '${b?.crew ?? 0} of $slots crew';
  }

  String crewShortage() {
    final t = crewTotals(s, c, factionId);
    return 'Your empire is short on crew: habitats and base crew support '
        '${t.supported} of ${t.assigned} assigned';
  }

  String diversion(Bottleneck n) {
    final share = math.min(100, ((n.shareOfSales ?? 0) * 100).round());
    final lost = n.lostCreditsPerHour ?? const BigNum.zero();
    return '${megaproject(n.megaprojectId)} takes $share% of the '
        '${res(n.resourceId)} that would sell: ${formatNumber(lost)} credits '
        'an hour not earned';
  }

  String keepBlocks(Bottleneck n) {
    final rule = faction?.autoSell
        .where((r) => r.bodyId == n.bodyId && r.resourceId == n.resourceId)
        .firstOrNull;
    final keep = rule == null ? '' : ' ${formatNumber(rule.keepAtLeast)}';
    final held = n.heldByKeep ?? const BigNum.zero();
    return '${megaproject(n.megaprojectId)} still needs ${res(n.resourceId)}, '
        'but ${body(n.bodyId)} keeps ${formatNumber(held)} of it back for its '
        'auto-sell keepAtLeast$keep';
  }

  /// "Smelter on Brine is running at 39%", or "2 Smelters on Brine are
  /// running as low as 39%" for a group.
  String whoIsRunning(Bottleneck n) => n.count > 1
      ? '${groupWho(n)} are running as low as ${pct(n.runFraction)}%'
      : '${where(n.bodyId, n.buildingId)} is running at ${pct(n.runFraction)}%';

  /// "Iron Ore into Brine is limited by the route's rate (10/s); raise its
  /// rate": what holds the route into the store back, and what raises it.
  String routeLimit(Bottleneck n) {
    final to = body(n.bodyId);
    final into = '${res(n.resourceId)} into $to is limited by';
    final rate = '${formatAmount(BigNum.from(n.routePerSec ?? 0))}/s';
    final route = s.routes.where((r) => r.id == n.routeId).firstOrNull;
    switch (n.binding ?? RouteLimit.rate) {
      case RouteLimit.rate:
        return "$into the route's rate ($rate); raise its rate";
      case RouteLimit.ships:
        final ships = route == null
            ? 'cargo ships'
            : this.ships(route.cargoShips);
        return "$into the route's $ships ($rate); assign more ships";
      case RouteLimit.destinationRoom:
        final depot = c.buildings.values
            .where((d) => d.kind == BuildingKind.warehouse)
            .firstOrNull;
        final raise = depot == null
            ? 'more storage there raises it'
            : 'a ${depot.name} raises it';
        return "$into $to's storage ($rate); $raise";
      case RouteLimit.stopLevel:
        return "$into the route's stop level ($rate); raise its stop level";
      case RouteLimit.sourceStock:
        final from = route == null ? 'its source' : body(route.fromBodyId);
        return '$into what $from has to send ($rate)';
    }
  }

  /// "17 Station Docks on Cinder": a group's buildings, by type when they
  /// share one.
  String groupWho(Bottleneck n) {
    final types = {
      for (final id in n.buildingIds) ?building(n.bodyId, id)?.defId,
    };
    final what = types.length == 1
        ? plural(c.buildings[types.single]!.name)
        : 'buildings';
    return '${n.count} $what on ${body(n.bodyId)}';
  }

  /// "2 Cargo Ships".
  String ships(int n) {
    final name = res(c.rules.cargoShipResource);
    return '$n $name${n == 1 ? '' : 's'}';
  }

  // Outcomes ---------------------------------------------------------------

  /// "5K credits and 20 Steel".
  String list(
    Map<String, BigNum> m, {
    NumberRounding rounding = NumberRounding.nearest,
  }) => [
    for (final MapEntry(key: k, value: v) in m.entries)
      k == creditsKey
          ? '${formatNumber(v, rounding: rounding)} credits'
          : '${formatNumber(v, rounding: rounding)} ${res(k)}',
  ].join(' and ');

  /// Game time from now until [at], as "2h 5m".
  String until(double at) => formatDuration(at - s.time);

  String outcome(Command cmd, CommandOutcome o) => switch (o) {
    Built() => built(o),
    Demolished(:final bodyId, :final defId) =>
      'Demolished ${c.buildings[defId]?.name ?? 'a building'} on '
          '${body(bodyId)}${o.gained.isEmpty ? '' : '; got back ${list(o.gained)}'}',
    CrewAssigned(:final bodyId, :final buildingId, :final crew) =>
      '${where(bodyId, buildingId)} now has $crew of '
          '${maxCrewOf(bodyId, buildingId)} crew',
    Upgraded(track: UpgradeTrack.capacity) => capacity(o),
    Upgraded(:final bodyId, :final buildingId, :final track, :final level) =>
      '${where(bodyId, buildingId)} is at ${trackLabel(track)} level $level, '
          'for ${list(o.spent)}',
    RouteCreated(:final routeId, :final stopClampedTo) =>
      'Created a route: ${routeText(routeId)}${clamped(routeId, stopClampedTo)}',
    RouteUpdated(:final routeId, :final stopClampedTo) =>
      'Updated the route: ${routeText(routeId)}${clamped(routeId, stopClampedTo)}',
    RouteRemoved(:final bodyId) =>
      'Closed a route from ${body(bodyId)}'
          '${o.gained.isEmpty ? '' : '; got back ${list(o.gained)}'}',
    ShipsSent(:final bodyId, :final toBodyId, :final count) =>
      'Sent ${ships(count)} from ${body(bodyId)} to ${body(toBodyId)}; '
          '${count == 1 ? 'it lands' : 'they land'} in ${until(o.arriveAt)}',
    Sold(:final bodyId, :final resourceId, :final amount, :final revenue) =>
      'Sold ${formatNumber(amount)} ${res(resourceId)} from ${body(bodyId)} '
          'for ${formatNumber(revenue)} credits',
    AutoSellSet(:final bodyId, :final resourceId, :final keepAtLeast) =>
      switch (keepAtLeast) {
        null => '${body(bodyId)} no longer auto-sells ${res(resourceId)}',
        final k when k.isZero =>
          '${body(bodyId)} now auto-sells all its ${res(resourceId)}',
        final k =>
          '${body(bodyId)} now auto-sells ${res(resourceId)} above '
              '${formatNumber(k)}',
      },
    ProjectStarted() => projectStarted(o),
    MegaprojectDelivered() => delivered(
      o,
      start: cmd is StartMegaprojectStageCommand,
    ),
    MegaprojectAutoSet() => autoText(o),
    AutoPayReserveSet(:final reserve) =>
      'Auto-pay now keeps ${formatNumber(reserve)} credits; the credits '
          'above it are shared out each game minute among the megaprojects '
          'taking credits on their own',
    ContractProgress(:final rewardPaid?) =>
      'Delivered ${formatNumber(o.delivered)} ${res(o.resourceId)} '
          '${fromText(o)} and completed the contract; paid '
          '${formatNumber(rewardPaid)} credits. '
          '${nextContract(o.nextContractAt, capital: true)}',
    ContractProgress() =>
      'Delivered ${formatNumber(o.delivered)} ${res(o.resourceId)} '
          '${fromText(o)} to ${contractName(o.contractId)} '
          '(${progress(o.totalDelivered, o.quantity)})',
    ContractDiscarded() =>
      'Discarded the contract for ${formatNumber(o.quantity)} '
          '${res(o.resourceId)}; ${nextContract(o.nextContractAt)}',
    UpgradesBought() => bought(o),
  };

  /// "Bought 3 upgrade levels on 2 buildings for 159 credits; the next
  /// costs 58.5 credits, more than the budget allows": what a buy-max
  /// bought and why it stopped, as the CLI says it.
  String bought(UpgradesBought o) {
    final next = formatNumber(o.nextCost ?? const BigNum.zero());
    final why = switch (o.stop) {
      UpgradeBuyStop.budget =>
        '${o.levels == 0 ? 'the cheapest' : 'the next'} costs $next credits, '
            'more than the budget allows',
      UpgradeBuyStop.maxPurchases =>
        'stopped at ${o.levels} levels, the most this command buys',
      UpgradeBuyStop.nothingToBuy => 'nothing is left to upgrade',
    };
    if (o.levels == 0) return 'Bought no upgrades: $why';
    final buildings = {for (final p in o.purchases) p.buildingId}.length;
    final levels = o.levels == 1
        ? '1 upgrade level'
        : '${o.levels} upgrade levels';
    final on = buildings == 1 ? '1 building' : '$buildings buildings';
    return 'Bought $levels on $on for ${formatNumber(o.total)} credits; $why';
  }

  static String trackLabel(UpgradeTrack t) => switch (t) {
    UpgradeTrack.speed => 'Speed',
    UpgradeTrack.efficiency => 'Efficiency',
    UpgradeTrack.capacity => 'Capacity',
  };

  int maxCrewOf(String? bodyId, String buildingId) {
    final b = building(bodyId, buildingId);
    return b == null ? 0 : maxCrew(c.rules, c.buildings[b.defId]!, b);
  }

  /// "the Veyra Exchange contract" while it is on the board; "the
  /// contract" once it has gone (a completed or discarded contract leaves
  /// the board, and its outcome names only its id).
  String contractName(String id) {
    final k = faction?.contracts.where((x) => x.id == id).firstOrNull;
    final issuer = c.contractTemplates[k?.templateId]?.issuer;
    return issuer == null ? 'the contract' : 'the $issuer contract';
  }

  /// "Built Smelter on Kora with 1 of 1 crew. At full crew it uses 0.4
  /// Iron Ore a second and makes 0.2 Steel a second".
  String built(Built o) {
    final def = c.buildings[o.defId]!;
    final slots = def.crewSlots;
    final staff = slots == 0 ? '' : ' with ${o.crew} of $slots crew';
    final (:inputs, :outputs) = builtRecipe(o, def);
    final runs = slots == 0 ? 'Running fully it' : 'At full crew it';
    final parts = [
      if (inputs.isNotEmpty) 'uses ${rateList(inputs)}',
      if (outputs.isNotEmpty) 'makes ${rateList(outputs)}',
      if (def.housing > 0) 'houses ${def.housing} crew',
    ];
    final what = parts.isEmpty ? '' : '. $runs ${parts.join(' and ')}';
    return 'Built ${def.name} on ${body(o.bodyId)}$staff$what';
  }

  /// Base-level rates a second with base crew full; an extractor's output
  /// is its deposit's resource at that deposit's richness.
  ({Map<String, BigNum> inputs, Map<String, BigNum> outputs}) builtRecipe(
    Built o,
    BuildingDef def,
  ) {
    if (!runsRecipe(def)) return (inputs: const {}, outputs: const {});
    Map<String, BigNum> perSecond(Map<String, double> perCycle) => {
      for (final MapEntry(key: id, value: v) in perCycle.entries)
        id: BigNum.from(v / def.cycleSeconds),
    };
    final inputs = perSecond(def.inputs);
    final outputs = perSecond(def.outputs);
    if (def.kind != BuildingKind.extractor) {
      return (inputs: inputs, outputs: outputs);
    }
    final b = building(o.bodyId, o.buildingId);
    final id = b?.depositResourceId;
    final deposit = s.bodies
        .where((x) => x.id == o.bodyId)
        .firstOrNull
        ?.deposits
        .where((d) => d.resourceId == id)
        .firstOrNull;
    return (
      inputs: inputs,
      outputs: {
        if (id != null && deposit != null && outputs[id] != null)
          id: outputs[id]!.mulDouble(deposit.richness),
      },
    );
  }

  /// "0.0333 Steel and 0.0133 Circuit a second".
  String rateList(Map<String, BigNum> m) {
    final items = [
      for (final MapEntry(key: id, value: v) in m.entries)
        '${formatAmount(v)} ${res(id)}',
    ];
    final last = items.removeLast();
    return '${items.isEmpty ? last : '${items.join(', ')} and $last'} '
        'a second';
  }

  String capacity(Upgraded o) {
    final b = building(o.bodyId, o.buildingId);
    final max = maxCrewOf(o.bodyId, o.buildingId);
    final what =
        '${where(o.bodyId, o.buildingId)} is at capacity level ${o.level}';
    if (b == null || max == 0) return '$what, for ${list(o.spent)}';
    final slots = c.rules.capacityCrewPerLevel == 1 ? 'slot' : 'slots';
    if (o.crewAdded > 0) {
      return '$what; ${o.crewAdded} free crew moved into its new $slots '
          '(${b.crew} of $max crew)';
    }
    return '$what; its new $slots ${slots == 'slot' ? 'is' : 'are'} empty '
        '(no free crew; ${b.crew} of $max crew)';
  }

  String projectStarted(ProjectStarted o) => switch (o.kind) {
    ProjectKind.claim =>
      'Started claiming ${body(o.targetId)} for ${list(o.spent)}'
          '${o.noKitsNeeded ? ' (no kits needed)' : ''}; done in '
          '${until(o.finishAt)}',
    ProjectKind.survey =>
      'Started a survey for ${list(o.spent)}; done in ${until(o.finishAt)}',
    ProjectKind.expandSlots =>
      'Started an extra build slot on ${body(o.targetId)} for '
          '${list(o.spent)}; done in ${until(o.finishAt)}',
    // Stages start from deliveries; named here should one start as a
    // project.
    ProjectKind.megaprojectStage =>
      'Started a ${megaproject(o.targetId)} stage; done in '
          '${until(o.finishAt)}',
  };

  /// What a delivery to a megaproject did, or with [start]
  /// (`StartMegaprojectStageCommand`) what paying for a stage did.
  String delivered(MegaprojectDelivered o, {required bool start}) {
    final name = megaproject(o.megaprojectId);
    final level = o.level;
    final from = body(o.bodyId);
    final paid = list(o.delivered);
    return switch (o) {
      MegaprojectDelivered(stageStarted: true, :final finishAt?) when start =>
        'Started $name level $level on $from for $paid; done in '
            '${until(finishAt)}',
      MegaprojectDelivered(queued: true, :final finishAt?) when start =>
        'Paid for $name level $level from $from with $paid; it starts when '
            'level ${level - 1} is done, in ${until(finishAt)}',
      MegaprojectDelivered(stageStarted: true, :final finishAt?) =>
        'Delivered $paid to $name level $level; level $level started, done '
            'in ${until(finishAt)}',
      MegaprojectDelivered(queued: true, :final finishAt?) =>
        'Delivered $paid to $name level $level; level $level starts when '
            'level ${level - 1} is done, in ${until(finishAt)}',
      _ =>
        'Delivered $paid to $name level $level; it still needs '
            '${list(o.remaining, rounding: NumberRounding.up)}',
    };
  }

  /// How [o] left a megaproject fed, as the CLI words it.
  String autoText(MegaprojectAutoSet o) {
    final name = megaproject(o.megaprojectId);
    final credits = o.credits ? creditShare(o.creditWeight) : 'no credits';
    final goods = switch (o.goods) {
      GoodsFeedMode.off => null,
      GoodsFeedMode.always => 'goods from every body each game minute',
      GoodsFeedMode.nearReady =>
        'goods from every body each game minute once a stage is near ready '
            '(its credits due within '
            '${formatDuration(c.rules.nearReadyHorizonSeconds)})',
    };
    if (goods != null) {
      return '$name now takes $goods, above what each keeps for its own use '
          'and open contracts, and $credits';
    }
    if (o.credits) {
      return '$name now takes $credits each game minute, and no goods';
    }
    return '$name is fed by hand only';
  }

  /// "a share of the credits above the auto-pay reserve (5M)", with the
  /// weight when it is not 1.
  String creditShare(int weight) {
    final reserve = faction?.autoPayReserve ?? const BigNum.zero();
    final above =
        'the credits above the auto-pay reserve (${formatNumber(reserve)})';
    return switch (weight) {
      0 => '$above only when nothing else takes them (weight 0)',
      1 => 'a share of $above',
      _ => 'a share, at weight $weight, of $above',
    };
  }

  String fromText(ContractProgress o) {
    if (o.bodyId case final id?) return 'from ${body(id)}';
    final parts = [
      for (final MapEntry(key: b, value: v) in o.fromBodies.entries)
        '${formatNumber(v)} from ${body(b)}',
    ];
    return '(${parts.join(', ')})';
  }

  /// "29.9K of 30K, 1 still owed": never "30K of 30K" while any is owed.
  static String progress(BigNum done, BigNum whole) {
    final got = done.floor();
    final owed = (whole - done).ceil();
    return '${formatNumber(got, rounding: NumberRounding.down)} of '
        '${formatNumber(whole)}, '
        '${formatNumber(owed, rounding: NumberRounding.up)} still owed';
  }

  String nextContract(double? at, {bool capital = false}) {
    final text = at == null
        ? 'no new contract is due'
        : at <= s.time
        ? 'a new contract is due now'
        : 'a new contract arrives in ${until(at)}';
    return capital ? '${text[0].toUpperCase()}${text.substring(1)}' : text;
  }

  /// "Iron Ore from Kora to Brine at 1/s with 1 Cargo Ship", and its stop
  /// level when it has one.
  String routeText(String id) {
    final r = s.routes.where((x) => x.id == id).firstOrNull;
    if (r == null) return 'a route';
    final to = body(r.toBodyId);
    final stop = switch (r.stopAtDestination) {
      final v? => ', pausing while $to holds ${formatNumber(v)}',
      null => '',
    };
    return '${res(r.resourceId)} from ${body(r.fromBodyId)} to $to at '
        '${formatAmount(r.ratePerSecond)}/s with ${ships(r.cargoShips)}$stop';
  }

  String clamped(String id, BigNum? stop) {
    if (stop == null) return '';
    final r = s.routes.where((x) => x.id == id).firstOrNull;
    return ". The stop level was cut to ${body(r?.toBodyId)}'s storage cap: "
        'stock above it is wasted';
  }
}
