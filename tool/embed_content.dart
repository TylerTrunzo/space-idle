// Regenerates app/lib/generated/content_bundle.g.dart from content/*.json.
//
// Run from anywhere in the repo after editing content:
//
//     dart run tool/embed_content.dart
//
// Each file is embedded verbatim as a raw-string literal so the app ships the
// exact same bundle on every platform, with no asset loading. The app's
// content_source_test fails when this output is stale.
import 'dart:io';

void main() {
  final root = Directory.fromUri(Platform.script.resolve('..'));
  final contentDir = Directory.fromUri(root.uri.resolve('content/'));
  final out = File.fromUri(
    root.uri.resolve('app/lib/generated/content_bundle.g.dart'),
  );

  final files =
      contentDir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.json'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
  if (files.isEmpty) {
    stderr.writeln('No content/*.json found under ${contentDir.path}');
    exit(1);
  }

  final buf = StringBuffer()
    ..writeln('// GENERATED — do not edit. Source: content/*.json.')
    ..writeln('// Regenerate with `dart run tool/embed_content.dart`.')
    ..writeln()
    ..writeln(
      '/// Every `content/*.json` file, by file stem, as its raw JSON text.',
    )
    ..writeln('const Map<String, String> contentJson = {');
  for (final f in files) {
    final stem = f.uri.pathSegments.last.replaceAll('.json', '');
    final text = f.readAsStringSync();
    // A raw ''' literal cannot hold ''' itself or end on a quote, and a
    // leading newline would be dropped by the Dart multiline-string rule.
    if (text.contains("'''") || text.endsWith("'") || text.startsWith('\n')) {
      stderr.writeln('${f.path} cannot be embedded as a raw string literal');
      exit(1);
    }
    buf.writeln("  '$stem': r'''$text''',");
  }
  buf.writeln('};');

  out.parent.createSync(recursive: true);
  out.writeAsStringSync(buf.toString());
  stdout.writeln('Wrote ${out.path} (${files.length} files)');
}
