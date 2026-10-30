// Dart imports:
import 'dart:convert';
import 'dart:io';

// Project imports:
import 'package:openlib/cli/annas_archive.dart';
import 'package:openlib/cli/options.dart';
import 'package:openlib/cli/slum.dart';
import 'package:openlib/core/slum.dart';

/// Writes one chunk to stdout or stderr.
typedef CliWrite = void Function(String text);

/// Builds a client for one invocation; injectable for tests.
typedef CliArchiveClientFactory = Future<CliArchiveClient> Function(
    CliOptions options);

/// Loads the raw mirror list; injectable for tests.
typedef CliMirrorsLoader = Future<List<SlumSite>> Function();

/// Runs the CLI and returns its process exit code.
///
/// Contract: a command writes exactly one JSON document to [writeOut] - the
/// result or an error - and progress events as JSON lines to [writeErr].
class CliRunner {
  CliRunner({
    required this.writeOut,
    required this.writeErr,
    CliArchiveClientFactory? clientFactory,
    CliMirrorsLoader? mirrorsLoader,
  })  : _clientFactory = clientFactory,
        _mirrorsLoader = mirrorsLoader;

  final CliWrite writeOut;
  final CliWrite writeErr;
  final CliArchiveClientFactory? _clientFactory;
  final CliMirrorsLoader? _mirrorsLoader;

  bool _quiet = false;

  static const String _version = '1.1.0';

  Future<int> run(List<String> arguments) async {
    CliOptions options;
    try {
      options = CliOptions.parse(arguments);
    } on CliUsageException catch (e) {
      _error('usage', e.message);
      return 1;
    }

    _quiet = options.flag('quiet');
    if (arguments.isEmpty) {
      _writeHelp();
      return 1;
    }
    if (options.flag('help')) {
      _writeHelp();
      return 0;
    }

    final command = options.command;
    if (command == null) {
      _writeHelp();
      return 1;
    }

    try {
      switch (command) {
        case 'search':
          await _search(options);
          break;
        case 'info':
          await _info(options);
          break;
        case 'download':
          await _download(options);
          break;
        case 'mirrors':
          await _mirrors();
          break;
        case 'version':
          _result({'name': 'openlib-ai-cli', 'version': _version});
          break;
        default:
          throw CliUsageException('Unknown command: $command');
      }
      return 0;
    } on CliUsageException catch (e) {
      _error('usage', e.message);
      return 1;
    } on CliBlockException catch (e) {
      _error('blocked', e.message, url: e.url, attempts: e.attempts);
      return 2;
    } on CliNotFoundException catch (e) {
      _error('not_found', e.message);
      return 3;
    } on CliNetworkException catch (e) {
      _error('network', e.message, attempts: e.attempts);
      return 4;
    } catch (e) {
      var message = e.toString();
      if (message.length > 300) message = message.substring(0, 300);
      _error('network', message);
      return 4;
    }
  }

  Future<CliArchiveClient> _client(CliOptions options) async {
    final injected = _clientFactory;
    if (injected != null) return injected(options);

    final override = options.value('base-url');
    final List<String> mirrors;
    if (override != null) {
      mirrors = [CliSlumCatalogue.normalizeUrl(override)];
    } else {
      final sites = await _loadMirrors();
      mirrors = [for (final site in sites) site.url];
    }

    final timeout =
        options.intValue('timeout', defaultValue: 8, min: 1, max: 600);
    return CliAnnasArchive(
      mirrors: mirrors,
      requestTimeout: Duration(seconds: timeout),
    );
  }

  /// Loads and orders SLUM mirrors. By default only attemptable mirrors are
  /// returned, capped to the first six as the app effectively walks them.
  Future<List<SlumSite>> _loadMirrors({bool includeDown = false}) async {
    final loader = _mirrorsLoader ?? CliSlumCatalogue().fetchAnnasMirrors;
    final sites = await loader();
    if (sites.isEmpty) {
      throw CliNetworkException(
          'open-slum.org returned no Anna\'s Archive mirror. '
          'Retry, or pass --base-url with a known mirror.');
    }

    final ordered = sortSlumSites(sites);
    if (includeDown) return ordered;

    final attemptable = ordered.where((site) => !site.isDown).take(6).toList();
    if (attemptable.isEmpty) {
      throw CliNetworkException(
          'open-slum.org reports every Anna\'s Archive mirror as down. '
          'Retry later, or pass --base-url with a known mirror.');
    }
    return attemptable;
  }

  Future<void> _search(CliOptions options) async {
    final query = options.requirePositional(0, 'search needs one query');
    final page = options.intValue('page', defaultValue: 1, min: 1, max: 10000);
    final limit = options.intValue('limit', defaultValue: 25, min: 1, max: 500);

    final client = await _client(options);
    final books = await client.searchBooks(
      query,
      content: options.value('content') ?? '',
      sort: options.value('sort') ?? '',
      fileType: options.value('ext') ?? '',
      language: options.value('lang') ?? '',
      yearFrom: options.value('year-from'),
      yearTo: options.value('year-to'),
      author: options.value('author') ?? '',
      publisher: options.value('publisher') ?? '',
      page: page,
    );

    final limited = books.take(limit).toList();
    _result({
      'query': query,
      'page': page,
      'count': limited.length,
      'results': [for (final book in limited) book.toJson()],
    });
  }

  Future<void> _info(CliOptions options) async {
    final target =
        options.requirePositional(0, 'info needs an md5 or book URL');
    final client = await _client(options);
    final details = await client.bookInfo(target);
    _result(details.toJson());
  }

  Future<void> _download(CliOptions options) async {
    final target =
        options.requirePositional(0, 'download needs an md5 or book URL');
    final client = await _client(options);
    _event('progress', {'step': 'book_info'});

    final details = await client.bookInfo(target);
    final slowUrl = details.slowDownloadUrl;
    if (slowUrl == null) {
      throw CliNotFoundException(
          'The book page has no slow_download link. This record may only '
          'offer fast (member) downloads.');
    }

    _event('progress', {'step': 'resolving_download_link'});
    final directUrl = await client.resolveSlowDownload(slowUrl);

    final outputPath = _outputPathFor(options, details);
    _event('progress', {
      'step': 'downloading',
      'file': outputPath,
      'url': directUrl,
    });

    var totalBytes = 0;
    var lastEmit = DateTime.fromMillisecondsSinceEpoch(0);
    final bytes = await client.downloadFile(
      url: directUrl,
      savePath: outputPath,
      onProgress: (received, total) {
        totalBytes = total ?? 0;
        final percent = total != null && total > 0
            ? (received / total * 100).clamp(0, 100).toDouble()
            : null;
        final now = DateTime.now();
        final finished = percent != null && percent >= 100;
        if (now.difference(lastEmit) < const Duration(milliseconds: 250) &&
            !finished) {
          return;
        }
        lastEmit = now;
        _event('progress', {
          'step': 'downloading',
          'received_bytes': received,
          if (total != null) 'total_bytes': total,
          if (percent != null) 'percent': percent.toStringAsFixed(1),
        });
      },
    );

    _event('progress', {
      'step': 'downloading',
      'received_bytes': bytes,
      if (totalBytes > 0) 'total_bytes': totalBytes,
      'percent': '100.0',
    });

    _result({
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

  Future<void> _mirrors() async {
    _event('progress', {
      'step': 'resolving_mirrors',
      'source': CliSlumCatalogue.defaultBaseUrl,
    });
    final sites = await _loadMirrors(includeDown: true);
    _result({
      'source': CliSlumCatalogue.defaultBaseUrl,
      'count': sites.length,
      'mirrors': [for (final site in sites) _slumSiteJson(site)],
    });
  }

  /// Turns `--output` into a concrete file path. A directory (existing,
  /// trailing slash, or a last segment without an extension) receives the
  /// generated file name; anything else is used verbatim.
  String _outputPathFor(CliOptions options, CliBookDetails details) {
    final raw = options.value('output');
    final fileName = CliAnnasArchive.bookFileName(
      title: details.title,
      author: details.author,
      format: details.format,
      md5: details.md5,
    );

    if (raw == null || raw.isEmpty) return fileName;

    final normalized = raw.replaceAll('\\', '/');
    final lastSegment = normalized.split('/').last;
    final looksLikeDirectory = normalized.endsWith('/') ||
        Directory(normalized).existsSync() ||
        !lastSegment.contains('.');
    if (looksLikeDirectory) {
      final dir = Directory(normalized)..createSync(recursive: true);
      return '${dir.path}${Platform.pathSeparator}$fileName';
    }
    final file = File(normalized);
    file.parent.createSync(recursive: true);
    return file.path;
  }

  Map<String, dynamic> _slumSiteJson(SlumSite site) => {
        'url': site.url,
        'host': site.host,
        'status': site.status.name,
        'protection': site.protection.name,
        if (site.httpStatus != null) 'http_status': site.httpStatus,
        if (site.latencyMs != null) 'latency_ms': site.latencyMs,
      };

  void _result(Map<String, dynamic> document) {
    writeOut('${const JsonEncoder.withIndent('  ').convert(document)}\n');
  }

  void _event(String event, Map<String, dynamic> data) {
    if (_quiet) return;
    writeErr('${jsonEncode({'event': event, ...data})}\n');
  }

  void _error(
    String code,
    String message, {
    String? url,
    List<CliAttempt> attempts = const [],
  }) {
    writeOut('${jsonEncode({
          'error': {
            'code': code,
            'message': message,
            if (url != null) 'url': url,
            if (attempts.isNotEmpty)
              'attempts': [for (final attempt in attempts) attempt.toJson()],
          },
        })}\n');
  }

  void _writeHelp() => writeOut(_help);
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
  mirrors              List every Anna's Archive mirror open-slum.org
                       reports, including down mirrors and their status.
  version              Print the CLI version.

Global options:
  --base-url URL       Use only this Anna's Archive mirror.
  --timeout SECONDS    Per-request timeout (default 8).
  --quiet              Suppress JSON progress events on stderr.

Output contract:
  stdout               Exactly one JSON document (the result, or an
                       {"error": {code, message, attempts}} document).
  stderr               JSON-line progress events (search/download steps,
                       download progress with received/total bytes).
Exit codes: 0 ok, 1 usage, 2 challenge-blocked, 3 not found, 4 network.

Examples:
  dart run bin/ai_cli.dart search "quantum computing" --ext epub --limit 5
  dart run bin/ai_cli.dart info 8efbf8e9f8b4592c7b0dbedec9c0ec05
  dart run bin/ai_cli.dart download 8efbf8e9f8b4592c7b0dbedec9c0ec05 --output ~/books
''';
