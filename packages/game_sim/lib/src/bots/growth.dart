part of 'bot.dart';

/// The balanced bot's growth: the purchase that adds the most credits a
/// second for its price.
extension _Growth on _View {
  /// Share in `[0, 1]` of extra per-second input demand [inputs] on [body]
  /// that spare supply meets: local surplus, plus another body's when a
  /// route could bring it.
  double supplied(BodyState body, Map<String, BigNum> inputs) {
    var share = 1.0;
    for (final MapEntry(key: id, value: need) in inputs.entries) {
      final n = need.toDouble();
      if (n <= 0) continue;
      var spare = math.max(0.0, surplus(body, id));
      if (routeInto(body, id)) {
        spare = math.max(spare, n);
      } else if (routeSource(id, body) case final from?) {
        spare += math.max(0.0, surplus(from, id));
      }
      share = math.min(share, spare / n);
    }
    return share;
  }

  /// Credits per second that [extra] flow on [body] adds: its outputs at
  /// market price less the inputs used, both scaled by the share of the
  /// extra input demand that spare supply meets.
  ///
  /// Every output is worth its price because [autoSell] sells all surplus
  /// and the engine auto-sells before it clamps stock to the storage cap,
  /// so nothing a body makes is lost to the cap.
  double gain(BodyState body, BuildingFlow extra) {
    final share = supplied(body, extra.inputs);
    return value(extra) * share;
  }

  /// The purchase adding the most credits per second per credit that the
  /// faction can pay while keeping [reserve] credits: speed, efficiency and
  /// capacity upgrades (for their extra crew slot), new extractors and
  /// factories, and an extra build slot on a full body (valued as the best
  /// building it would take, priced with it). See [gain]. Storage is
  /// bought only when a store fills up ([fixBottleneck]). While saving,
  /// purchases up to [_pettyShare] of the credits held still go ahead.
  Command? grow({required BigNum reserve}) {
    final budget = (faction.credits - reserve).max(
      faction.credits.mulDouble(_pettyShare),
    );
    if (budget <= const BigNum.zero()) return null;
    Command? best;
    var bestRoi = 0.0;
    void consider(
      Command cmd,
      BodyState payer,
      Map<String, BigNum> cost,
      double gain,
    ) {
      final credits = cost['credits'] ?? const BigNum.zero();
      if (gain <= 0 || credits > budget || !canPay(payer, cost)) return;
      final roi = gain / math.max(1.0, credits.toDouble());
      if (roi > bestRoi) {
        best = cmd;
        bestRoi = roi;
      }
    }

    for (final body in owned) {
      for (final b in body.buildings) {
        final d = def(b);
        if (canUpgrade(b, UpgradeTrack.capacity) &&
            d.kind != BuildingKind.habitat &&
            freeCrew >= 1 &&
            b.crew > 0 &&
            _runsFreely(b) &&
            b.crew >= maxCrew(r, d, b)) {
          // One more crew slot, worth it when crew is free and this
          // building runs freely with every slot filled.
          final g = gain(body, _scaledFlow(flowOf(body, b), 1 / b.crew));
          consider(
            UpgradeCommand(factionId, b.id, UpgradeTrack.capacity),
            body,
            upgradeCost(c, b, UpgradeTrack.capacity),
            g,
          );
        }
        if (b.crew == 0 || !_runsFreely(b)) continue;
        if (d.kind == BuildingKind.habitat) continue;
        final flow = flowOf(body, b);
        if (canUpgrade(b, UpgradeTrack.speed)) {
          final level = b.levels[UpgradeTrack.speed]!;
          final more =
              speedMultiplier(r, level + 1) / speedMultiplier(r, level) - 1;
          consider(
            UpgradeCommand(factionId, b.id, UpgradeTrack.speed),
            body,
            upgradeCost(c, b, UpgradeTrack.speed),
            gain(body, _scaledFlow(flow, more)),
          );
        }
        if (canUpgrade(b, UpgradeTrack.efficiency) && flow.inputs.isNotEmpty) {
          final level = b.levels[UpgradeTrack.efficiency]!;
          final saved =
              1 -
              efficiencyMultiplier(r, level + 1) /
                  efficiencyMultiplier(r, level);
          consider(
            UpgradeCommand(factionId, b.id, UpgradeTrack.efficiency),
            body,
            upgradeCost(c, b, UpgradeTrack.efficiency),
            _worth(flow.inputs) * saved,
          );
        }
      }

      if (!hasFreeSlot(body)) {
        // An extra slot is worth what the best new building there would
        // add, for the slot and the building together.
        if (freeCrew < 1 || expanding(body)) continue;
        final slot = slotCost(c, body)['credits']!;
        for (final d in c.buildings.values) {
          if (d.kind != BuildingKind.extractor &&
              d.kind != BuildingKind.factory) {
            continue;
          }
          for (final dep in buildDeposits(d, body)) {
            if (_onlyFullMarkets(d, dep)) continue;
            consider(ExpandSlotsCommand(factionId, body.id), body, {
              ...d.buildCost,
              'credits': slot + (d.buildCost['credits'] ?? const BigNum.zero()),
            }, gain(body, probe(d, body, dep)));
          }
        }
        continue;
      }
      for (final d in c.buildings.values) {
        switch (d.kind) {
          case BuildingKind.warehouse:
            // Auto-sell keeps stock under the cap; storage earns nothing.
            continue;
          case BuildingKind.extractor || BuildingKind.factory:
            if (freeCrew < 1) continue;
            for (final dep in buildDeposits(d, body)) {
              if (_onlyFullMarkets(d, dep)) continue;
              consider(
                BuildCommand(factionId, body.id, d.id, depositResourceId: dep),
                body,
                d.buildCost,
                gain(body, probe(d, body, dep)),
              );
            }
          case BuildingKind.habitat:
            // Housing is a goal; see [pursueGoals].
            continue;
        }
      }
    }
    return best;
  }
}

BuildingFlow _scaledFlow(BuildingFlow f, double by) =>
    (inputs: _scaled(f.inputs, by), outputs: _scaled(f.outputs, by));

Map<String, BigNum> _scaled(Map<String, BigNum> m, double f) => {
  for (final MapEntry(key: id, value: v) in m.entries) id: v.mulDouble(f),
};
