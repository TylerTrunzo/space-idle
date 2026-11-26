import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:game_core/game_core.dart';
import 'package:game_sim/src/balance_report.dart';
import 'package:game_sim/src/bots/bot.dart';
import 'package:game_sim/src/content_files.dart';
import 'package:game_sim/src/script_runner.dart';

const _usage =
    'Usage: game_sim [--content content] [--seed 1] [--load save.json] '
    '[--script file.jsonl]\n'
    '       game_sim check [--content content]\n'
    '       game_sim bot [--bot greedy|balanced] [--hours 168] [--seed 1] '
    '[--format json|md] [--content content]';

/// Bots the `bot` subcommand can run, by name.
final Map<String, Bot Function()> _bots = {
  'greedy': GreedyBot.new,
  'balanced': BalancedBot.new,
};

Never _usageError(String message) {
  stderr.writeln('game_sim: $message\n$_usage');
  exit(2);
}

/// Loads and validates content, or returns the problems found.
({Content? content, List<String> errors}) _loadContent(String dir) {
  try {
    return switch (Content.fromBundle(loadContentDir(dir))) {
      ContentOk(:final content) => (content: content, errors: const []),
      ContentInvalid(:final errors) => (content: null, errors: errors),
    };
  } on FormatException catch (e) {
    return (content: null, errors: [e.message]);
  }
}

void _emit(Map<String, Object?> m) => stdout.writeln(jsonEncode(m));

void _emitContentErrors(List<String> errors) {
  for (final e in errors) {
    _emit({'ok': false, 'error': 'invalidContent', 'message': e});
  }
}

/// Looks up an option by name, giving its value or default.
typedef _Options = String? Function(String name);

int _seed(_Options opt) =>
    int.tryParse(opt('seed')!) ?? _usageError('--seed must be an integer');

/// Runs a bot session and prints its balance report.
void _runBot(_Options opt) {
  final hours = double.tryParse(opt('hours')!);
  if (hours == null || !hours.isFinite || hours <= 0) {
    _usageError('--hours must be a number above 0');
  }
  final seed = _seed(opt);
  final loaded = _loadContent(opt('content')!);
  if (loaded.content == null) {
    _emitContentErrors(loaded.errors);
    exit(1);
  }
  final report = runBotSession(
    GameEngine(loaded.content!),
    _bots[opt('bot')!]!(),
    seed: seed,
    hours: hours,
  );
  if (opt('format') == 'md') {
    stdout.write(report.toMarkdown());
  } else {
    _emit(report.toJson());
  }
}

void main(List<String> argv) {
  final parser = ArgParser()
    ..addOption('content', defaultsTo: 'content')
    ..addOption('seed', defaultsTo: '1')
    ..addOption('load')
    ..addOption('script')
    ..addCommand('check', ArgParser()..addOption('content'))
    ..addCommand(
      'bot',
      ArgParser()
        ..addOption('content')
        ..addOption('seed')
        ..addOption('bot', allowed: _bots.keys, defaultsTo: 'balanced')
        ..addOption('hours', defaultsTo: '168')
        ..addOption('format', allowed: ['json', 'md'], defaultsTo: 'json'),
    );
  final ArgResults top;
  try {
    top = parser.parse(argv);
  } on FormatException catch (e) {
    _usageError(e.message);
  }
  final sub = top.command;
  final rest = sub?.rest ?? top.rest;
  if (rest.isNotEmpty) {
    _usageError('unexpected argument "${rest.join(' ')}"');
  }
  // `--content` and `--seed` may come before or after the subcommand name;
  // the subcommand's own value wins, else the top level's value or default.
  String? opt(String name) {
    final own = sub != null && sub.options.contains(name);
    if (own && (sub.wasParsed(name) || !top.options.contains(name))) {
      return sub.option(name);
    }
    return top.option(name);
  }

  if (sub?.name == 'bot') return _runBot(opt);
  final loaded = _loadContent(opt('content')!);

  if (sub?.name == 'check') {
    _emitContentErrors(loaded.errors);
    if (loaded.errors.isEmpty) _emit({'ok': true});
    exit(loaded.errors.isEmpty ? 0 : 1);
  }
  if (loaded.content == null) {
    _emitContentErrors(loaded.errors);
    exit(1);
  }

  final seed = _seed(opt);
  final engine = GameEngine(loaded.content!);
  var state = engine.newGame(seed);
  final loadPath = opt('load');
  if (loadPath != null) {
    try {
      switch (SaveCodec.decode(
        File(loadPath).readAsStringSync(),
        engine.content,
      )) {
        case SaveOk(state: final s):
          state = s;
        case SaveError(:final message):
          _usageError('cannot load $loadPath: $message');
      }
    } on FileSystemException catch (e) {
      _usageError('cannot read $loadPath: ${e.message}');
    }
  }
  final runner = ScriptRunner(engine, state);

  final scriptPath = opt('script');
  final Stream<String> lines;
  if (scriptPath == null) {
    lines = stdin.transform(utf8.decoder).transform(const LineSplitter());
  } else {
    final f = File(scriptPath);
    if (!f.existsSync()) _usageError('no such script $scriptPath');
    lines = Stream.fromIterable(
      const LineSplitter().convert(f.readAsStringSync()),
    );
  }
  lines.listen((line) {
    if (line.trim().isEmpty) return;
    _emit(runner.handleLine(line));
  });
}
