import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:game_core/game_core.dart';
import 'package:game_sim/src/content_files.dart';
import 'package:game_sim/src/script_runner.dart';

const _usage =
    'Usage: game_sim [--content content] [--seed 1] [--load save.json] '
    '[--script file.jsonl]\n       game_sim check [--content content]';

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

void main(List<String> argv) {
  final parser = ArgParser()
    ..addOption('content', defaultsTo: 'content')
    ..addOption('seed', defaultsTo: '1')
    ..addOption('load')
    ..addOption('script');
  final ArgResults args;
  try {
    args = parser.parse(argv);
  } on FormatException catch (e) {
    _usageError(e.message);
  }
  final rest = args.rest;
  if (rest.length > 1 || (rest.isNotEmpty && rest.first != 'check')) {
    _usageError('unexpected argument "${rest.join(' ')}"');
  }
  final loaded = _loadContent(args.option('content')!);

  if (rest.isNotEmpty) {
    for (final e in loaded.errors) {
      _emit({'ok': false, 'error': 'invalidContent', 'message': e});
    }
    if (loaded.errors.isEmpty) _emit({'ok': true});
    exit(loaded.errors.isEmpty ? 0 : 1);
  }
  if (loaded.content == null) {
    for (final e in loaded.errors) {
      _emit({'ok': false, 'error': 'invalidContent', 'message': e});
    }
    exit(1);
  }

  final seed = int.tryParse(args.option('seed')!);
  if (seed == null) _usageError('--seed must be an integer');
  final engine = GameEngine(loaded.content!);
  var state = engine.newGame(seed);
  final loadPath = args.option('load');
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

  final scriptPath = args.option('script');
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
