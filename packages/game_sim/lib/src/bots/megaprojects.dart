part of 'bot.dart';

/// Megaproject stages: what they still want, deliveries toward them and
/// the steps toward paying for the next one.
extension _Megaprojects on _View {
  /// Units of [resourceId] the megaprojects still want for the stages
  /// being paid for, summed: what each still lacks ([megaprojectRemaining];
  /// while a stage is under way, of the one after it); zero when none
  /// uses it.
  BigNum stageNeed(String resourceId) => _owedToStages(resourceId);

  /// [stageNeed] of the megaprojects whose goods the bot delivers by hand:
  /// for those fed on their own ([autoDeliver]) the engine's auto-sell
  /// already holds back what they lack.
  BigNum handStageNeed(String resourceId) =>
      _owedToStages(resourceId, handOnly: true);

  /// Whether deliveries to [m] can go on: it is open
  /// ([megaprojectLockedBy]) and the stage they pay for is below the
  /// highest level ([megaprojectDeliveryLevel]).
  bool _deliverable(MegaprojectDef m) =>
      megaprojectLockedBy(s, c, factionId, m) == null &&
      megaprojectDeliveryLevel(s, factionId, m) < SaveCodec.maxMegaprojectLevel;

  /// Seconds of income the bot keeps back when megaprojects take its
  /// credits on their own ([autoDeliver]).
  static const double creditReserveSeconds = 3600;

  /// One change to how megaprojects are fed on their own, the first that
  /// is needed; null when every setting is as wanted.
  ///
  /// Once a megaproject is open ([megaprojectLockedBy]) and its host is
  /// owned, every body feeds it goods once its stage is near ready
  /// ([GoodsFeedMode.nearReady]). Its credits go in on their own, at
  /// weight 1, once every good the stage being paid for still lacks is
  /// made or held ([_fundable]): from then the stage is only waiting on
  /// what the economy makes, and the credits above the faction's shared
  /// auto-pay reserve go in as they are earned, so none sit idle and its
  /// goods start [RulesDef.nearReadyHorizonSeconds] before its credits
  /// are in. Before that, credits paid in would sit in a stage the empire
  /// cannot finish instead of growing the economy that makes its goods.
  /// The reserve, [creditReserveSeconds] of income plus what the bot is
  /// saving for a goal ([_savingFor]), is set before any credits go in,
  /// and kept while within a factor of two of what is wanted.
  Command? autoDeliver() {
    Command? setting;
    var anyCredits = false;
    for (final m in c.megaprojects.values) {
      if (megaprojectLockedBy(s, c, factionId, m) != null) continue;
      if (m.hostBodyType case final t? when !owned.any((b) => b.typeId == t)) {
        continue;
      }
      final now = faction.megaprojectAuto[m.id];
      final payCredits = _deliverable(m) && _fundable(m);
      anyCredits = anyCredits || payCredits;
      if (now != null &&
          now.goods == GoodsFeedMode.nearReady &&
          now.credits == payCredits &&
          now.creditWeight == _weightOf(m)) {
        continue;
      }
      setting ??= SetMegaprojectAutoCommand(
        factionId,
        m.id,
        goods: GoodsFeedMode.nearReady,
        credits: payCredits,
        creditWeight: _weightOf(m),
      );
    }
    if (anyCredits) {
      final want = _creditReserve();
      if (!_closeEnough(faction.autoPayReserve, want)) {
        return SetAutoPayReserveCommand(factionId, want);
      }
    }
    return setting;
  }

  /// The credit weight the bot gives [m] ([_View.creditWeights]; 1 when
  /// it names none).
  int _weightOf(MegaprojectDef m) => creditWeights[m.id] ?? 1;

  /// Whether every good the stage of [m] being paid for still lacks
  /// ([megaprojectRemaining]) is made by a staffed building ([made]) or
  /// held, all of it, across the owned bodies; true when it lacks only
  /// credits.
  bool _fundable(MegaprojectDef m) {
    for (final MapEntry(key: id, value: need) in megaprojectRemaining(
      s,
      c,
      factionId,
      m,
    ).entries) {
      if (id == 'credits' || made(id)) continue;
      final held = owned.fold(const BigNum.zero(), (t, b) => t + stock(b, id));
      if (held < need) return false;
    }
    return true;
  }

  /// Whether credit reserve [now] can stay for one of [want]: within a
  /// factor of two, so the reserve is not reset for every small change of
  /// income.
  bool _closeEnough(BigNum now, BigNum want) =>
      now.mulDouble(2) >= want && want.mulDouble(2) >= now;

  /// Credits [autoDeliver] keeps back: [creditReserveSeconds] of income, in
  /// whole credits, plus what the bot is saving for a goal ([_savingFor]).
  BigNum _creditReserve() {
    final perSec = report != null || _planIncome != null
        ? income
        : math.max(
            0.0,
            buildFlowReport(s, c, factionId).creditsPerSec.toDouble(),
          );
    return BigNum.from(perSec * creditReserveSeconds).floor() + _savingFor();
  }

  /// Credits the bot saves for its next goal ([pursueGoals]), which credit
  /// auto-pay must leave it: what the plan passed in, else zero.
  BigNum _savingFor() => _planSaving?.call() ?? const BigNum.zero();

  /// Whether goods go into [m] on their own ([autoDeliver]).
  bool _fedGoods(MegaprojectDef m) =>
      (faction.megaprojectAuto[m.id]?.goods ?? GoodsFeedMode.off) !=
      GoodsFeedMode.off;

  /// Whether [m] takes credits on its own ([autoDeliver]).
  bool _fedCredits(MegaprojectDef m) =>
      faction.megaprojectAuto[m.id]?.credits ?? false;

  /// One delivery by hand toward the stage being paid for of the first
  /// megaproject, in content order, whose goods the engine does not feed
  /// it on its own ([autoDeliver]) (while a stage is under way, the one
  /// after it): the goods it still lacks from the first owned body holding
  /// at least one whole unit more of them than it keeps for its own use
  /// ([keepForUse]), body order. Null if there is nothing to deliver.
  /// Credits go in on their own ([autoDeliver]).
  ///
  /// Deliveries add up, so goods go in as they are made, from every body,
  /// and the stage's timer starts as soon as the last of its cost is in,
  /// or as the stage under way completes.
  Command? deliverMegaproject() {
    for (final m in c.megaprojects.values) {
      if (!_deliverable(m) || _fedGoods(m)) continue;
      if (m.hostBodyType case final t? when !owned.any((b) => b.typeId == t)) {
        continue;
      }
      final owed = megaprojectRemaining(s, c, factionId, m);
      for (final body in owned) {
        final give = <String, BigNum>{};
        for (final MapEntry(key: id, value: need) in owed.entries) {
          if (id == 'credits') continue;
          // Deliveries move whole units.
          final spare = (stock(body, id) - keepForUse(body, id)).floor();
          if (spare > const BigNum.zero()) give[id] = spare.min(need);
        }
        if (give.isNotEmpty) {
          return DeliverToMegaprojectCommand(factionId, m.id, body.id, give);
        }
      }
    }
    return null;
  }

  /// The next step toward the stage of [m] being paid for (while one is
  /// under way, the one after it): making each good it still lacks
  /// ([ensureMade], which also feeds makers that stand idle), then saving
  /// its credits once every good is in. [_Waiting] once it is paid for or
  /// while goods are on their way.
  _Step _ensureStage(MegaprojectDef m) {
    if (!_deliverable(m)) return const _Waiting();
    final owed = megaprojectRemaining(s, c, factionId, m);
    final goods = [
      for (final id in owed.keys)
        if (id != 'credits') id,
    ];
    for (final id in goods) {
      final step = ensureMade(id);
      if (_acts(step)) return step;
    }
    if (_growFor(m, owed) case final step?) return step;
    // Credits fed on their own come as they are earned.
    if (_onlyCredits(owed) case final credits? when !_fedCredits(m)) {
      return _Save(credits, stage: true);
    }
    return const _Waiting();
  }

  /// A step toward more of the good [m] still lacks ([owed]) that is
  /// slowest to come, when at today's surplus ([surplus], over the owned
  /// bodies) it takes longer than [_stageGoodsWithinSeconds], or never
  /// comes ([_grow]): so the economy grows toward what the megaprojects
  /// take, not only toward what sells. Null when every good comes soon
  /// enough, or no step helps. Once per megaproject per decision: a new
  /// maker adds to the surplus only once it has run, and the other
  /// megaprojects get their turn.
  _Step? _growFor(MegaprojectDef m, Map<String, BigNum> owed) {
    if (report == null || _grown.contains(m.id)) return null;
    String? slowest;
    var longest = _stageGoodsWithinSeconds;
    for (final MapEntry(key: id, value: need) in owed.entries) {
      if (id == 'credits') continue;
      final rate = owned.fold(0.0, (t, b) => t + math.max(0.0, surplus(b, id)));
      // Megaprojects before [m] in content order take a good they share
      // first, as auto-delivery feeds them in that order.
      final ahead = _owedBefore(m, id);
      final seconds = rate > 0
          ? (need + ahead).toDouble() / rate
          : double.infinity;
      if (seconds > longest) {
        slowest = id;
        longest = seconds;
      }
    }
    if (slowest == null) return null;
    _grown.add(m.id);
    final step = _grow(slowest, const {});
    return _acts(step) ? step : null;
  }

  /// The next step toward making more [resourceId]: when a maker of it is
  /// held back by an input, getting it that input ([_feedMaker]), or
  /// growing the input's own supply in turn once it is made and within
  /// reach; otherwise another maker ([ensureMade]). [visiting] holds the
  /// goods already being grown, so a loop of recipes ends.
  _Step _grow(String resourceId, Set<String> visiting) {
    if (visiting.length > _maxChainDepth || visiting.contains(resourceId)) {
      return const _Stuck();
    }
    final deeper = {...visiting, resourceId};
    for (final (body, b) in buildings) {
      if (b.crew == 0 || !makes(b, resourceId) || _runsFreely(b)) continue;
      final reason = b.lastLimitReason!;
      if (!reason.startsWith('input:')) continue;
      final fed = _feedMaker(body, b, deeper);
      if (_acts(fed)) return fed;
      // Made and on its way, but too little of it: grow that, or, when
      // that leads nowhere (an input already being grown), try the next
      // maker, then another maker of it.
      final grown = _grow(reason.substring('input:'.length), deeper);
      if (_acts(grown)) return grown;
    }
    return ensureMade(resourceId, visiting, true);
  }

  /// Units of [resourceId] the megaprojects before [m] in content order
  /// still lack for the stages being paid for ([megaprojectRemaining]).
  BigNum _owedBefore(MegaprojectDef m, String resourceId) {
    var total = const BigNum.zero();
    for (final other in c.megaprojects.values) {
      if (other.id == m.id) break;
      if (!_deliverable(other)) continue;
      final owed = megaprojectRemaining(s, c, factionId, other)[resourceId];
      if (owed != null) total = total + owed;
    }
    return total;
  }

  /// Units of [resourceId] the megaproject stages being paid for still
  /// lack, summed (while a stage is under way, the one after it); with
  /// [handOnly], only of those not fed goods on their own.
  BigNum _owedToStages(String resourceId, {bool handOnly = false}) {
    var total = const BigNum.zero();
    for (final m in c.megaprojects.values) {
      if (!m.baseCost.containsKey(resourceId) || !_deliverable(m)) continue;
      if (handOnly && _fedGoods(m)) continue;
      final owed = megaprojectRemaining(s, c, factionId, m)[resourceId];
      if (owed != null) total = total + owed;
    }
    return total;
  }
}

/// The credits [owed] holds when they are all it holds, else null.
BigNum? _onlyCredits(Map<String, BigNum> owed) =>
    owed.length == 1 ? owed['credits'] : null;
