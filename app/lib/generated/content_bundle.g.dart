// GENERATED — do not edit. Source: content/*.json.
// Regenerate with `dart run tool/embed_content.dart`.

/// Every `content/*.json` file, by file stem, as its raw JSON text.
const Map<String, String> contentJson = {
  'body_types': r'''[
  {"id": "rocky", "name": "Rocky World", "depositPool": ["iron_ore", "copper_ore", "silicon"], "buildSlots": 12},
  {"id": "asteroid_belt", "name": "Asteroid Belt", "depositPool": ["nickel", "iron_ore", "water_ice"], "buildSlots": 8},
  {"id": "ice_moon", "name": "Ice Moon", "depositPool": ["water_ice", "ammonia"], "buildSlots": 10},
  {"id": "gas_giant", "name": "Gas Giant", "depositPool": ["hydrogen", "helium_3"], "buildSlots": 6},
  {"id": "volcanic", "name": "Volcanic World", "depositPool": ["sulfur", "rare_earths"], "buildSlots": 6},
  {"id": "kuiper", "name": "Kuiper Rock", "depositPool": ["nickel", "rare_earths", "helium_3"], "buildSlots": 8}
]
''',
  'buildings': r'''[
  {
    "id": "mine", "name": "Mine", "kind": "extractor", "cycleSeconds": 5,
    "extracts": ["iron_ore", "copper_ore", "silicon", "nickel", "sulfur", "rare_earths"],
    "outputs": {"iron_ore": 2, "copper_ore": 2, "silicon": 2, "nickel": 1.5, "sulfur": 2, "rare_earths": 1},
    "crewSlots": 1,
    "buildCost": {"credits": "100"},
    "upgrades": {
      "speed": {"baseCredits": "50", "growth": 1.17},
      "capacity": {"baseCredits": "300", "growth": 1.17}
    }
  },
  {
    "id": "ice_drill", "name": "Ice Drill", "kind": "extractor", "cycleSeconds": 5,
    "extracts": ["water_ice", "ammonia"],
    "outputs": {"water_ice": 3, "ammonia": 2},
    "crewSlots": 1,
    "buildCost": {"credits": "250"},
    "upgrades": {
      "speed": {"baseCredits": "120", "growth": 1.17},
      "capacity": {"baseCredits": "720", "growth": 1.17}
    }
  },
  {
    "id": "gas_skimmer", "name": "Gas Skimmer", "kind": "extractor", "cycleSeconds": 6,
    "extracts": ["hydrogen", "helium_3"],
    "outputs": {"hydrogen": 4, "helium_3": 1},
    "crewSlots": 1,
    "buildCost": {"credits": "600"},
    "upgrades": {
      "speed": {"baseCredits": "300", "growth": 1.17},
      "capacity": {"baseCredits": "1800", "growth": 1.17}
    }
  },
  {
    "id": "smelter", "name": "Smelter", "kind": "factory", "cycleSeconds": 5,
    "inputs": {"iron_ore": 2},
    "outputs": {"steel": 1},
    "crewSlots": 1,
    "buildCost": {"credits": "150"},
    "upgrades": {
      "speed": {"baseCredits": "75", "growth": 1.17},
      "efficiency": {"baseCredits": "100", "growth": 1.2},
      "capacity": {"baseCredits": "450", "growth": 1.17}
    }
  },
  {
    "id": "hydrogen_furnace", "name": "Hydrogen Furnace", "kind": "factory", "cycleSeconds": 8,
    "inputs": {"iron_ore": 2, "hydrogen": 2},
    "outputs": {"steel": 2, "water": 1},
    "crewSlots": 1,
    "buildCost": {"credits": "800"},
    "upgrades": {
      "speed": {"baseCredits": "400", "growth": 1.17},
      "efficiency": {"baseCredits": "528", "growth": 1.2},
      "capacity": {"baseCredits": "2400", "growth": 1.17}
    }
  },
  {
    "id": "wire_mill", "name": "Wire Mill", "kind": "factory", "cycleSeconds": 4,
    "inputs": {"copper_ore": 1},
    "outputs": {"copper_wire": 2},
    "crewSlots": 1,
    "buildCost": {"credits": "150"},
    "upgrades": {
      "speed": {"baseCredits": "75", "growth": 1.17},
      "efficiency": {"baseCredits": "100", "growth": 1.2},
      "capacity": {"baseCredits": "450", "growth": 1.17}
    }
  },
  {
    "id": "wafer_fab", "name": "Wafer Fab", "kind": "factory", "cycleSeconds": 6,
    "inputs": {"silicon": 2},
    "outputs": {"silicon_wafer": 1},
    "crewSlots": 1,
    "buildCost": {"credits": "250"},
    "upgrades": {
      "speed": {"baseCredits": "120", "growth": 1.17},
      "efficiency": {"baseCredits": "160", "growth": 1.2},
      "capacity": {"baseCredits": "720", "growth": 1.17}
    }
  },
  {
    "id": "circuit_fab", "name": "Circuit Fab", "kind": "factory", "cycleSeconds": 10,
    "inputs": {"copper_wire": 2, "silicon_wafer": 1},
    "outputs": {"circuit": 1},
    "crewSlots": 2,
    "buildCost": {"credits": "600"},
    "upgrades": {
      "speed": {"baseCredits": "300", "growth": 1.17},
      "efficiency": {"baseCredits": "400", "growth": 1.2},
      "capacity": {"baseCredits": "1800", "growth": 1.17}
    }
  },
  {
    "id": "plate_press", "name": "Plate Press", "kind": "factory", "cycleSeconds": 8,
    "inputs": {"steel": 3},
    "outputs": {"hull_plate": 1},
    "crewSlots": 1,
    "buildCost": {"credits": "500"},
    "upgrades": {
      "speed": {"baseCredits": "250", "growth": 1.17},
      "efficiency": {"baseCredits": "330", "growth": 1.2},
      "capacity": {"baseCredits": "1500", "growth": 1.17}
    }
  },
  {
    "id": "ice_melter", "name": "Ice Melter", "kind": "factory", "cycleSeconds": 2,
    "inputs": {"water_ice": 1},
    "outputs": {"water": 1},
    "crewSlots": 1,
    "buildCost": {"credits": "200"},
    "upgrades": {
      "speed": {"baseCredits": "100", "growth": 1.17},
      "efficiency": {"baseCredits": "130", "growth": 1.2},
      "capacity": {"baseCredits": "600", "growth": 1.17}
    }
  },
  {
    "id": "electrolyzer", "name": "Electrolyzer", "kind": "factory", "cycleSeconds": 6,
    "inputs": {"water": 2},
    "outputs": {"oxygen": 1, "hydrogen": 2},
    "crewSlots": 1,
    "buildCost": {"credits": "400"},
    "upgrades": {
      "speed": {"baseCredits": "200", "growth": 1.17},
      "efficiency": {"baseCredits": "260", "growth": 1.2},
      "capacity": {"baseCredits": "1200", "growth": 1.17}
    }
  },
  {
    "id": "fuel_refinery", "name": "Fuel Refinery", "kind": "factory", "cycleSeconds": 6,
    "inputs": {"hydrogen": 2, "oxygen": 1},
    "outputs": {"fuel": 2},
    "crewSlots": 1,
    "buildCost": {"credits": "500"},
    "upgrades": {
      "speed": {"baseCredits": "250", "growth": 1.17},
      "efficiency": {"baseCredits": "330", "growth": 1.2},
      "capacity": {"baseCredits": "1500", "growth": 1.17}
    }
  },
  {
    "id": "fusion_refinery", "name": "Fusion Refinery", "kind": "factory", "cycleSeconds": 10,
    "inputs": {"hydrogen": 1, "helium_3": 1},
    "outputs": {"fuel": 6},
    "crewSlots": 2,
    "buildCost": {"credits": "3000"},
    "upgrades": {
      "speed": {"baseCredits": "1500", "growth": 1.17},
      "efficiency": {"baseCredits": "2000", "growth": 1.2},
      "capacity": {"baseCredits": "9000", "growth": 1.17}
    }
  },
  {
    "id": "propellant_mixer", "name": "Propellant Mixer", "kind": "factory", "cycleSeconds": 8,
    "inputs": {"sulfur": 2},
    "outputs": {"fuel": 2},
    "crewSlots": 1,
    "buildCost": {"credits": "400"},
    "upgrades": {
      "speed": {"baseCredits": "200", "growth": 1.17},
      "efficiency": {"baseCredits": "260", "growth": 1.2},
      "capacity": {"baseCredits": "1200", "growth": 1.17}
    }
  },
  {
    "id": "fertilizer_plant", "name": "Fertilizer Plant", "kind": "factory", "cycleSeconds": 5,
    "inputs": {"ammonia": 2},
    "outputs": {"fertilizer": 1},
    "crewSlots": 1,
    "buildCost": {"credits": "300"},
    "upgrades": {
      "speed": {"baseCredits": "150", "growth": 1.17},
      "efficiency": {"baseCredits": "200", "growth": 1.2},
      "capacity": {"baseCredits": "900", "growth": 1.17}
    }
  },
  {
    "id": "farm", "name": "Hydroponic Farm", "kind": "factory", "cycleSeconds": 10,
    "inputs": {"water": 2, "fertilizer": 1},
    "outputs": {"food": 2},
    "crewSlots": 1,
    "buildCost": {"credits": "400"},
    "upgrades": {
      "speed": {"baseCredits": "200", "growth": 1.17},
      "efficiency": {"baseCredits": "260", "growth": 1.2},
      "capacity": {"baseCredits": "1200", "growth": 1.17}
    }
  },
  {
    "id": "protein_vat", "name": "Protein Vat", "kind": "factory", "cycleSeconds": 12,
    "inputs": {"water": 2, "hydrogen": 2},
    "outputs": {"food": 2},
    "crewSlots": 1,
    "buildCost": {"credits": "500"},
    "upgrades": {
      "speed": {"baseCredits": "250", "growth": 1.17},
      "efficiency": {"baseCredits": "330", "growth": 1.2},
      "capacity": {"baseCredits": "1500", "growth": 1.17}
    }
  },
  {
    "id": "magnet_works", "name": "Magnet Works", "kind": "factory", "cycleSeconds": 10,
    "inputs": {"rare_earths": 2, "nickel": 1},
    "outputs": {"magnet": 1},
    "crewSlots": 2,
    "buildCost": {"credits": "1500"},
    "upgrades": {
      "speed": {"baseCredits": "750", "growth": 1.17},
      "efficiency": {"baseCredits": "1000", "growth": 1.2},
      "capacity": {"baseCredits": "4500", "growth": 1.17}
    }
  },
  {
    "id": "reactor_works", "name": "Reactor Works", "kind": "factory", "cycleSeconds": 60,
    "inputs": {"magnet": 2, "helium_3": 3, "circuit": 1},
    "outputs": {"reactor_core": 1},
    "crewSlots": 2,
    "buildCost": {"credits": "4000"},
    "upgrades": {
      "speed": {"baseCredits": "2000", "growth": 1.17},
      "efficiency": {"baseCredits": "2640", "growth": 1.2},
      "capacity": {"baseCredits": "12000", "growth": 1.17}
    }
  },
  {
    "id": "module_works", "name": "Module Works", "kind": "factory", "cycleSeconds": 300,
    "inputs": {"hull_plate": 4, "circuit": 4},
    "outputs": {"habitat_module": 1},
    "crewSlots": 2,
    "buildCost": {"credits": "1500"},
    "upgrades": {
      "efficiency": {"baseCredits": "1000", "growth": 1.2}
    }
  },
  {
    "id": "shipyard", "name": "Shipyard", "kind": "factory", "cycleSeconds": 300,
    "inputs": {"steel": 10, "circuit": 4},
    "outputs": {"cargo_ship": 1},
    "crewSlots": 2,
    "buildCost": {"credits": "1000"},
    "upgrades": {
      "efficiency": {"baseCredits": "660", "growth": 1.2}
    }
  },
  {
    "id": "drone_works", "name": "Drone Works", "kind": "factory", "cycleSeconds": 120,
    "inputs": {"magnet": 4, "circuit": 4, "fuel": 6},
    "outputs": {"survey_drone": 1},
    "crewSlots": 2,
    "buildCost": {"credits": "8000"},
    "upgrades": {
      "speed": {"baseCredits": "4000", "growth": 1.17},
      "efficiency": {"baseCredits": "5280", "growth": 1.2},
      "capacity": {"baseCredits": "24000", "growth": 1.17}
    }
  },
  {
    "id": "kit_assembler", "name": "Outpost Kit Assembler", "kind": "factory", "cycleSeconds": 600,
    "inputs": {"hull_plate": 6, "fuel": 12, "circuit": 6},
    "outputs": {"outpost_kit": 1},
    "crewSlots": 2,
    "buildCost": {"credits": "2500"},
    "upgrades": {
      "efficiency": {"baseCredits": "1650", "growth": 1.2}
    }
  },
  {
    "id": "station_dock", "name": "Station Dock", "kind": "factory", "cycleSeconds": 120,
    "inputs": {"hull_plate": 8, "magnet": 2, "circuit": 4},
    "outputs": {"station_segment": 1},
    "crewSlots": 3,
    "buildCost": {"credits": "20000"},
    "upgrades": {
      "speed": {"baseCredits": "10000", "growth": 1.17},
      "efficiency": {"baseCredits": "13200", "growth": 1.2},
      "capacity": {"baseCredits": "60000", "growth": 1.17}
    }
  },
  {
    "id": "habitat", "name": "Habitat", "kind": "habitat", "cycleSeconds": 10,
    "inputs": {"food": 1, "water": 1, "oxygen": 1},
    "housing": 20,
    "crewSlots": 0,
    "buildCost": {"credits": "1500", "habitat_module": "1"},
    "upgrades": {
      "efficiency": {"baseCredits": "1000", "growth": 1.2},
      "capacity": {"baseCredits": "900", "growth": 1.2}
    }
  },
  {
    "id": "depot", "name": "Depot", "kind": "warehouse", "cycleSeconds": 1,
    "storageBonus": 2,
    "crewSlots": 0,
    "buildCost": {"credits": "800", "steel": "50"},
    "upgrades": {
      "capacity": {"baseCredits": "400", "growth": 1.17}
    }
  }
]
''',
  'contracts': r'''[
  {"id": "veyra_bulk", "issuer": "Veyra Exchange", "minTier": 0, "maxTier": 1, "quantitySeconds": 3600, "quantityIncomeSecondsMin": 600, "quantityIncomeSecondsMax": 1800, "quantityProductionSecondsMax": 86400, "rewardMultiplier": 3, "minRewardMultiplier": 1.5, "minQuantity": "100", "rewardIncomeSeconds": 1800, "rewardCapIncomeSeconds": 3600, "lifeSupportWeight": 0.25, "minRewardCredits": "500", "firstContractMinReward": "7500"},
  {"id": "veyra_parts", "issuer": "Veyra Exchange", "minTier": 2, "maxTier": 2, "quantitySeconds": 7200, "quantityIncomeSecondsMin": 600, "quantityIncomeSecondsMax": 1800, "quantityProductionSecondsMax": 86400, "rewardMultiplier": 3, "minRewardMultiplier": 1.5, "minQuantity": "20", "rewardIncomeSeconds": 1800, "rewardCapIncomeSeconds": 3600, "lifeSupportWeight": 0.25, "minRewardCredits": "500", "firstContractMinReward": "7500"},
  {"id": "veyra_advanced", "issuer": "Veyra Exchange", "minTier": 3, "maxTier": 3, "quantitySeconds": 10800, "quantityIncomeSecondsMin": 600, "quantityIncomeSecondsMax": 1800, "quantityProductionSecondsMax": 86400, "rewardMultiplier": 3, "minRewardMultiplier": 1.5, "minQuantity": "5", "rewardIncomeSeconds": 1800, "rewardCapIncomeSeconds": 3600, "lifeSupportWeight": 0.25, "minRewardCredits": "500", "firstContractMinReward": "7500"}
]
''',
  'galaxy': r'''{
  "systems": [
    {
      "id": "veyra",
      "name": "Veyra",
      "bodies": [
        {
          "id": "cinder", "name": "Cinder", "typeId": "volcanic", "orbit": 1,
          "deposits": [
            {"resourceId": "sulfur", "richness": 1.2},
            {"resourceId": "rare_earths", "richness": 0.6}
          ]
        },
        {
          "id": "kora", "name": "Kora", "typeId": "rocky", "orbit": 2,
          "deposits": [
            {"resourceId": "iron_ore", "richness": 1.0},
            {"resourceId": "copper_ore", "richness": 0.8},
            {"resourceId": "silicon", "richness": 0.7}
          ]
        },
        {
          "id": "hollow_reach", "name": "Hollow Reach", "typeId": "asteroid_belt", "orbit": 3,
          "deposits": [
            {"resourceId": "nickel", "richness": 1.2},
            {"resourceId": "iron_ore", "richness": 0.8},
            {"resourceId": "water_ice", "richness": 1.0}
          ]
        },
        {
          "id": "vastmere", "name": "Vastmere", "typeId": "gas_giant", "orbit": 5,
          "deposits": [
            {"resourceId": "hydrogen", "richness": 1.5},
            {"resourceId": "helium_3", "richness": 0.5}
          ]
        },
        {
          "id": "brine", "name": "Brine", "typeId": "ice_moon", "orbit": 5,
          "deposits": [
            {"resourceId": "water_ice", "richness": 1.5},
            {"resourceId": "ammonia", "richness": 1.0}
          ]
        },
        {
          "id": "tessaly", "name": "Tessaly", "typeId": "ice_moon", "orbit": 8, "hidden": true,
          "deposits": [
            {"resourceId": "water_ice", "richness": 2.2},
            {"resourceId": "ammonia", "richness": 1.8}
          ]
        },
        {
          "id": "dusk_cairn", "name": "Dusk Cairn", "typeId": "kuiper", "orbit": 9, "hidden": true,
          "deposits": [
            {"resourceId": "rare_earths", "richness": 1.8},
            {"resourceId": "nickel", "richness": 1.5},
            {"resourceId": "helium_3", "richness": 1.4}
          ]
        }
      ]
    }
  ],
  "factions": [
    {
      "id": "player",
      "name": "Kora Compact",
      "isPlayer": true,
      "homeBodyId": "kora",
      "credits": "250",
      "baseCrew": 20,
      "buildings": [
        {"defId": "mine", "depositResourceId": "iron_ore", "crew": 1},
        {"defId": "mine", "depositResourceId": "copper_ore", "crew": 1},
        {"defId": "smelter", "crew": 1}
      ],
      "stock": {"iron_ore": "40", "cargo_ship": "2"}
    }
  ]
}
''',
  'megaprojects': r'''[
  {
    "id": "orbital_station",
    "name": "Orbital Station",
    "baseCost": {
      "credits": "5e6",
      "station_segment": "200",
      "survey_drone": "40",
      "reactor_core": "30",
      "hull_plate": "1500"
    },
    "costGrowth": 2.5,
    "stageSeconds": 7200,
    "stageSecondsGrowth": 1.15,
    "bonusesPerLevel": [
      {"kind": "storagePercent", "amount": 10},
      {"kind": "housingPercent", "amount": 5},
      {"kind": "offlineCapSeconds", "amount": 3600},
      {"kind": "marketDepthMultiplier", "amount": 1.25}
    ]
  },
  {
    "id": "mass_driver",
    "name": "Mass Driver",
    "requiresMegaproject": {"orbital_station": 1},
    "scalesContracts": false,
    "baseCost": {
      "credits": "2e6",
      "hull_plate": "5000",
      "copper_wire": "20000",
      "water": "10000",
      "silicon_wafer": "2000"
    },
    "costGrowth": 2.3,
    "stageSeconds": 7200,
    "stageSecondsGrowth": 1.15,
    "bonusesPerLevel": [
      {"kind": "salePriceMultiplier", "amount": 1.25, "appliesToMinTier": 1, "appliesToMaxTier": 2}
    ]
  }
]
''',
  'milestones': r'''[
  {"id": "first_steel", "name": "First Foundry", "condition": {"type": "produced", "resource": "steel", "amount": "30"}},
  {"id": "credits_10k", "name": "Ten Thousand Credits", "condition": {"type": "creditsEarned", "amount": "1e4"}},
  {"id": "own_2_bodies", "name": "First Claim", "condition": {"type": "bodiesOwned", "count": 2}},
  {"id": "first_circuits", "name": "Circuit Board", "condition": {"type": "produced", "resource": "circuit", "amount": "100"}},
  {"id": "first_habitat_module", "name": "Room to Grow", "condition": {"type": "produced", "resource": "habitat_module", "amount": "1"}},
  {"id": "first_outpost_kit", "name": "Outpost Ready", "condition": {"type": "produced", "resource": "outpost_kit", "amount": "1"}},
  {"id": "credits_1m", "name": "Millionaire", "condition": {"type": "creditsEarned", "amount": "1e6"}},
  {"id": "own_3_bodies", "name": "Second Claim", "condition": {"type": "bodiesOwned", "count": 3}},
  {"id": "credits_3m", "name": "Three Million", "condition": {"type": "creditsEarned", "amount": "3e6"}},
  {"id": "first_magnets", "name": "Field Lines", "condition": {"type": "produced", "resource": "magnet", "amount": "10"}},
  {"id": "own_4_bodies", "name": "Spreading Out", "condition": {"type": "bodiesOwned", "count": 4}},
  {"id": "credits_10m", "name": "Ten Million", "condition": {"type": "creditsEarned", "amount": "1e7"}},
  {"id": "first_reactor_core", "name": "Fusion Heart", "condition": {"type": "produced", "resource": "reactor_core", "amount": "1"}},
  {"id": "first_survey_drone", "name": "Eyes Outward", "condition": {"type": "produced", "resource": "survey_drone", "amount": "1"}},
  {"id": "own_5_bodies", "name": "Whole System", "condition": {"type": "bodiesOwned", "count": 5}},
  {"id": "credits_30m", "name": "Thirty Million", "condition": {"type": "creditsEarned", "amount": "3e7"}},
  {"id": "credits_100m", "name": "Hundred Million", "condition": {"type": "creditsEarned", "amount": "1e8"}},
  {"id": "first_station_segment", "name": "Orbital Foundations", "condition": {"type": "produced", "resource": "station_segment", "amount": "1"}},
  {"id": "credits_300m", "name": "Three Hundred Million", "condition": {"type": "creditsEarned", "amount": "3e8"}},
  {"id": "credits_600m", "name": "Six Hundred Million", "condition": {"type": "creditsEarned", "amount": "6e8"}},
  {"id": "credits_1b", "name": "Billionaire", "condition": {"type": "creditsEarned", "amount": "1e9"}},
  {"id": "surveyed_1", "name": "Lifting the Veil", "condition": {"type": "bodiesSurveyed", "count": 1}},
  {"id": "surveyed_2", "name": "Nothing Hidden", "condition": {"type": "bodiesSurveyed", "count": 2}},
  {"id": "types_20", "name": "Every Tool Lit", "condition": {"type": "buildingTypesBuilt", "count": 20}},
  {"id": "crew_40", "name": "Crowded Corridors", "condition": {"type": "crewTotal", "count": 40}},
  {"id": "contracts_1", "name": "Handshake Deal", "condition": {"type": "contractsCompleted", "count": 1}},
  {"id": "contracts_5", "name": "Reliable Supplier", "condition": {"type": "contractsCompleted", "count": 5}},
  {"id": "station_1", "name": "Anchor Dropped", "condition": {"type": "megaprojectLevel", "megaproject": "orbital_station", "level": 1}},
  {"id": "station_2", "name": "Spine Complete", "condition": {"type": "megaprojectLevel", "megaproject": "orbital_station", "level": 2}},
  {"id": "station_3", "name": "Ring Takes Shape", "condition": {"type": "megaprojectLevel", "megaproject": "orbital_station", "level": 3}},
  {"id": "clean_2h", "name": "Clean Running", "condition": {"type": "zeroWasteFor", "seconds": 7200}},
  {"id": "clean_24h", "name": "Nothing Lost", "condition": {"type": "zeroWasteFor", "seconds": 86400}},
  {"id": "credits_10b", "name": "Ten Billion", "condition": {"type": "creditsEarned", "amount": "1e10"}},
  {"id": "credits_100b", "name": "Hundred Billion", "condition": {"type": "creditsEarned", "amount": "1e11"}},
  {"id": "credits_1t", "name": "Trillionaire", "condition": {"type": "creditsEarned", "amount": "1e12"}},
  {"id": "types_12", "name": "Twelve Trades", "condition": {"type": "buildingTypesBuilt", "count": 12}},
  {"id": "crew_90", "name": "City Lights", "condition": {"type": "crewTotal", "count": 90}},
  {"id": "contracts_10", "name": "Name on the Board", "condition": {"type": "contractsCompleted", "count": 10}},
  {"id": "contracts_14", "name": "Guild Favorite", "condition": {"type": "contractsCompleted", "count": 14}},
  {"id": "wire_flow", "name": "Copper River", "condition": {"type": "productionRate", "resource": "copper_wire", "perSec": "20"}},
  {"id": "plate_flow", "name": "Armor Line", "condition": {"type": "productionRate", "resource": "hull_plate", "perSec": "5"}},
  {"id": "wafer_flow", "name": "Glass Tide", "condition": {"type": "productionRate", "resource": "silicon_wafer", "perSec": "10"}},
  {"id": "food_flow", "name": "Full Tables", "condition": {"type": "productionRate", "resource": "food", "perSec": "20"}},
  {"id": "credits_3b", "name": "Three Billion", "condition": {"type": "creditsEarned", "amount": "3e9"}},
  {"id": "credits_30b", "name": "Thirty Billion", "condition": {"type": "creditsEarned", "amount": "3e10"}},
  {"id": "credits_300b", "name": "Three Hundred Billion", "condition": {"type": "creditsEarned", "amount": "3e11"}},
  {"id": "station_4", "name": "Busy Harbor", "condition": {"type": "megaprojectLevel", "megaproject": "orbital_station", "level": 4}},
  {"id": "station_6", "name": "Sky Bazaar", "condition": {"type": "megaprojectLevel", "megaproject": "orbital_station", "level": 6}},
  {"id": "station_8", "name": "Crown of Lights", "condition": {"type": "megaprojectLevel", "megaproject": "orbital_station", "level": 8}},
  {"id": "station_10", "name": "City Above", "condition": {"type": "megaprojectLevel", "megaproject": "orbital_station", "level": 10}},
  {"id": "driver_1", "name": "First Launch", "condition": {"type": "megaprojectLevel", "megaproject": "mass_driver", "level": 1}},
  {"id": "driver_3", "name": "Steady Volleys", "condition": {"type": "megaprojectLevel", "megaproject": "mass_driver", "level": 3}},
  {"id": "driver_5", "name": "Rail to the Sky", "condition": {"type": "megaprojectLevel", "megaproject": "mass_driver", "level": 5}},
  {"id": "segment_flow", "name": "Assembly in Orbit", "condition": {"type": "productionRate", "resource": "station_segment", "perSec": "0.03"}},
  {"id": "steel_flow", "name": "Iron Tide", "condition": {"type": "productionRate", "resource": "steel", "perSec": "20"}},
  {"id": "wire_flow_150", "name": "Copper Flood", "condition": {"type": "productionRate", "resource": "copper_wire", "perSec": "150"}}
]
''',
  'resources': r'''[
  {"id": "iron_ore", "name": "Iron Ore", "tier": 0, "basePrice": "1", "marketDepth": 10000, "marketFloor": 0.00001},
  {"id": "copper_ore", "name": "Copper Ore", "tier": 0, "basePrice": "1.5", "marketDepth": 6700, "marketFloor": 0.00001},
  {"id": "silicon", "name": "Silicon", "tier": 0, "basePrice": "1.2", "marketDepth": 8300, "marketFloor": 0.00001},
  {"id": "water_ice", "name": "Water Ice", "tier": 0, "basePrice": "0.8", "marketDepth": 12000, "marketFloor": 0.00001},
  {"id": "nickel", "name": "Nickel", "tier": 0, "basePrice": "2.5", "marketDepth": 4000, "marketFloor": 0.00001},
  {"id": "ammonia", "name": "Ammonia", "tier": 0, "basePrice": "1.5", "marketDepth": 6700, "marketFloor": 0.00001},
  {"id": "hydrogen", "name": "Hydrogen", "tier": 0, "basePrice": "1", "marketDepth": 10000, "marketFloor": 0.00001},
  {"id": "helium_3", "name": "Helium-3", "tier": 0, "basePrice": "4", "marketDepth": 2500, "marketFloor": 0.00001},
  {"id": "sulfur", "name": "Sulfur", "tier": 0, "basePrice": "1", "marketDepth": 10000, "marketFloor": 0.00001},
  {"id": "rare_earths", "name": "Rare Earths", "tier": 0, "basePrice": "3", "marketDepth": 3300, "marketFloor": 0.00001},

  {"id": "steel", "name": "Steel", "tier": 1, "basePrice": "6", "marketDepth": 833333, "marketFloor": 0.00005},
  {"id": "copper_wire", "name": "Copper Wire", "tier": 1, "basePrice": "2", "marketDepth": 2500000, "marketFloor": 0.00005},
  {"id": "silicon_wafer", "name": "Silicon Wafer", "tier": 1, "basePrice": "7", "marketDepth": 714286, "marketFloor": 0.00005},
  {"id": "water", "name": "Water", "tier": 1, "basePrice": "2.2", "marketDepth": 2272727, "marketFloor": 0.00005},
  {"id": "oxygen", "name": "Oxygen", "tier": 1, "basePrice": "4", "marketDepth": 1250000, "marketFloor": 0.00005},
  {"id": "fuel", "name": "Fuel", "tier": 1, "basePrice": "6", "marketDepth": 833333, "marketFloor": 0.00005},
  {"id": "fertilizer", "name": "Fertilizer", "tier": 1, "basePrice": "8", "marketDepth": 625000, "marketFloor": 0.00005},
  {"id": "food", "name": "Food", "tier": 1, "basePrice": "9", "marketDepth": 555556, "marketFloor": 0.00005},

  {"id": "circuit", "name": "Circuit", "tier": 2, "basePrice": "20", "marketDepth": 3000000},
  {"id": "hull_plate", "name": "Hull Plate", "tier": 2, "basePrice": "30", "marketDepth": 2000000},
  {"id": "magnet", "name": "Magnet", "tier": 2, "basePrice": "28", "marketDepth": 2142857},
  {"id": "reactor_core", "name": "Reactor Core", "tier": 2, "basePrice": "150", "marketDepth": 400000},
  {"id": "habitat_module", "name": "Habitat Module", "tier": 2, "basePrice": "320", "marketDepth": 1, "marketFloor": 0.00001},
  {"id": "cargo_ship", "name": "Cargo Ship", "tier": 2, "basePrice": "230", "marketDepth": 1, "marketFloor": 0.00001},
  {"id": "outpost_kit", "name": "Outpost Kit", "tier": 2, "basePrice": "600", "marketDepth": 1, "marketFloor": 0.00001},

  {"id": "station_segment", "name": "Station Segment", "tier": 3, "basePrice": "1000", "marketDepth": 150000},
  {"id": "survey_drone", "name": "Survey Drone", "tier": 3, "basePrice": "480", "marketDepth": 208333}
]
''',
  'rules': r'''{
  "speedPerLevel": 1.1,
  "speedMilestoneEvery": 25,
  "speedMilestoneMult": 2,
  "efficiencyPerLevel": 0.95,
  "efficiencyFloor": 0.25,
  "capacityCrewPerLevel": 1,
  "capacityStoragePerLevel": 0.2,
  "capacityHousingPerLevel": 0.25,
  "baseStorageCap": 1000,
  "offlineCapSeconds": 43200,
  "marketFloor": 0.002,
  "marketRecoverySeconds": 1800,
  "claimBaseCredits": "5e3",
  "claimGrowth": 8,
  "claimKitsBase": 5,
  "claimKitsPerOwned": 5,
  "slotBaseCredits": "5e4",
  "slotGrowth": 2.0,
  "outpostKitResource": "outpost_kit",
  "shipCapacityPerSecond": 10,
  "cargoShipResource": "cargo_ship",
  "baseTravelSeconds": 60,
  "shipmentMergeSeconds": 10,
  "claimSecondsBase": 1800,
  "claimSecondsPerOwned": 1800,
  "expandSlotsSeconds": 3600,
  "contractRefillSeconds": 14400,
  "nearReadyHorizonSeconds": 43200,
  "surveyDrones": 3,
  "surveyCredits": "2e4",
  "surveySeconds": 10800
}
''',
};
