// Dart imports:
import 'dart:io';

// Project imports:
import 'package:openlib/cli/runner.dart';

/// AI-facing command line interface for OpenlibExtended.
///
/// Every command prints one JSON document on stdout and keeps progress and
/// diagnostics on stderr as JSON lines, so an agent only ever has to parse
/// stdout. Exit codes: 0 ok, 1 usage, 2 challenge-blocked, 3 not found,
/// 4 network failure.
///
/// Run from the repository root after `flutter pub get`:
///
///     dart run bin/ai_cli.dart search "quantum computing" --ext epub
///     dart run bin/ai_cli.dart info <md5>
///     dart run bin/ai_cli.dart download <md5> --output ~/books
Future<void> main(List<String> arguments) async {
  final runner = CliRunner(
    writeOut: stdout.write,
    writeErr: stderr.write,
  );
  exitCode = await runner.run(arguments);
}
