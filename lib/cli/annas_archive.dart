// Dart imports:
import 'dart:async';
import 'dart:io';

// Package imports:
import 'package:dio/dio.dart';

// Project imports:
import 'package:openlib/core/annas_archive.dart';

/// A search result in the shape an agent wants from JSON.
class CliBook {
  final String title;
  final String? author;
  final String? thumbnail;
  final String link;
  final String md5;
  final String? publisher;
  final String? info;

  const CliBook({
    required this.title,
    this.author,
    this.thumbnail,
    required this.link,
    required this.md5,
    this.publisher,
    this.info,
  });

  factory CliBook.fromArchive(ArchiveBook book) => CliBook(
        title: book.title,
        author: book.author,
        thumbnail: book.thumbnail,
        link: book.link,
        md5: book.md5,
        publisher: book.publisher,
        info: book.info,
      );

  String get format => ArchiveParsing.formatFromInfo(info);

  Map<String, dynamic> toJson() => {
        'md5': md5,
        'title': title,
        'author': author,
        'publisher': publisher,
        'format': format,
        'info': info,
        'link': link,
        if (thumbnail != null) 'thumbnail': thumbnail,
      };
}

/// Parsed `/md5/<md5>` detail page.
class CliBookDetails extends CliBook {
  final String? description;

  /// The `/slow_download/<...>` link on the detail page, when present.
  final String? slowDownloadUrl;

  const CliBookDetails({
    required super.title,
    super.author,
    super.thumbnail,
    required super.link,
    required super.md5,
    super.publisher,
    super.info,
    this.description,
    this.slowDownloadUrl,
  });

  factory CliBookDetails.fromArchive(ArchiveBookDetails details) =>
      CliBookDetails(
        title: details.title,
        author: details.author,
        thumbnail: details.thumbnail,
        link: details.link,
        md5: details.md5,
        publisher: details.publisher,
        info: details.info,
        description: details.description,
        slowDownloadUrl: details.slowDownloadUrl,
      );

  @override
  Map<String, dynamic> toJson() => {
        ...super.toJson(),
        'description': description,
        'slow_download_url': slowDownloadUrl,
      };
}

/// One mirror attempt, for the error report.
class CliAttempt {
  final String mirror;
  final String error;

  /// `challenge`, `forbidden`, `wrong_page`, `not_found`, `timeout`, `http_*`
  /// or `network`; lets an agent tell a Cloudflare gate from a dead host.
  final String kind;

  const CliAttempt(this.mirror, this.error, {this.kind = 'network'});

  Map<String, dynamic> toJson() =>
      {'mirror': mirror, 'kind': kind, 'error': error};
}

/// All mirrors were challenge-blocked. `url` is the last blocked URL so
/// the caller can retry it (in a browser, via a VPN, or later).
class CliBlockException implements Exception {
  final String message;
  final String? url;
  final List<CliAttempt> attempts;
  CliBlockException(this.message, {this.url, this.attempts = const []});
  @override
  String toString() => message;
}

/// The search or detail page answered but held no book data.
class CliNotFoundException implements Exception {
  final String message;
  CliNotFoundException(this.message);
  @override
  String toString() => message;
}

/// Network-level failure after every mirror attempt.
class CliNetworkException implements Exception {
  final String message;
  final String? lastHost;

  /// What every mirror answered, so an agent can decide whether a VPN,
  /// a different mirror (`--base-url`), or a later retry helps.
  final List<CliAttempt> attempts;
  CliNetworkException(this.message, {this.lastHost, this.attempts = const []});
  @override
  String toString() => message;
}

/// The operations the CLI runner needs from an Anna's Archive client.
///
/// Keeping this interface separate lets tests drive the runner with a fake
/// and leaves the network client free to change.
abstract interface class CliArchiveClient {
  Future<List<CliBook>> searchBooks(
    String query, {
    String content,
    String sort,
    String fileType,
    String language,
    String? yearFrom,
    String? yearTo,
    String author,
    String publisher,
    int page,
  });

  Future<CliBookDetails> bookInfo(String md5OrUrl);

  Future<String> resolveSlowDownload(String slowDownloadUrl);

  Future<int> downloadFile({
    required String url,
    required String savePath,
    void Function(int received, int? total)? onProgress,
  });
}

/// Pure-Dart Anna's Archive client for the CLI.
///
/// The request flow (browser-like headers, challenge detection, mirror
/// fallback loop) mirrors `lib/services/annas_archieve.dart`. HTML parsing
/// and URL building live in [ArchiveParsing] and are shared with the app, so
/// the two cannot drift apart.
class CliAnnasArchive implements CliArchiveClient {
  CliAnnasArchive({Dio? dio, List<String>? mirrors, Duration? requestTimeout})
      : dio = dio ?? Dio(),
        mirrors = mirrors ?? const [],
        requestTimeout = requestTimeout ?? const Duration(seconds: 8);

  final Dio dio;
  final List<String> mirrors;

  /// Per-request timeout for search/info pages.
  final Duration requestTimeout;

  // Same constants as the app service.
  static const int maxRetriesPerMirror = 1;
  static const int retryDelayMs = 200;

  static const Map<String, String> defaultHeaders = {
    'user-agent':
        'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36',
    'accept':
        'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8',
    'accept-language': 'en-US,en;q=0.9',
  };

  bool isChallengeResponse(Response response) {
    return ArchiveParsing.isChallengeResponse(
      statusCode: response.statusCode ?? 0,
      cfMitigated: response.headers.value('cf-mitigated'),
      body: response.data?.toString() ?? '',
    );
  }

  /// True when the page is an Anna's Archive document rather than an
  /// unrelated site sharing the host.
  bool isAnnasArchivePage(String html) => ArchiveParsing.isArchivePage(html);

  void _ensureResponseStatus(Response response, String url) {
    final status = response.statusCode ?? 0;
    if (status >= 200 && status < 300) return;
    throw DioException.badResponse(
      statusCode: status,
      requestOptions: response.requestOptions,
      response: response,
    );
  }

  Future<Response> _makeRequest(String url) async {
    return await dio.get(
      url,
      options: Options(
        headers: {...defaultHeaders},
        responseType: ResponseType.plain,
        validateStatus: (_) => true,
      ),
    );
  }

  /// Mirror fallback loop, same shape as the app's `_requestWithRetry`:
  /// one retry on the first mirror, straight walk after that, every
  /// failure recorded. Typed client errors survive the walk so a missing
  /// book is reported as not-found rather than a vague network failure.
  Future<T> requestWithMirrorFallback<T>(
    Future<T> Function(String baseUrl) requestFn,
  ) async {
    if (mirrors.isEmpty) {
      throw CliNetworkException(
          'No Anna\'s Archive mirror is available right now '
          '(open-slum.org unreachable?)');
    }

    Object? lastError;
    String? lastHost;
    final attempts = <CliAttempt>[];

    for (var i = 0; i < mirrors.length; i++) {
      final baseUrl = mirrors[i];
      final retriesForThis = i == 0 ? maxRetriesPerMirror : 0;

      for (var attempt = 0; attempt <= retriesForThis; attempt++) {
        try {
          return await requestFn(baseUrl).timeout(
            requestTimeout,
            onTimeout: () => throw TimeoutException(
                'Request timed out after ${requestTimeout.inSeconds}s'),
          );
        } catch (e) {
          lastError = e;
          lastHost = baseUrl;
          attempts.add(CliAttempt(
            baseUrl,
            _shortError(e),
            kind: _attemptKind(e),
          ));
          if (attempt < retriesForThis) {
            await Future.delayed(const Duration(milliseconds: retryDelayMs));
          }
        }
      }
    }

    if (lastError is CliBlockException) {
      throw CliBlockException(lastError.message,
          url: lastError.url, attempts: attempts);
    }
    if (lastError is CliNotFoundException) {
      throw lastError;
    }
    if (lastError is CliNetworkException) {
      throw CliNetworkException(
        lastError.message,
        lastHost: lastHost,
        attempts: attempts,
      );
    }
    throw CliNetworkException(
      'All mirrors failed: ${_shortError(lastError)}',
      lastHost: lastHost,
      attempts: attempts,
    );
  }

  static String _attemptKind(Object error) {
    if (error is CliBlockException) return 'challenge';
    if (error is CliNotFoundException) return 'not_found';
    if (error is TimeoutException) return 'timeout';
    if (error is DioException) {
      final status = error.response?.statusCode;
      if (status == 403) return 'forbidden';
      if (status == 404) return 'not_found';
      if (status != null) return 'http_$status';
    }
    if (error.toString().contains('did not serve')) return 'wrong_page';
    return 'network';
  }

  static String _shortError(Object? error) {
    final text = error.toString();
    return text.length > 160 ? text.substring(0, 160) : text;
  }

  // ------------------------------------------------------------------
  // Search.
  // ------------------------------------------------------------------

  @override
  Future<List<CliBook>> searchBooks(
    String query, {
    String content = '',
    String sort = '',
    String fileType = '',
    String language = '',
    String? yearFrom,
    String? yearTo,
    String author = '',
    String publisher = '',
    int page = 1,
  }) async {
    return requestWithMirrorFallback<List<CliBook>>((baseUrl) async {
      final url = ArchiveParsing.buildSearchUrl(
        baseUrl: baseUrl,
        query: query,
        content: content,
        sort: sort,
        fileType: fileType,
        language: language,
        yearFrom: yearFrom,
        yearTo: yearTo,
        author: author,
        publisher: publisher,
        page: page,
      );
      final response = await _makeRequest(url);

      if (isChallengeResponse(response)) {
        throw CliBlockException(
          'Access blocked by bot protection on $baseUrl. '
          'A browser challenge must be solved before this works.',
          url: url,
        );
      }
      _ensureResponseStatus(response, url);
      final body = response.data?.toString() ?? '';
      if (!isAnnasArchivePage(body)) {
        throw Exception(
            'Mirror $baseUrl did not serve an Anna\'s Archive page');
      }
      return [
        for (final book in ArchiveParsing.parseSearchResults(
          body,
          baseUrl: baseUrl,
          fileType: fileType,
        ))
          CliBook.fromArchive(book),
      ];
    });
  }

  /// Parses a search results page. Kept public for tests and for callers
  /// that already have HTML (for example a solved challenge page).
  List<CliBook> parseSearchResults(
    String html, {
    String fileType = '',
    String baseUrl = '',
  }) {
    return [
      for (final book in ArchiveParsing.parseSearchResults(
        html,
        baseUrl: baseUrl,
        fileType: fileType,
      ))
        CliBook.fromArchive(book),
    ];
  }

  // ------------------------------------------------------------------
  // Detail page.
  // ------------------------------------------------------------------

  @override
  Future<CliBookDetails> bookInfo(String md5OrUrl) async {
    return requestWithMirrorFallback<CliBookDetails>((baseUrl) async {
      final url = normalizeBookUrl(md5OrUrl, baseUrl);
      final response = await _makeRequest(url);

      if (isChallengeResponse(response)) {
        throw CliBlockException(
          'Access blocked by bot protection on $baseUrl. '
          'A browser challenge must be solved before this works.',
          url: url,
        );
      }
      _ensureResponseStatus(response, url);
      final details = ArchiveParsing.parseBookDetails(
        response.data?.toString() ?? '',
        url: url,
        baseUrl: baseUrl,
      );
      if (details == null) {
        throw CliNotFoundException(
            'No book details on $url. The md5 link may be outdated - '
            'search for the title instead.');
      }
      return CliBookDetails.fromArchive(details);
    });
  }

  /// Parses one `/md5/` detail page. Returns null when the page holds no
  /// book record.
  CliBookDetails? parseBookInfo(
    String html, {
    required String url,
    String baseUrl = '',
  }) {
    final details = ArchiveParsing.parseBookDetails(
      html,
      url: url,
      baseUrl: baseUrl,
    );
    return details == null ? null : CliBookDetails.fromArchive(details);
  }

  // ------------------------------------------------------------------
  // Download.
  // ------------------------------------------------------------------

  /// Resolves the direct download link behind a book's slow_download page.
  @override
  Future<String> resolveSlowDownload(String slowDownloadUrl) async {
    final response = await _fetchPlain(slowDownloadUrl);
    if (isChallengeResponse(response)) {
      throw CliBlockException(
        'Access blocked by bot protection on the download page. '
        'A browser challenge must be solved before this works.',
        url: slowDownloadUrl,
      );
    }
    _ensureResponseStatus(response, slowDownloadUrl);

    final link = ArchiveParsing.extractSlowDownloadLink(
      response.data?.toString() ?? '',
      pageUrl: slowDownloadUrl,
    );
    if (link == null) {
      throw CliNotFoundException(
          'No download link on the slow_download page (link expired or '
          'page changed). Re-fetch the book info and retry.');
    }
    return link;
  }

  /// Extracts the direct link from slow_download page HTML, or null.
  static String? extractSlowDownloadLink(String html, {String pageUrl = ''}) =>
      ArchiveParsing.extractSlowDownloadLink(html, pageUrl: pageUrl);

  /// Streams a file to [savePath] with resume support.
  ///
  /// A Range request resumes an existing partial file; 416 means the file is
  /// already complete; a 200 after a Range resets the file. Reports progress
  /// through [onProgress] and returns the final byte count.
  @override
  Future<int> downloadFile({
    required String url,
    required String savePath,
    void Function(int received, int? total)? onProgress,
  }) async {
    final downloadDio = Dio();
    downloadDio.options.connectTimeout = const Duration(seconds: 30);
    downloadDio.options.receiveTimeout = const Duration(minutes: 60);

    final file = File(savePath);
    await file.parent.create(recursive: true);

    var received = 0;
    if (await file.exists()) {
      received = await file.length();
    }

    final options = Options(
      responseType: ResponseType.stream,
      headers: {
        ...defaultHeaders,
        'Connection': 'Keep-Alive',
        if (received > 0) 'Range': 'bytes=$received-',
      },
      validateStatus: (_) => true,
    );

    final response = await downloadDio.get<ResponseBody>(url, options: options);
    final status = response.statusCode ?? 0;

    // Range past EOF: the partial file is already the complete file.
    if (status == 416 && received > 0) {
      return received;
    }
    if (status < 200 || status >= 300) {
      throw CliNetworkException('Download failed with HTTP $status for $url');
    }

    int? contentLength;
    final contentLengthHeader = response.headers.value('content-length');
    if (contentLengthHeader != null) {
      contentLength = int.tryParse(contentLengthHeader);
    }

    // Server ignored the Range: start over.
    if (received > 0 && status == 200) {
      received = 0;
      await file.writeAsBytes([]);
    }

    final total = status == 206 && contentLength != null
        ? received + contentLength
        : contentLength;

    final sink = file.openWrite(mode: FileMode.append);
    try {
      await for (final chunk in response.data!.stream) {
        sink.add(chunk);
        received += chunk.length;
        onProgress?.call(received, total);
      }
      await sink.flush();
      await sink.close();
    } catch (_) {
      await sink.close();
      rethrow;
    }
    return received;
  }

  // ------------------------------------------------------------------
  // Small helpers.
  // ------------------------------------------------------------------

  Future<Response> _fetchPlain(String url) async {
    return await dio
        .get(
          url,
          options: Options(
            headers: {...defaultHeaders},
            responseType: ResponseType.plain,
            validateStatus: (_) => true,
          ),
        )
        .timeout(
          requestTimeout,
          onTimeout: () => throw TimeoutException(
              'Request timed out after ${requestTimeout.inSeconds}s'),
        );
  }

  /// Normalizes an md5 or any book URL to a `/md5/<md5>` path on [baseUrl].
  static String normalizeBookUrl(String md5OrUrl, String baseUrl) {
    final trimmed = md5OrUrl.trim();
    if (trimmed.startsWith('http')) {
      final uri = Uri.parse(trimmed);
      final segments = uri.pathSegments;
      final md5Index = segments.indexOf('md5');
      final md5 = md5Index >= 0 && md5Index + 1 < segments.length
          ? segments[md5Index + 1]
          : segments.isNotEmpty
              ? segments.last
              : '';
      if (md5.isNotEmpty) return '$baseUrl/md5/$md5';
    }
    return '$baseUrl/md5/$trimmed';
  }

  static String resolveRelative(String href, String pageUrl) =>
      ArchiveParsing.resolveRelative(href, pageUrl);

  /// Filesystem-safe book file name: sanitized title (+ author when
  /// present) and a short md5 suffix, in the book's format.
  static String bookFileName({
    required String title,
    String? author,
    required String format,
    required String md5,
  }) {
    String sanitize(String text) {
      final noEmoji = text
          .replaceAll(RegExp(r'[\u{1F300}-\u{1F9FF}]', unicode: true), '')
          .replaceAll(RegExp(r'[\u{2600}-\u{26FF}]', unicode: true), '')
          .replaceAll(RegExp(r'[^\x00-\x7F]+'), '')
          .replaceAll(RegExp(r'[\\/:*?"<>|]'), ' ')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      return noEmoji.isEmpty ? 'book' : noEmoji;
    }

    final parts = <String>[
      if (author != null && author.isNotEmpty && author != 'unknown')
        sanitize(author),
      sanitize(title),
    ];
    var name = parts.join(' - ');
    if (name.length > 120) name = name.substring(0, 120).trim();
    final suffix = md5.length >= 8 ? md5.substring(0, 8) : md5;
    return '$name ($suffix).$format';
  }
}
