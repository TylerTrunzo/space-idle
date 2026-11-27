part of 'bot.dart';

/// Megaproject stages: what they still want, deliveries toward them and
/// the steps toward paying for the next one.
extension _Megaprojects on _View {
  /// Units of [resourceId] the megaprojects still want for the stages
  /// being paid for, summed: what each still lacks ([megaprojectRemaining];
  /// while a stage is under way, of the one after it); zero when none
  /// uses it.
  BigNum stageNeed(String resourceId) => _owedToStages(resourceId);

  /// Whether deliveries to [m] can go on: the stage they pay for is below
  /// the highest level ([megaprojectDeliveryLevel]).
  bool _deliverable(MegaprojectDef m) =>
      megaprojectDeliveryLevel(s, factionId, m) < SaveCodec.maxMegaprojectLevel;

  /// One delivery toward the stage being paid for of the first
  /// megaproject, in content order, that still lacks something (while a
  /// stage is under way, the one after it): the goods it still lacks from
  /// the first owned body holding at least one whole unit more of them
  /// than it keeps for its own use ([keepForUse]), body order; once every
  /// good is in, the credits, when the faction holds them all. Null if
  /// there is nothing to deliver.
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
    if (_onlyCredits(owed) case final credits?) return _Save(credits);
    return const _Waiting();
  }

  /// Units of [resourceId] the megaproject stages being paid for still
  /// lack, summed (while a stage is under way, the one after it).
  BigNum _owedToStages(String resourceId) {
    var total = const BigNum.zero();
    for (final m in c.megaprojects.values) {
      if (!m.baseCost.containsKey(resourceId) || !_deliverable(m)) continue;
      final owed = megaprojectRemaining(s, c, factionId, m)[resourceId];
      if (owed != null) total = total + owed;
    }
    return total;
  }
}

/// The credits [owed] holds when they are all it holds, else null.
BigNum? _onlyCredits(Map<String, BigNum> owed) =>
    owed.length == 1 ? owed['credits'] : null;
