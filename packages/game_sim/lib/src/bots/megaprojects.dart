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

  /// One change to how a megaproject is fed on its own, the first in
  /// content order that needs one; null when every setting is as wanted.
  ///
  /// Once a megaproject is open ([megaprojectLockedBy]) and its host is
  /// owned, every body feeds it goods. Its credits go in on their own,
  /// above a reserve of [creditReserveSeconds] of income, only while they
  /// are all the stage being paid for still lacks; at the next decision
  /// after that stage is paid for, they stop again. Paid in earlier, credits
  /// would sit in a stage still short of goods instead of growing the
  /// economy that makes them: in 21-day runs that kept the casual bot's
  /// first station level a day later and its income lower.
  Command? autoDeliver() {
    for (final m in c.megaprojects.values) {
      if (megaprojectLockedBy(s, c, factionId, m) != null) continue;
      if (m.hostBodyType case final t? when !owned.any((b) => b.typeId == t)) {
        continue;
      }
      final now = faction.megaprojectAuto[m.id];
      final payCredits =
          _deliverable(m) &&
          _onlyCredits(megaprojectRemaining(s, c, factionId, m)) != null;
      final reserve = payCredits ? _creditReserve() : null;
      if (now != null &&
          now.goods &&
          _closeEnough(now.creditReserve, reserve)) {
        continue;
      }
      return SetMegaprojectAutoCommand(factionId, m.id, true, reserve);
    }
    return null;
  }

  /// Whether credit reserve [now] can stay for one of [want]: both none,
  /// or both set and within a factor of two, so the reserve is not reset
  /// for every small change of income.
  bool _closeEnough(BigNum? now, BigNum? want) {
    if (now == null || want == null) return now == want;
    return now.mulDouble(2) >= want && want.mulDouble(2) >= now;
  }

  /// Credits [autoDeliver] keeps back: [creditReserveSeconds] of income, in
  /// whole credits.
  BigNum _creditReserve() {
    final perSec = report != null || _planIncome != null
        ? income
        : math.max(
            0.0,
            buildFlowReport(s, c, factionId).creditsPerSec.toDouble(),
          );
    return BigNum.from(perSec * creditReserveSeconds).floor();
  }

  /// Whether goods go into [m] on their own ([autoDeliver]).
  bool _fedGoods(MegaprojectDef m) =>
      faction.megaprojectAuto[m.id]?.goods ?? false;

  /// Whether [m] takes credits on its own ([autoDeliver]).
  bool _fedCredits(MegaprojectDef m) =>
      faction.megaprojectAuto[m.id]?.creditReserve != null;

  /// One delivery by hand toward the stage being paid for of the first
  /// megaproject, in content order, that still lacks something the engine
  /// does not feed it on its own ([autoDeliver]) (while a stage is under
  /// way, the one after it): the goods it still lacks from the first owned
  /// body holding at least one whole unit more of them than it keeps for
  /// its own use ([keepForUse]), body order; once every good is in, the
  /// credits, when the faction holds them all. Null if there is nothing to
  /// deliver.
  ///
  /// Deliveries add up, so goods go in as they are made, from every body,
  /// and the stage's timer starts as soon as the last of its cost is in,
  /// or as the stage under way completes.
  Command? deliverMegaproject() {
    for (final m in c.megaprojects.values) {
      if (!_deliverable(m)) continue;
      if (m.hostBodyType case final t? when !owned.any((b) => b.typeId == t)) {
        continue;
      }
      final owed = megaprojectRemaining(s, c, factionId, m);
      if (!_fedGoods(m)) {
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
      if (_fedCredits(m)) continue;
      if (_onlyCredits(owed) case final credits?
          when faction.credits >= credits) {
        return DeliverToMegaprojectCommand(factionId, m.id, owned.first.id, {
          'credits': credits,
        });
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
    if (_onlyCredits(owed) case final credits?) return _Save(credits);
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
      final seconds = rate > 0 ? need.toDouble() / rate : double.infinity;
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
      // Made and on its way, but too little of it: grow that.
      return _grow(reason.substring('input:'.length), deeper);
    }
    return ensureMade(resourceId, visiting, true);
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
