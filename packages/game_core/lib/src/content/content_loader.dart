import '../num/big_num.dart';
import '../num/format.dart';
import 'content.dart';

/// Parses and validates a content bundle; backs [Content.fromBundle].
///
/// Never throws. Problems are collected as `"<path>: <message>"` in three
/// passes: shape (types, ranges, unknown fields), references (every id
/// points at something), then the recipe graph (every resource is made from
/// deposits and is used or sold). The graph pass runs only when the first
/// two found nothing, so one typo does not cascade into many errors.
ContentResult loadContentBundle(Map<String, Object?> bundle) =>
    _Loader().load(bundle);

const _sections = {
  'rules',
  'resources',
  'buildings',
  'body_types',
  'galaxy',
  'milestones',
  'megaprojects',
  'contracts',
};

const _credits = 'credits';

final _idPattern = RegExp(r'^[a-z][a-z0-9_]*$');

String _fmt(double v) => v == v.roundToDouble() && v.abs() < 1e15
    ? v.toInt().toString()
    : v.toString();

final class _Loader {
  final _errors = <String>[];

  // Every id seen in a well-formed entry, even if the rest of the entry was
  // invalid, so references to it do not produce follow-on errors.
  final _resourceIds = <String>{};
  final _buildingIds = <String>{};
  final _bodyTypeIds = <String>{};
  final _systemIds = <String>{};
  final _bodyIds = <String>{};
  final _factionIds = <String>{};
  final _milestoneIds = <String>{};
  final _megaprojectIds = <String>{};
  final _contractTemplateIds = <String>{};

  void err(String path, String message) => _errors.add('$path: $message');

  ContentResult load(Map<String, Object?> bundle) {
    for (final key in bundle.keys) {
      if (!_sections.contains(key)) err(key, 'unknown field');
    }

    final rules = _rules(bundle['rules']);
    final resources = _entries(
      'resources',
      _listAt('resources', bundle['resources']),
      _resourceIds,
      const {'id', 'name', 'tier', 'basePrice', 'marketDepth', 'marketFloor'},
      _resource,
    );
    final buildings = _entries(
      'buildings',
      _listAt('buildings', bundle['buildings']),
      _buildingIds,
      const {
        'id',
        'name',
        'kind',
        'cycleSeconds',
        'inputs',
        'outputs',
        'extracts',
        'crewSlots',
        'housing',
        'storageBonus',
        'buildCost',
        'upgrades',
      },
      _building,
    );
    final bodyTypes = _entries(
      'body_types',
      _listAt('body_types', bundle['body_types']),
      _bodyTypeIds,
      const {'id', 'name', 'depositPool', 'buildSlots'},
      _bodyType,
    );
    final galaxy = _galaxy(bundle['galaxy']);
    final milestones = _entries(
      'milestones',
      _listAt('milestones', bundle['milestones']),
      _milestoneIds,
      const {'id', 'name', 'condition'},
      _milestone,
    );
    // Optional: content without the file has no megaprojects.
    final megaprojects = bundle.containsKey('megaprojects')
        ? _entries(
            'megaprojects',
            _listAt('megaprojects', bundle['megaprojects']),
            _megaprojectIds,
            const {
              'id',
              'name',
              'hostBodyType',
              'baseCost',
              'costGrowth',
              'stageSeconds',
              'stageSecondsGrowth',
              'bonusesPerLevel',
            },
            _megaproject,
          )
        : <String, MegaprojectDef>{};
    // Optional: content without the file posts no contracts.
    final contractTemplates = bundle.containsKey('contracts')
        ? _entries(
            'contracts',
            _listAt('contracts', bundle['contracts']),
            _contractTemplateIds,
            const {
              'id',
              'issuer',
              'minTier',
              'maxTier',
              'quantitySeconds',
              'rewardMultiplier',
              'minQuantity',
              'maxQuantity',
              'rewardIncomeSeconds',
              'rewardCapIncomeSeconds',
            },
            _contractTemplate,
          )
        : <String, ContractTemplateDef>{};

    if (rules != null) _checkRules(rules, galaxy);
    _checkBuildings(buildings);
    _checkBodyTypes(bodyTypes);
    if (galaxy != null) _checkGalaxy(galaxy, buildings, bodyTypes);
    _checkMilestones(milestones, buildings, galaxy);
    _checkMegaprojects(megaprojects);

    if (_errors.isEmpty) {
      _checkGraph(rules!, resources, buildings, galaxy!, megaprojects);
    }
    if (_errors.isNotEmpty) return ContentInvalid(_errors);
    return ContentOk(
      Content(
        rules: rules!,
        resources: resources,
        buildings: buildings,
        bodyTypes: bodyTypes,
        galaxy: galaxy!,
        milestones: milestones.values.toList(),
        megaprojects: megaprojects,
        contractTemplates: contractTemplates,
      ),
    );
  }

  // ---------------------------------------------------------------- shape

  _Fields? _objectAt(String path, Object? v, Set<String> allowed) {
    if (v is Map<String, Object?>) return _Fields(this, path, v, allowed);
    err(path, v == null ? 'missing' : 'expected an object');
    return null;
  }

  List<Object?>? _listAt(String path, Object? v) {
    if (v is List<Object?>) return v;
    err(path, v == null ? 'missing' : 'expected a list');
    return null;
  }

  /// Parses each object in [list] that has a valid, unique id.
  Map<String, T> _entries<T>(
    String section,
    List<Object?>? list,
    Set<String> ids,
    Set<String> allowed,
    T? Function(_Fields f, String id) parse,
  ) {
    final out = <String, T>{};
    if (list == null) return out;
    for (var i = 0; i < list.length; i++) {
      final e = list[i];
      final at = '$section[$i]';
      if (e is! Map<String, Object?>) {
        err(at, 'expected an object');
        continue;
      }
      final id = _idOf(at, e['id']);
      if (id == null) continue;
      final path = '$section.$id';
      if (!ids.add(id)) {
        err(path, 'duplicate id');
        continue;
      }
      final def = parse(_Fields(this, path, e, allowed), id);
      if (def != null) out[id] = def;
    }
    return out;
  }

  String? _idOf(String at, Object? v) {
    if (v == null) {
      err('$at.id', 'missing');
    } else if (v is! String || !_idPattern.hasMatch(v)) {
      err(
        '$at.id',
        'expected lowercase letters, digits, and underscores, '
            'starting with a letter',
      );
    } else {
      return v;
    }
    return null;
  }

  double? number(String path, Object? v, {double? gt, double? ge, double? le}) {
    if (v is! num || !v.isFinite) {
      err(path, 'expected a number');
      return null;
    }
    final d = v.toDouble();
    if (gt != null && !(d > gt)) {
      err(path, 'must be > ${_fmt(gt)}');
    } else if (ge != null && !(d >= ge)) {
      err(path, 'must be >= ${_fmt(ge)}');
    } else if (le != null && !(d <= le)) {
      err(path, 'must be <= ${_fmt(le)}');
    } else {
      return d;
    }
    return null;
  }

  BigNum? bigNum(String path, Object? v, {bool positive = false}) {
    BigNum? b;
    if (v is String) {
      try {
        b = BigNum.parse(v);
      } on FormatException {
        b = null;
      }
    }
    if (b == null) {
      err(path, 'expected a number string like "5e3"');
    } else if (b.isNegative) {
      err(path, 'must be >= 0');
    } else if (positive && b.isZero) {
      err(path, 'must be > 0');
    } else {
      return b;
    }
    return null;
  }

  RulesDef? _rules(Object? raw) {
    final f = _objectAt('rules', raw, const {
      'speedPerLevel',
      'speedMilestoneEvery',
      'speedMilestoneMult',
      'efficiencyPerLevel',
      'efficiencyFloor',
      'capacityCrewPerLevel',
      'capacityStoragePerLevel',
      'capacityHousingPerLevel',
      'baseStorageCap',
      'offlineCapSeconds',
      'marketFloor',
      'marketRecoverySeconds',
      'claimBaseCredits',
      'claimGrowth',
      'claimKitsBase',
      'claimKitsPerOwned',
      'slotBaseCredits',
      'slotGrowth',
      'outpostKitResource',
      'shipCapacityPerSecond',
      'cargoShipResource',
      'baseTravelSeconds',
      'shipmentMergeSeconds',
      'claimSecondsBase',
      'claimSecondsPerOwned',
      'expandSlotsSeconds',
      'contractRefillSeconds',
      'surveyDrones',
      'surveyCredits',
      'surveySeconds',
      'surveyDroneResource',
    });
    if (f == null) return null;
    final before = _errors.length;
    final speedPerLevel = f.number('speedPerLevel', ge: 1);
    final speedMilestoneEvery = f.integer('speedMilestoneEvery', min: 1);
    final speedMilestoneMult = f.number('speedMilestoneMult', ge: 1);
    final efficiencyPerLevel = f.number('efficiencyPerLevel', gt: 0, le: 1);
    final efficiencyFloor = f.number('efficiencyFloor', gt: 0, le: 1);
    final capacityCrewPerLevel = f.integer('capacityCrewPerLevel', min: 0);
    final capacityStoragePerLevel = f.number('capacityStoragePerLevel', ge: 0);
    final capacityHousingPerLevel = f.number(
      'capacityHousingPerLevel',
      fallback: RulesDef.defaultCapacityHousingPerLevel,
      ge: 0,
    );
    final baseStorageCap = f.number('baseStorageCap', gt: 0);
    final offlineCapSeconds = f.number(
      'offlineCapSeconds',
      gt: 0,
      le: RulesDef.maxOfflineCapSeconds,
    );
    final marketFloor = f.number('marketFloor', ge: 0, le: 1);
    final marketRecoverySeconds = f.number('marketRecoverySeconds', gt: 0);
    final claimBaseCredits = f.bigNum('claimBaseCredits');
    final claimGrowth = f.number('claimGrowth', ge: 1);
    final claimKitsBase = f.integer(
      'claimKitsBase',
      fallback: RulesDef.defaultClaimKitsBase,
      min: 0,
    );
    final claimKitsPerOwned = f.integer(
      'claimKitsPerOwned',
      fallback: RulesDef.defaultClaimKitsPerOwned,
      min: 0,
    );
    final slotBaseCredits = f.bigNum('slotBaseCredits', positive: true);
    final slotGrowth = f.number('slotGrowth', gt: 1);
    final outpostKitResource = f.string('outpostKitResource');
    final shipCapacityPerSecond = f.number('shipCapacityPerSecond', gt: 0);
    final cargoShipResource = f.string('cargoShipResource');
    final baseTravelSeconds = f.number('baseTravelSeconds', gt: 0);
    final shipmentMergeSeconds = f.number(
      'shipmentMergeSeconds',
      fallback: RulesDef.defaultShipmentMergeSeconds,
      ge: 0,
    );
    final claimSecondsBase = f.number(
      'claimSecondsBase',
      fallback: RulesDef.defaultClaimSecondsBase,
      ge: 0,
    );
    final claimSecondsPerOwned = f.number(
      'claimSecondsPerOwned',
      fallback: RulesDef.defaultClaimSecondsPerOwned,
      ge: 0,
    );
    final expandSlotsSeconds = f.number(
      'expandSlotsSeconds',
      fallback: RulesDef.defaultExpandSlotsSeconds,
      ge: RulesDef.minProjectSeconds,
      le: RulesDef.maxProjectSeconds,
    );
    final contractRefillSeconds = f.number(
      'contractRefillSeconds',
      fallback: RulesDef.defaultContractRefillSeconds,
      gt: 0,
    );
    final surveyDrones = f.integer(
      'surveyDrones',
      fallback: RulesDef.defaultSurveyDrones,
      min: 0,
    );
    final surveyCredits = f.bigNum('surveyCredits', optional: true);
    final surveySeconds = f.number(
      'surveySeconds',
      fallback: RulesDef.defaultSurveySeconds,
      ge: RulesDef.minProjectSeconds,
      le: RulesDef.maxProjectSeconds,
    );
    final surveyDroneResource =
        f.string('surveyDroneResource', optional: true) ??
        RulesDef.defaultSurveyDroneResource;
    if (_errors.length > before) return null;
    return RulesDef(
      speedPerLevel: speedPerLevel!,
      speedMilestoneEvery: speedMilestoneEvery!,
      speedMilestoneMult: speedMilestoneMult!,
      efficiencyPerLevel: efficiencyPerLevel!,
      efficiencyFloor: efficiencyFloor!,
      capacityCrewPerLevel: capacityCrewPerLevel!,
      capacityStoragePerLevel: capacityStoragePerLevel!,
      capacityHousingPerLevel: capacityHousingPerLevel!,
      baseStorageCap: baseStorageCap!,
      offlineCapSeconds: offlineCapSeconds!,
      marketFloor: marketFloor!,
      marketRecoverySeconds: marketRecoverySeconds!,
      claimBaseCredits: claimBaseCredits!,
      claimGrowth: claimGrowth!,
      claimKitsBase: claimKitsBase!,
      claimKitsPerOwned: claimKitsPerOwned!,
      slotBaseCredits: slotBaseCredits!,
      slotGrowth: slotGrowth!,
      outpostKitResource: outpostKitResource!,
      shipCapacityPerSecond: shipCapacityPerSecond!,
      cargoShipResource: cargoShipResource!,
      baseTravelSeconds: baseTravelSeconds!,
      shipmentMergeSeconds: shipmentMergeSeconds!,
      claimSecondsBase: claimSecondsBase!,
      claimSecondsPerOwned: claimSecondsPerOwned!,
      expandSlotsSeconds: expandSlotsSeconds!,
      contractRefillSeconds: contractRefillSeconds!,
      surveyDrones: surveyDrones!,
      surveyCredits: surveyCredits,
      surveySeconds: surveySeconds!,
      surveyDroneResource: surveyDroneResource,
    );
  }

  ResourceDef? _resource(_Fields f, String id) {
    final before = _errors.length;
    if (id == _credits) f.err('id', "'$_credits' is reserved for currency");
    final name = f.string('name');
    final tier = f.integer('tier', min: 0, max: ResourceDef.megaprojectTier);
    final basePrice = f.bigNum('basePrice');
    final marketDepth = f.number(
      'marketDepth',
      fallback: ResourceDef.defaultMarketDepth,
      gt: 0,
    );
    final marketFloor = f.map.containsKey('marketFloor')
        ? f.number('marketFloor', ge: 0, le: 1)
        : null;
    if (_errors.length > before) return null;
    return ResourceDef(
      id: id,
      name: name!,
      tier: tier!,
      basePrice: basePrice!,
      marketDepth: marketDepth!,
      marketFloor: marketFloor,
    );
  }

  BuildingDef? _building(_Fields f, String id) {
    final before = _errors.length;
    final name = f.string('name');
    final kind = f.choice('kind', BuildingKind.values, 'kind');
    final cycleSeconds = f.number('cycleSeconds', gt: 0);
    final inputs = f.rates('inputs');
    final outputs = f.rates('outputs');
    final extracts = f.stringList('extracts', optional: true);
    final crewSlots = f.integer('crewSlots', min: 0);
    final housing = f.integer('housing', fallback: 0, min: 0);
    final storageBonus = f.number('storageBonus', fallback: 0, ge: 0);
    final buildCost = f.amounts('buildCost', positive: true);
    final upgrades = _upgrades(f);
    if (_errors.length > before) return null;
    final def = BuildingDef(
      id: id,
      name: name!,
      kind: kind!,
      cycleSeconds: cycleSeconds!,
      inputs: inputs!,
      outputs: outputs!,
      extracts: extracts!,
      crewSlots: crewSlots!,
      housing: housing!,
      storageBonus: storageBonus!,
      buildCost: buildCost!,
      upgrades: upgrades!,
    );
    _checkKind(f, def);
    return _errors.length > before ? null : def;
  }

  /// Checks the fields that only make sense for some building kinds.
  void _checkKind(_Fields f, BuildingDef b) {
    void unused(String key, bool present) {
      if (present) f.err(key, 'not used by ${b.kind.name} buildings');
    }

    // Habitats may run without crew; warehouses never have any.
    if ((b.kind == BuildingKind.extractor || b.kind == BuildingKind.factory) &&
        b.crewSlots < 1) {
      f.err('crewSlots', 'must be >= 1 for ${b.kind.name} buildings');
    }
    switch (b.kind) {
      case BuildingKind.extractor:
        if (b.extracts.isEmpty) f.err('extracts', 'must list at least one');
        unused('inputs', b.inputs.isNotEmpty);
        for (final r in b.outputs.keys) {
          if (!b.extracts.contains(r)) {
            f.err('outputs', "'$r' is not in extracts");
          }
        }
        for (final r in b.extracts) {
          if (!b.outputs.containsKey(r)) {
            f.err('outputs', "missing rate for '$r'");
          }
        }
        unused('housing', b.housing > 0);
        unused('storageBonus', b.storageBonus > 0);
      case BuildingKind.factory:
        if (b.outputs.isEmpty) f.err('outputs', 'must list at least one');
        unused('extracts', b.extracts.isNotEmpty);
        unused('housing', b.housing > 0);
        unused('storageBonus', b.storageBonus > 0);
      case BuildingKind.habitat:
        if (b.housing < 1) f.err('housing', 'must be >= 1 for habitats');
        unused('extracts', b.extracts.isNotEmpty);
        unused('storageBonus', b.storageBonus > 0);
      case BuildingKind.warehouse:
        if (!(b.storageBonus > 0)) {
          f.err('storageBonus', 'must be > 0 for warehouses');
        }
        unused('inputs', b.inputs.isNotEmpty);
        unused('outputs', b.outputs.isNotEmpty);
        unused('extracts', b.extracts.isNotEmpty);
        unused('housing', b.housing > 0);
    }
  }

  Map<UpgradeTrack, UpgradeCostDef>? _upgrades(_Fields f) {
    final raw = f.object('upgrades', optional: true);
    if (raw == null) return null;
    final tracks = UpgradeTrack.values.asNameMap();
    final out = <UpgradeTrack, UpgradeCostDef>{};
    for (final MapEntry(:key, :value) in raw.entries) {
      final path = '${f.path}.upgrades.$key';
      final track = tracks[key];
      if (track == null) {
        err(path, 'unknown upgrade track');
        continue;
      }
      final u = _objectAt(path, value, const {'baseCredits', 'growth'});
      if (u == null) continue;
      final baseCredits = u.bigNum('baseCredits', positive: true);
      final growth = u.number('growth', ge: 1);
      if (baseCredits != null && growth != null) {
        out[track] = UpgradeCostDef(baseCredits: baseCredits, growth: growth);
      }
    }
    final speed = out[UpgradeTrack.speed];
    final capacity = out[UpgradeTrack.capacity];
    if (speed != null && capacity != null && capacity.growth != speed.growth) {
      err(
        '${f.path}.upgrades.capacity.growth',
        'must equal the speed growth (${speed.growth}): speed and capacity '
            'share one level counter',
      );
    }
    return out;
  }

  BodyTypeDef? _bodyType(_Fields f, String id) {
    final before = _errors.length;
    final name = f.string('name');
    final depositPool = f.stringList('depositPool');
    final buildSlots = f.integer('buildSlots', min: 1);
    if (depositPool != null && depositPool.isEmpty) {
      f.err('depositPool', 'must list at least one');
    }
    if (_errors.length > before) return null;
    return BodyTypeDef(
      id: id,
      name: name!,
      depositPool: depositPool!,
      buildSlots: buildSlots!,
    );
  }

  GalaxyDef? _galaxy(Object? raw) {
    final g = _objectAt('galaxy', raw, const {'systems', 'factions'});
    if (g == null) return null;
    final before = _errors.length;
    final systems = _entries(
      'galaxy.systems',
      g.list('systems'),
      _systemIds,
      const {'id', 'name', 'bodies'},
      _system,
    );
    final factions =
        _entries('galaxy.factions', g.list('factions'), _factionIds, const {
          'id',
          'name',
          'isPlayer',
          'homeBodyId',
          'credits',
          'baseCrew',
          'buildings',
          'stock',
        }, _faction);
    if (_errors.length > before) return null;
    return GalaxyDef(
      systems: systems.values.toList(),
      factions: factions.values.toList(),
    );
  }

  SystemDef? _system(_Fields f, String id) {
    final before = _errors.length;
    final name = f.string('name');
    final bodies = _entries(
      '${f.path}.bodies',
      f.list('bodies'),
      _bodyIds,
      const {'id', 'name', 'typeId', 'orbit', 'deposits', 'hidden'},
      _body,
    );
    if (_errors.length > before) return null;
    return SystemDef(id: id, name: name!, bodies: bodies.values.toList());
  }

  BodyDef? _body(_Fields f, String id) {
    final before = _errors.length;
    final name = f.string('name');
    final typeId = f.string('typeId');
    final orbit = f.integer('orbit', min: 0);
    final hidden = f.boolean('hidden', fallback: false);
    final rawDeposits = f.list('deposits');
    final deposits = <DepositDef>[];
    if (rawDeposits != null) {
      if (rawDeposits.isEmpty || rawDeposits.length > 4) {
        f.err('deposits', 'expected 1 to 4 deposits');
      }
      for (var i = 0; i < rawDeposits.length; i++) {
        final d = _objectAt('${f.path}.deposits[$i]', rawDeposits[i], const {
          'resourceId',
          'richness',
        });
        if (d == null) continue;
        final resourceId = d.string('resourceId');
        final richness = d.number('richness', gt: 0);
        if (resourceId == null || richness == null) continue;
        if (deposits.any((e) => e.resourceId == resourceId)) {
          f.err('deposits', "duplicate deposit '$resourceId'");
        }
        deposits.add(DepositDef(resourceId: resourceId, richness: richness));
      }
    }
    if (_errors.length > before) return null;
    return BodyDef(
      id: id,
      name: name!,
      typeId: typeId!,
      orbit: orbit!,
      deposits: deposits,
      hidden: hidden!,
    );
  }

  StartingFactionDef? _faction(_Fields f, String id) {
    final before = _errors.length;
    final name = f.string('name');
    final isPlayer = f.boolean('isPlayer');
    final homeBodyId = f.string('homeBodyId');
    final credits = f.bigNum('credits');
    final baseCrew = f.integer('baseCrew', min: 0);
    final rawBuildings = f.list('buildings');
    final stock = f.amounts('stock', optional: true);
    final buildings = <StartingBuildingDef>[];
    for (final (i, raw) in (rawBuildings ?? const []).indexed) {
      final at = '${f.path}.buildings[$i]';
      final b = _objectAt(at, raw, const {
        'defId',
        'depositResourceId',
        'crew',
      });
      if (b == null) continue;
      final defId = b.string('defId');
      final depositResourceId = b.string('depositResourceId', optional: true);
      final crew = b.integer('crew', min: 0);
      if (defId == null || crew == null) continue;
      buildings.add(
        StartingBuildingDef(
          defId: defId,
          depositResourceId: depositResourceId,
          crew: crew,
        ),
      );
    }
    if (_errors.length > before) return null;
    return StartingFactionDef(
      id: id,
      name: name!,
      isPlayer: isPlayer!,
      homeBodyId: homeBodyId!,
      credits: credits!,
      baseCrew: baseCrew!,
      buildings: buildings,
      stock: stock!,
    );
  }

  MilestoneDef? _milestone(_Fields f, String id) {
    final before = _errors.length;
    final name = f.string('name');
    final raw = f.object('condition');
    final path = '${f.path}.condition';
    MilestoneCondition? condition;
    if (raw != null) {
      final type = raw['type'];
      switch (type) {
        case 'stock':
          final c = _Fields(this, path, raw, const {
            'type',
            'resource',
            'amount',
          });
          final resource = c.string('resource');
          final amount = c.bigNum('amount', positive: true);
          if (resource != null && amount != null) {
            condition = StockCondition(resourceId: resource, amount: amount);
          }
        case 'produced':
          final c = _Fields(this, path, raw, const {
            'type',
            'resource',
            'amount',
          });
          final resource = c.string('resource');
          final amount = c.bigNum('amount', positive: true);
          if (resource != null && amount != null) {
            condition = ProducedCondition(resourceId: resource, amount: amount);
          }
        case 'credits':
          final c = _Fields(this, path, raw, const {'type', 'amount'});
          final amount = c.bigNum('amount', positive: true);
          if (amount != null) condition = CreditsCondition(amount: amount);
        case 'creditsEarned':
          final c = _Fields(this, path, raw, const {'type', 'amount'});
          final amount = c.bigNum('amount', positive: true);
          if (amount != null) {
            condition = CreditsEarnedCondition(amount: amount);
          }
        case 'bodiesOwned':
          final c = _Fields(this, path, raw, const {'type', 'count'});
          final count = c.integer('count', min: 1);
          if (count != null) condition = BodiesOwnedCondition(count: count);
        case 'buildingCount':
          final c = _Fields(this, path, raw, const {'type', 'defId', 'count'});
          final defId = c.string('defId');
          final count = c.integer('count', min: 1);
          if (defId != null && count != null) {
            condition = BuildingCountCondition(defId: defId, count: count);
          }
        case 'contractsCompleted':
          final c = _Fields(this, path, raw, const {'type', 'count'});
          final count = c.integer('count', min: 1);
          if (count != null) {
            condition = ContractsCompletedCondition(count: count);
          }
        case 'productionRate':
          final c = _Fields(this, path, raw, const {
            'type',
            'resource',
            'perSec',
          });
          final resource = c.string('resource');
          final perSec = c.bigNum('perSec', positive: true);
          if (resource != null && perSec != null) {
            condition = ProductionRateCondition(
              resourceId: resource,
              perSec: perSec,
            );
          }
        case 'buildingTypesBuilt':
          final c = _Fields(this, path, raw, const {'type', 'count'});
          final count = c.integer('count', min: 1);
          if (count != null) {
            condition = BuildingTypesBuiltCondition(count: count);
          }
        case 'crewTotal':
          final c = _Fields(this, path, raw, const {'type', 'count'});
          final count = c.integer('count', min: 1);
          if (count != null) condition = CrewTotalCondition(count: count);
        case 'megaprojectLevel':
          final c = _Fields(this, path, raw, const {
            'type',
            'megaproject',
            'level',
          });
          final id = c.string('megaproject');
          final level = c.integer('level', min: 1);
          if (id != null && level != null) {
            condition = MegaprojectLevelCondition(
              megaprojectId: id,
              level: level,
            );
          }
        case 'zeroWasteFor':
          final c = _Fields(this, path, raw, const {'type', 'seconds'});
          final seconds = c.number('seconds', gt: 0);
          if (seconds != null) {
            condition = ZeroWasteForCondition(seconds: seconds);
          }
        case 'bodiesSurveyed':
          final c = _Fields(this, path, raw, const {'type', 'count'});
          final count = c.integer('count', min: 1);
          if (count != null) condition = BodiesSurveyedCondition(count: count);
        case null:
          err('$path.type', 'missing');
        default:
          err('$path.type', "unknown condition type '$type'");
      }
    }
    if (_errors.length > before) return null;
    return MilestoneDef(id: id, name: name!, condition: condition!);
  }

  MegaprojectDef? _megaproject(_Fields f, String id) {
    final before = _errors.length;
    final name = f.string('name');
    final hostBodyType = f.string('hostBodyType', optional: true);
    final baseCost = f.amounts('baseCost', positive: true);
    if (f.map['baseCost'] case final Map<String, Object?> raw
        when raw.isEmpty) {
      f.err('baseCost', 'must list at least one');
    }
    final costGrowth = f.number('costGrowth', ge: 1);
    final stageSeconds = f.number(
      'stageSeconds',
      ge: RulesDef.minProjectSeconds,
      le: RulesDef.maxProjectSeconds,
    );
    final stageSecondsGrowth = f.number('stageSecondsGrowth', ge: 1);
    final rawBonuses = f.list('bonusesPerLevel');
    final bonuses = <BonusDef>[];
    if (rawBonuses != null && rawBonuses.isEmpty) {
      f.err('bonusesPerLevel', 'must list at least one');
    }
    for (final (i, raw) in (rawBonuses ?? const []).indexed) {
      final b = _objectAt('${f.path}.bonusesPerLevel[$i]', raw, const {
        'kind',
        'amount',
      });
      if (b == null) continue;
      final kind = b.choice('kind', BonusKind.values, 'bonus kind');
      final amount = b.number('amount', gt: 0);
      if (kind != null && amount != null) {
        bonuses.add(BonusDef(kind: kind, amount: amount));
      }
    }
    if (_errors.length > before) return null;
    return MegaprojectDef(
      id: id,
      name: name!,
      hostBodyType: hostBodyType,
      baseCost: baseCost!,
      costGrowth: costGrowth!,
      stageSeconds: stageSeconds!,
      stageSecondsGrowth: stageSecondsGrowth!,
      bonusesPerLevel: bonuses,
    );
  }

  ContractTemplateDef? _contractTemplate(_Fields f, String id) {
    final before = _errors.length;
    final issuer = f.string('issuer');
    const top = ResourceDef.megaprojectTier;
    final minTier = f.integer('minTier', min: 0, max: top);
    final maxTier = f.integer('maxTier', min: 0, max: top);
    if (minTier != null && maxTier != null && maxTier < minTier) {
      f.err('maxTier', 'must be >= minTier ($minTier)');
    }
    final quantitySeconds = f.number(
      'quantitySeconds',
      fallback: ContractTemplateDef.defaultQuantitySeconds,
      gt: 0,
    );
    final rewardMultiplier = f.number(
      'rewardMultiplier',
      fallback: ContractTemplateDef.defaultRewardMultiplier,
      gt: 0,
    );
    final minQuantity = f.map.containsKey('minQuantity')
        ? f.bigNum('minQuantity', positive: true)
        : null;
    final maxQuantity = f.map.containsKey('maxQuantity')
        ? f.bigNum('maxQuantity', positive: true)
        : null;
    final least =
        minQuantity ?? BigNum.from(ContractTemplateDef.defaultMinQuantity);
    if (maxQuantity != null && maxQuantity < least) {
      f.err('maxQuantity', 'must be >= minQuantity (${formatNumber(least)})');
    }
    final rewardIncomeSeconds = f.number(
      'rewardIncomeSeconds',
      fallback: 0,
      ge: 0,
    );
    final rewardCapIncomeSeconds = f.map.containsKey('rewardCapIncomeSeconds')
        ? f.number('rewardCapIncomeSeconds', gt: 0)
        : null;
    if (rewardCapIncomeSeconds != null &&
        rewardIncomeSeconds != null &&
        rewardCapIncomeSeconds < rewardIncomeSeconds) {
      f.err(
        'rewardCapIncomeSeconds',
        'must be >= rewardIncomeSeconds (${_fmt(rewardIncomeSeconds)})',
      );
    }
    if (_errors.length > before) return null;
    return ContractTemplateDef(
      id: id,
      issuer: issuer!,
      minTier: minTier!,
      maxTier: maxTier!,
      quantitySeconds: quantitySeconds!,
      rewardMultiplier: rewardMultiplier!,
      minQuantity: minQuantity,
      maxQuantity: maxQuantity,
      rewardIncomeSeconds: rewardIncomeSeconds!,
      rewardCapIncomeSeconds: rewardCapIncomeSeconds,
    );
  }

  // ----------------------------------------------------------- references

  void _needResource(String path, String id) {
    if (!_resourceIds.contains(id)) err(path, "unknown resource '$id'");
  }

  /// Whether any body of [g] is hidden, so that surveys have a use.
  static bool _hasHidden(GalaxyDef? g) =>
      g != null && g.systems.any((s) => s.bodies.any((b) => b.hidden));

  void _checkRules(RulesDef r, GalaxyDef? galaxy) {
    _needResource('rules.outpostKitResource', r.outpostKitResource);
    _needResource('rules.cargoShipResource', r.cargoShipResource);
    if (_hasHidden(galaxy)) {
      _needResource('rules.surveyDroneResource', r.surveyDroneResource);
    }
  }

  void _checkBuildings(Map<String, BuildingDef> buildings) {
    for (final b in buildings.values) {
      final path = 'buildings.${b.id}';
      for (final r in b.inputs.keys) {
        _needResource('$path.inputs', r);
      }
      for (final r in b.outputs.keys) {
        _needResource('$path.outputs', r);
      }
      for (final r in b.extracts) {
        _needResource('$path.extracts', r);
      }
      for (final r in b.buildCost.keys) {
        if (r != _credits) _needResource('$path.buildCost', r);
      }
    }
  }

  void _checkBodyTypes(Map<String, BodyTypeDef> bodyTypes) {
    for (final t in bodyTypes.values) {
      for (final r in t.depositPool) {
        _needResource('body_types.${t.id}.depositPool', r);
      }
    }
  }

  void _checkGalaxy(
    GalaxyDef galaxy,
    Map<String, BuildingDef> buildings,
    Map<String, BodyTypeDef> bodyTypes,
  ) {
    final bodies = <String, BodyDef>{};
    for (final s in galaxy.systems) {
      for (final b in s.bodies) {
        bodies[b.id] = b;
        final path = 'galaxy.systems.${s.id}.bodies.${b.id}';
        if (!_bodyTypeIds.contains(b.typeId)) {
          err('$path.typeId', "unknown body type '${b.typeId}'");
        }
        final type = bodyTypes[b.typeId];
        for (final d in b.deposits) {
          _needResource('$path.deposits', d.resourceId);
          if (type != null && !type.depositPool.contains(d.resourceId)) {
            err(
              '$path.deposits',
              "'${d.resourceId}' is not in the '${type.id}' deposit pool",
            );
          }
        }
      }
    }

    final players = galaxy.factions.where((f) => f.isPlayer).length;
    if (players != 1) {
      err(
        'galaxy.factions',
        'expected exactly one player faction, found $players',
      );
    }
    final homes = <String>{};
    for (final f in galaxy.factions) {
      final path = 'galaxy.factions.${f.id}';
      if (!_bodyIds.contains(f.homeBodyId)) {
        err('$path.homeBodyId', "unknown body '${f.homeBodyId}'");
      } else if (!homes.add(f.homeBodyId)) {
        err(
          '$path.homeBodyId',
          "'${f.homeBodyId}' is already a faction's home",
        );
      }
      final home = bodies[f.homeBodyId];
      if (home != null && home.hidden) {
        err(
          '$path.homeBodyId',
          "'${home.id}' is hidden, so it can't be a home",
        );
      }
      var crew = 0;
      for (final (i, sb) in f.buildings.indexed) {
        final at = '$path.buildings[$i]';
        crew += sb.crew;
        if (!_buildingIds.contains(sb.defId)) {
          err('$at.defId', "unknown building '${sb.defId}'");
        }
        final def = buildings[sb.defId];
        if (def == null) continue;
        final deposit = sb.depositResourceId;
        if (def.kind != BuildingKind.extractor) {
          if (deposit != null) {
            err(
              '$at.depositResourceId',
              'not used by ${def.kind.name} buildings',
            );
          }
        } else if (deposit == null) {
          err('$at.depositResourceId', 'missing');
        } else if (!def.extracts.contains(deposit)) {
          err('$at.depositResourceId', "'${def.id}' cannot extract '$deposit'");
        } else if (home != null &&
            !home.deposits.any((d) => d.resourceId == deposit)) {
          err('$at.depositResourceId', "no '$deposit' deposit on '${home.id}'");
        }
        if (sb.crew > def.crewSlots) {
          err('$at.crew', 'exceeds ${def.crewSlots} crew slots');
        }
      }
      if (crew > f.baseCrew) {
        err(
          '$path.buildings',
          'assign $crew crew but baseCrew is ${f.baseCrew}',
        );
      }
      final slots = home == null ? null : bodyTypes[home.typeId]?.buildSlots;
      if (slots != null && f.buildings.length > slots) {
        err(
          '$path.buildings',
          '${f.buildings.length} buildings exceed the $slots build slots '
              "of '${home!.id}'",
        );
      }
      for (final r in f.stock.keys) {
        _needResource('$path.stock', r);
      }
    }
  }

  void _checkMilestones(
    Map<String, MilestoneDef> milestones,
    Map<String, BuildingDef> buildings,
    GalaxyDef? galaxy,
  ) {
    final hidden = galaxy == null
        ? 0
        : galaxy.systems.expand((s) => s.bodies).where((b) => b.hidden).length;
    for (final m in milestones.values) {
      final path = 'milestones.${m.id}.condition';
      switch (m.condition) {
        case StockCondition(:final resourceId) ||
            ProducedCondition(:final resourceId) ||
            ProductionRateCondition(:final resourceId):
          _needResource('$path.resource', resourceId);
        case BuildingTypesBuiltCondition(:final count):
          if (count > buildings.length) {
            err('$path.count', 'above the ${buildings.length} building types');
          }
        case MegaprojectLevelCondition(:final megaprojectId):
          if (!_megaprojectIds.contains(megaprojectId)) {
            err('$path.megaproject', "unknown megaproject '$megaprojectId'");
          }
        case BodiesSurveyedCondition(:final count):
          if (count > hidden) {
            err('$path.count', 'above the $hidden hidden bodies');
          }
        case BuildingCountCondition(:final defId):
          if (!_buildingIds.contains(defId)) {
            err('$path.defId', "unknown building '$defId'");
          }
        case CreditsCondition() ||
            CreditsEarnedCondition() ||
            BodiesOwnedCondition() ||
            ContractsCompletedCondition() ||
            CrewTotalCondition() ||
            ZeroWasteForCondition():
          break;
      }
    }
  }

  void _checkMegaprojects(Map<String, MegaprojectDef> megaprojects) {
    for (final m in megaprojects.values) {
      final path = 'megaprojects.${m.id}';
      final host = m.hostBodyType;
      if (host != null && !_bodyTypeIds.contains(host)) {
        err('$path.hostBodyType', "unknown body type '$host'");
      }
      for (final r in m.baseCost.keys) {
        if (r != _credits) _needResource('$path.baseCost', r);
      }
    }
  }

  // ---------------------------------------------------------------- graph

  void _checkGraph(
    RulesDef rules,
    Map<String, ResourceDef> resources,
    Map<String, BuildingDef> buildings,
    GalaxyDef galaxy,
    Map<String, MegaprojectDef> megaprojects,
  ) {
    final deposits = {
      for (final s in galaxy.systems)
        for (final b in s.bodies)
          for (final d in b.deposits) d.resourceId,
    };
    final extractors = [
      for (final b in buildings.values)
        if (b.kind == BuildingKind.extractor) b,
    ];
    final recipes = [
      for (final b in buildings.values)
        if (b.kind != BuildingKind.extractor && b.outputs.isNotEmpty) b,
    ];

    // Reachable: mined from some deposit, or made by a recipe whose inputs
    // are all reachable. Grows until stable.
    final reachable = {
      for (final e in extractors)
        for (final r in e.extracts)
          if (deposits.contains(r)) r,
    };
    var grew = true;
    while (grew) {
      grew = false;
      for (final b in recipes) {
        if (b.inputs.keys.every(reachable.contains)) {
          for (final r in b.outputs.keys) {
            if (reachable.add(r)) grew = true;
          }
        }
      }
    }
    final made = {...reachable, for (final b in recipes) ...b.outputs.keys};

    final consumed = {
      for (final b in buildings.values) ...b.inputs.keys,
      for (final b in buildings.values) ...b.buildCost.keys,
      for (final m in megaprojects.values) ...m.baseCost.keys,
      rules.outpostKitResource,
      rules.cargoShipResource,
      if (_hasHidden(galaxy) && rules.surveyDrones > 0)
        rules.surveyDroneResource,
    };

    for (final r in resources.values) {
      final path = 'resources.${r.id}';
      if (!made.contains(r.id)) {
        err(path, 'nothing produces it');
      } else if (!reachable.contains(r.id)) {
        err(path, 'its producers need inputs that are never made');
      }
      if (r.tier < ResourceDef.megaprojectTier &&
          !consumed.contains(r.id) &&
          r.basePrice.isZero) {
        err(path, 'never consumed and cannot be sold');
      }
    }
  }
}

/// Typed, error-collecting reads from one JSON object at [path].
final class _Fields {
  _Fields(this._l, this.path, this.map, Set<String> allowed) {
    for (final key in map.keys) {
      if (!allowed.contains(key)) err(key, 'unknown field');
    }
  }

  final _Loader _l;
  final String path;
  final Map<String, Object?> map;

  void err(String key, String message) => _l.err('$path.$key', message);

  /// Returns the value at [key], recording `missing` when it is required.
  Object? _get(String key, {required bool optional}) {
    final v = map[key];
    if (v == null && !optional) err(key, 'missing');
    return v;
  }

  String? string(String key, {bool optional = false}) {
    final v = _get(key, optional: optional);
    if (v == null || (v is String && v.isNotEmpty)) return v as String?;
    err(key, 'expected a non-empty string');
    return null;
  }

  bool? boolean(String key, {bool? fallback}) {
    final v = _get(key, optional: fallback != null);
    if (v == null) return fallback;
    if (v is bool) return v;
    err(key, 'expected true or false');
    return null;
  }

  T? choice<T extends Enum>(String key, List<T> values, String what) {
    final s = string(key);
    if (s == null) return null;
    final v = values.asNameMap()[s];
    if (v == null) err(key, "unknown $what '$s'");
    return v;
  }

  double? number(
    String key, {
    double? fallback,
    double? gt,
    double? ge,
    double? le,
  }) {
    final v = _get(key, optional: fallback != null);
    if (v == null) return fallback;
    return _l.number('$path.$key', v, gt: gt, ge: ge, le: le);
  }

  int? integer(String key, {int? fallback, int? min, int? max}) {
    final v = _get(key, optional: fallback != null);
    if (v == null) return fallback;
    if (v is! int) {
      err(key, 'expected an integer');
    } else if (min != null && v < min) {
      err(key, 'must be >= $min');
    } else if (max != null && v > max) {
      err(key, 'must be <= $max');
    } else {
      return v;
    }
    return null;
  }

  BigNum? bigNum(String key, {bool positive = false, bool optional = false}) {
    final v = _get(key, optional: optional);
    if (v == null) return null;
    return _l.bigNum('$path.$key', v, positive: positive);
  }

  /// An object value; an absent optional one reads as empty.
  Map<String, Object?>? object(String key, {bool optional = false}) {
    final v = _get(key, optional: optional);
    if (v == null) return optional ? const {} : null;
    if (v is Map<String, Object?>) return v;
    err(key, 'expected an object');
    return null;
  }

  List<Object?>? list(String key) {
    final v = _get(key, optional: false);
    if (v == null) return null;
    if (v is List<Object?>) return v;
    err(key, 'expected a list');
    return null;
  }

  /// A list of distinct non-empty strings; an absent optional one is empty.
  List<String>? stringList(String key, {bool optional = false}) {
    final v = _get(key, optional: optional);
    if (v == null) return optional ? const [] : null;
    if (v is! List<Object?>) {
      err(key, 'expected a list');
      return null;
    }
    final out = <String>[];
    for (final (i, s) in v.indexed) {
      if (s is! String || s.isEmpty) {
        _l.err('$path.$key[$i]', 'expected a non-empty string');
      } else if (out.contains(s)) {
        err(key, "duplicate '$s'");
      } else {
        out.add(s);
      }
    }
    return out;
  }

  /// Resource id to a positive per-cycle rate; absent reads as empty.
  Map<String, double>? rates(String key) {
    final m = object(key, optional: true);
    if (m == null) return null;
    final out = <String, double>{};
    for (final MapEntry(key: id, :value) in m.entries) {
      final d = _l.number('$path.$key.$id', value, gt: 0);
      if (d != null) out[id] = d;
    }
    return out;
  }

  /// Key to a [BigNum] amount; an absent optional one reads as empty.
  Map<String, BigNum>? amounts(
    String key, {
    bool optional = false,
    bool positive = false,
  }) {
    final m = object(key, optional: optional);
    if (m == null) return null;
    final out = <String, BigNum>{};
    for (final MapEntry(key: id, :value) in m.entries) {
      final b = _l.bigNum('$path.$key.$id', value, positive: positive);
      if (b != null) out[id] = b;
    }
    return out;
  }
}
