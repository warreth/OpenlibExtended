// Dart imports:
import 'dart:convert';
import 'dart:io';

// Project imports:
import 'package:openlib/cli/annas_archive.dart';
import 'package:openlib/cli/slum.dart';

/// AI-facing command line interface for OpenlibExtended.
///
/// Every command prints one JSON document on stdout and keeps progress
/// and diagnostics on stderr as JSON lines, so an agent only ever has
/// to parse stdout. Exit codes: 0 ok, 1 usage, 2 challenge-blocked,
/// 3 not found, 4 network failure.
///
/// Run from the repository root after `flutter pub get`:
///
///     dart run bin/ai_cli.dart search "quantum computing" --ext epub
///     dart run bin/ai_cli.dart info <md5>
///     dart run bin/ai_cli.dart download <md5> --output ~/books
Future<void> main(List<String> arguments) async {
  final parsed = _parseArgs(arguments);
  cliQuiet = parsed['quiet'] == true;
  if (parsed['help'] == true || arguments.isEmpty) {
    stdout.write(_help);
    exitCode = arguments.isEmpty ? 1 : 0;
    return;
  }

  final command = parsed['command'] as String?;
  try {
    switch (command) {
      case 'search':
        await _search(parsed);
      case 'info':
        await _info(parsed);
      case 'download':
        await _download(parsed);
      case 'mirrors':
        await _mirrors(parsed);
      case 'version':
        _emit({'name': 'openlib-ai-cli', 'version': '1.0.0'});
      default:
        _emitError('usage', 'Unknown command: ${command ?? '(none)'}');
        exitCode = 1;
    }
  } on CliBlockException catch (e) {
    _emitError('blocked', e.message,
        url: e.url, attempts: e.attempts);
    exitCode = 2;
  } on CliNotFoundException catch (e) {
    _emitError('not_found', e.message);
    exitCode = 3;
  } on CliNetworkException catch (e) {
    _emitError('network', e.message, attempts: e.attempts);
    exitCode = 4;
  } catch (e) {
    var message = e.toString();
    if (message.length > 300) message = message.substring(0, 300);
    _emitError('network', message);
    exitCode = 4;
  }
}

Future<List<String>> _resolveMirrors(Map<String, dynamic> parsed) async {
  final override = parsed['base-url'] as String?;
  if (override != null) {
    return [CliSlumCatalogue.normalizeUrl(override)];
  }

  _emitEvent('progress', {'step': 'resolving_mirrors',
      'source': CliSlumCatalogue.defaultBaseUrl});
  final sites = await CliSlumCatalogue().fetchAnnasMirrors();
  if (sites.isEmpty) {
    _emitError('no_mirrors',
        'open-slum.org returned no usable Anna\'s Archive mirror. '
        'Retry, or pass --base-url with a known mirror.');
    exitCode = 4;
    return const [];
  }
  // Bound the walk: the first handful of ordered mirrors is what the
  // app effectively reaches in practice too.
  return sites.take(6).map((site) => site.url).toList();
}

Future<CliAnnasArchive> _client(Map<String, dynamic> parsed) async {
  final mirrors = await _resolveMirrors(parsed);
  final timeoutSeconds = int.tryParse(parsed['timeout'] as String? ?? '');
  return CliAnnasArchive(
    mirrors: mirrors,
    requestTimeout: timeoutSeconds != null && timeoutSeconds > 0
        ? Duration(seconds: timeoutSeconds)
        : null,
  );
}

Future<void> _search(Map<String, dynamic> parsed) async {
  final query = parsed['positional']?[0] as String?;
  if (query == null || query.isEmpty) {
    _emitError('usage', 'search needs a query: search "machine learning"');
    exitCode = 1;
    return;
  }

  final client = await _client(parsed);
  final page = int.tryParse(parsed['page'] as String? ?? '') ?? 1;
  final limit = int.tryParse(parsed['limit'] as String? ?? '') ?? 25;

  final books = await client.searchBooks(
    query,
    content: parsed['content'] as String? ?? '',
    sort: parsed['sort'] as String? ?? '',
    fileType: parsed['ext'] as String? ?? '',
    language: parsed['lang'] as String? ?? '',
    yearFrom: parsed['year-from'] as String?,
    yearTo: parsed['year-to'] as String?,
    author: parsed['author'] as String? ?? '',
    publisher: parsed['publisher'] as String? ?? '',
    page: page,
  );

  final limited = limit > 0 ? books.take(limit).toList() : books;
  _emit({
    'query': query,
    'page': page,
    'count': limited.length,
    'results': [for (final book in limited) book.toJson()],
  });
}

Future<void> _info(Map<String, dynamic> parsed) async {
  final target = parsed['positional']?[0] as String?;
  if (target == null || target.isEmpty) {
    _emitError('usage', 'info needs an md5 or book URL');
    exitCode = 1;
    return;
  }

  final client = await _client(parsed);
  final details = await client.bookInfo(target);
  _emit(details.toJson());
}

Future<void> _download(Map<String, dynamic> parsed) async {
  final target = parsed['positional']?[0] as String?;
  if (target == null || target.isEmpty) {
    _emitError('usage', 'download needs an md5 or book URL');
    exitCode = 1;
    return;
  }

  final client = await _client(parsed);
  _emitEvent('progress', {'step': 'book_info'});

  final details = await client.bookInfo(target);
  final slowUrl = details.slowDownloadUrl;
  if (slowUrl == null) {
    _emitError('not_found',
        'The book page has no slow_download link. This record may only '
        'offer fast (member) downloads.');
    exitCode = 3;
    return;
  }

  _emitEvent('progress', {'step': 'resolving_download_link'});
  final directUrl = await client.resolveSlowDownload(slowUrl);

  final outputPath = _outputPathFor(parsed, details);
  _emitEvent('progress', {
    'step': 'downloading',
    'file': outputPath,
    'url': directUrl,
  });

  final bytes = await client.downloadFile(
    url: directUrl,
    savePath: outputPath,
    onProgress: (received, total) {
      _emitEvent('progress', {
        'step': 'downloading',
        'received_bytes': received,
        if (total != null) 'total_bytes': total,
        if (total != null && total > 0)
          'percent': (received / total * 100).clamp(0, 100).toStringAsFixed(1),
      });
    },
  );

  _emit({
    'status': 'downloaded',
    'path': outputPath,
    'bytes': bytes,
    'md5': details.md5,
    'title': details.title,
    'author': details.author,
    'format': details.format,
    'source_url': directUrl,
  });
}

/// Turns `--output` into a concrete file path. A directory (existing,
/// trailing slash, or no known book extension) receives the generated
/// file name; anything else is used verbatim.
String _outputPathFor(Map<String, dynamic> parsed, CliBookDetails details) {
  final raw = parsed['output'] as String?;
  final fileName = CliAnnasArchive.bookFileName(
    title: details.title,
    author: details.author,
    format: details.format,
    md5: details.md5,
  );

  if (raw == null || raw.isEmpty) {
    return fileName;
  }
  final normalized = raw.replaceAll('\\', '/');
  final looksLikeDirectory = normalized.endsWith('/') ||
      Directory(normalized).existsSync() ||
      !normalized.contains('.');
  if (looksLikeDirectory) {
    final dir = Directory(normalized)..createSync(recursive: true);
    return '${dir.path}${Platform.pathSeparator}$fileName';
  }
  final file = File(normalized);
  file.parent.createSync(recursive: true);
  return file.path;
}

Future<void> _mirrors(Map<String, dynamic> parsed) async {
  _emitEvent('progress', {'step': 'resolving_mirrors',
      'source': CliSlumCatalogue.defaultBaseUrl});
  final sites = await CliSlumCatalogue().fetchAnnasMirrors();
  _emit({
    'source': CliSlumCatalogue.defaultBaseUrl,
    'count': sites.length,
    'mirrors': [for (final site in sites) site.toJson()],
  });
}

// --------------------------------------------------------------------
// Argument handling (hand-rolled: the repo avoids new dependencies).
// --------------------------------------------------------------------

/// Flags that take a value.
const _valueFlags = {
  'base-url': 'base-url',
  'timeout': 'timeout',
  'output': 'output',
  'ext': 'ext',
  'lang': 'lang',
  'sort': 'sort',
  'content': 'content',
  'author': 'author',
  'publisher': 'publisher',
  'year-from': 'year-from',
  'year-to': 'year-to',
  'page': 'page',
  'limit': 'limit',
};

/// Flags that are plain switches.
const _boolFlags = {'help', 'quiet', 'json', 'progress'};

Map<String, dynamic> _parseArgs(List<String> arguments) {
  final result = <String, dynamic>{};
  final positional = <String>[];

  for (var i = 0; i < arguments.length; i++) {
    var arg = arguments[i];
    if (!arg.startsWith('--')) {
      positional.add(arg);
      continue;
    }
    arg = arg.substring(2);

    String? value;
    final eq = arg.indexOf('=');
    if (eq != -1) {
      value = arg.substring(eq + 1);
      arg = arg.substring(0, eq);
    }

    if (_valueFlags.containsKey(arg)) {
      value ??= (i + 1 < arguments.length) ? arguments[++i] : null;
      result[arg] = value;
    } else if (_boolFlags.contains(arg)) {
      result[arg] = true;
    } else {
      result['unknown-$arg'] = true;
    }
  }

  result['positional'] = positional;
  if (positional.isNotEmpty) {
    result['command'] = positional.first;
    if (positional.length > 1) {
      result['positional'] = positional.sublist(1);
    }
  }
  return result;
}

// --------------------------------------------------------------------
// Output helpers. stdout: exactly one JSON document. stderr: JSON lines.
// --------------------------------------------------------------------

void _emit(Map<String, dynamic> document) {
  stdout.writeln(const JsonEncoder.withIndent('  ').convert(document));
}

void _emitEvent(String event, Map<String, dynamic> data) {
  if (cliQuiet) return;
  stderr.writeln(jsonEncode({'event': event, ...data}));
}

/// Set from `--quiet` in [main]; suppresses stderr progress events.
bool cliQuiet = false;

void _emitError(String code, String message,
    {String? url, List<CliAttempt> attempts = const []}) {
  stdout.writeln(jsonEncode({
    'error': {
      'code': code,
      'message': message,
      if (url != null) 'url': url,
      if (attempts.isNotEmpty)
        'attempts': [for (final attempt in attempts) attempt.toJson()],
    },
  }));
}

const String _help = '''
openlib-ai-cli: search and download books from Anna's Archive.
Part of OpenlibExtended (https://github.com/warreth/OpenlibExtended).

Usage (from the repo root, after `flutter pub get`):
  dart run bin/ai_cli.dart <command> [options]

Commands:
  search <query>       Search books. Options:
                         --ext epub|pdf|cbz|cbr   file extension filter
                         --lang en                language code
                         --sort newest|oldest|... results ordering
                         --content book_fiction   content class filter
                         --author NAME            field-scoped author
                         --publisher NAME         field-scoped publisher
                         --year-from 1990 --year-to 2005
                         --page N                 result page (default 1)
                         --limit N                max results (default 25)
  info <md5|url>       Book details (title, author, description, format,
                       slow_download link).
  download <md5|url>   Download the book. Options:
                         --output PATH  target file or directory
                                        (default: generated name in cwd)
  mirrors              List Anna's Archive mirrors known to open-slum.org.
  version              Print the CLI version.

Global options:
  --base-url URL       Use only this Anna's Archive mirror.
  --timeout SECONDS    Per-request timeout (default 8).

Output contract:
  stdout               Exactly one JSON document (the result, or an
                       {"error": {code, message}} document).
  stderr               JSON-line progress events (search/download steps,
                       download progress with received/total bytes).
Exit codes: 0 ok, 1 usage, 2 challenge-blocked, 3 not found, 4 network.

Examples:
  dart run bin/ai_cli.dart search "quantum computing" --ext epub --limit 5
  dart run bin/ai_cli.dart info 8efbf8e9f8b4592c7b0dbedec9c0ec05
  dart run bin/ai_cli.dart download 8efbf8e9f8b4592c7b0dbedec9c0ec05 --output ~/books
''';
