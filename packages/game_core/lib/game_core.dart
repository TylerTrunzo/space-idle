/// Deterministic, headless economy engine for the space idle game.
library;

export 'src/commands/apply.dart';
export 'src/commands/command.dart';
export 'src/commands/outcome.dart';
export 'src/content/content.dart';
export 'src/num/big_num.dart';
export 'src/num/change.dart';
export 'src/num/format.dart';
export 'src/report/flow_report.dart';
export 'src/rng.dart';
// Engine internals stay inside the package: the contract reward basis and
// rounding, auto-delivery's steps and keeps, building tiers and the
// end-of-tick landing.
export 'src/sim/contracts.dart' hide incomeBasis, twoSignificantFigures;
export 'src/sim/crew.dart';
export 'src/sim/engine.dart';
export 'src/sim/logistics.dart' hide landArrivals;
export 'src/sim/market.dart' hide DeliveryKeeps, autoDeliveryKeeps;
export 'src/sim/megaprojects.dart';
// The engine's own milestone helpers stay inside the package.
export 'src/sim/milestones.dart'
    hide factionStock, hiddenBodies, milestoneProgressAt;
// megaprojectEtas looks one stage ahead only, which suits nextGoal (the
// soonest) but not a per-megaproject ETA: it stays inside.
export 'src/sim/offline_summary.dart' hide megaprojectEtas;
export 'src/sim/production.dart' hide buildingTier;
export 'src/sim/projects.dart';
export 'src/sim/survey.dart';
export 'src/state/game_state.dart';
export 'src/state/save_codec.dart';
