// Dart imports:
import 'dart:async';
import 'dart:io';

// Package imports:
import 'package:dio/dio.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' show parse;

/// A search result. Same fields the app's `BookData` carries, in the
/// shape an agent wants from JSON.
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

  /// Best-effort format guess from the info string, same heuristic as
  /// the app (`pdf` / `cbr` / `cbz`, default `epub`).
  String get format {
    final infoLower = (info ?? '').toLowerCase();
    if (infoLower.contains('pdf')) return 'pdf';
    if (infoLower.contains('cbr')) return 'cbr';
    if (infoLower.contains('cbz')) return 'cbz';
    return 'epub';
  }

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
  const CliAttempt(this.mirror, this.error);

  Map<String, dynamic> toJson() => {'mirror': mirror, 'error': error};
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

/// Pure-Dart Anna's Archive client for the AI CLI.
///
/// Mirrors the request flow of `lib/services/annas_archieve.dart`
/// (browser-like headers, challenge detection, mirror fallback loop,
/// the search/detail HTML parsers) without importing it: the app-side
/// service pulls in Flutter plugins a `dart` CLI cannot load. Keep the
/// behaviour in sync with the app service when it changes.
class CliAnnasArchive {
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

  /// Hosts the app's download loop refuses; mirror the list so the CLI
  /// does not waste attempts on them either.
  static const List<String> deadHosts = ['annas-archive.org', '1lib.sk'];

  // ------------------------------------------------------------------
  // Challenge / page-identity detection (same signals as the app).
  // ------------------------------------------------------------------

  bool isChallengeResponse(Response response) {
    if (response.headers.value('cf-mitigated')?.toLowerCase() == 'challenge') {
      return true;
    }

    final status = response.statusCode ?? 0;
    final body = response.data?.toString().toLowerCase() ?? '';
    if (body.isEmpty) return false;

    final title = RegExp(r'<title[^>]*>([^<]*)</title>')
            .firstMatch(body)
            ?.group(1)
            ?.trim() ??
        '';
    const challengeTitles = [
      'just a moment',
      'ddos-guard',
      'checking your browser',
      'attention required',
    ];
    if (challengeTitles.any(title.startsWith)) return true;

    const hardMarkers = [
      'cf-browser-verification',
      'cf-challenge-running',
      '/cdn-cgi/challenge-platform/',
      'check.ddos-guard.net',
      'data-ddg-origin',
      '__ddg',
    ];
    for (final marker in hardMarkers) {
      if (body.contains(marker)) return true;
    }

    if (status == 403 || status == 503) {
      const softMarkers = [
        'checking your browser',
        'enable javascript and cookies',
        'needs to review the security of your connection',
        'verifying you are human',
        'browser check',
        'security check',
      ];
      for (final marker in softMarkers) {
        if (body.contains(marker)) return true;
      }
    }
    return false;
  }

  /// True when the page is an Anna's Archive document rather than an
  /// unrelated site sharing the host.
  bool isAnnasArchivePage(String html) {
    final title = RegExp(r'<title[^>]*>([^<]*)</title>', caseSensitive: false)
            .firstMatch(html)
            ?.group(1)
            ?.toLowerCase() ??
        '';
    return title.contains('anna') && title.contains('archive');
  }

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
  /// failure recorded. Throws [CliBlockException] when the surviving
  /// response was a challenge, [CliNetworkException] otherwise.
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
          attempts.add(CliAttempt(baseUrl, _shortError(e)));
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
    throw CliNetworkException(
      'All mirrors failed: ${_shortError(lastError)}',
      lastHost: lastHost,
      attempts: attempts,
    );
  }

  static String _shortError(Object? error) {
    final text = error.toString();
    return text.length > 120 ? text.substring(0, 120) : text;
  }

  /// Fetches [path] (e.g. `/search?q=...`) through the mirror loop and
  /// returns the body text. Throws the CLI exceptions above.
  Future<String> fetchPage(String path) async {
    return requestWithMirrorFallback<String>((baseUrl) async {
      final url = '$baseUrl$path';
      final response = await _makeRequest(url);

      if (isChallengeResponse(response)) {
        throw CliBlockException(
          'Access blocked by bot protection on $baseUrl. '
          'A browser challenge must be solved before this works.',
          url: url,
        );
      }
      _ensureResponseStatus(response, url);
      return response.data?.toString() ?? '';
    });
  }

  // ------------------------------------------------------------------
  // Search.
  // ------------------------------------------------------------------

  /// Builds the search URL. Mirrors the app's `urlEncoder`: filters ride
  /// the documented `/search` parameters; author/publisher become
  /// field-scoped terms inside `q`.
  static String buildSearchUrl({
    required String baseUrl,
    required String query,
    String content = '',
    String sort = '',
    String fileType = '',
    String language = '',
    String? yearFrom,
    String? yearTo,
    String author = '',
    String publisher = '',
    int page = 1,
  }) {
    var q = query;
    final fieldTerms = StringBuffer();
    if (author.trim().isNotEmpty) {
      fieldTerms.write(
          'author:%22${Uri.encodeQueryComponent(author.trim())}%22 ');
    }
    if (publisher.trim().isNotEmpty) {
      fieldTerms.write(
          'publisher:%22${Uri.encodeQueryComponent(publisher.trim())}%22 ');
    }
    q = (fieldTerms.toString() + q).replaceAll(' ', '+');

    final pageParam = page > 1 ? '&page=$page' : '';

    final hasFilters = content.isNotEmpty ||
        sort.isNotEmpty ||
        fileType.isNotEmpty ||
        language.isNotEmpty ||
        yearFrom != null ||
        yearTo != null;

    if (!hasFilters) {
      return '$baseUrl/search?q=$q$pageParam';
    }

    var url = '$baseUrl/search?index=&sort=$sort';
    if (language.isNotEmpty) url += '&lang=$language';
    url += '&display=';
    url += '&q=$q';
    if (content.isNotEmpty) url += '&content=$content';
    if (fileType.isNotEmpty) url += '&ext=$fileType';
    if (yearFrom != null && yearFrom.isNotEmpty) {
      url += '&year_from=${yearFrom.trim()}';
    }
    if (yearTo != null && yearTo.isNotEmpty) {
      url += '&year_end=${yearTo.trim()}';
    }
    return '$url$pageParam';
  }

  /// Searches Anna's Archive. Returns parsed results; an empty list
  /// means the search genuinely had no hits.
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
      final url = buildSearchUrl(
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
      if (!isAnnasArchivePage(response.data.toString())) {
        throw Exception(
            'Mirror $baseUrl did not serve an Anna\'s Archive page');
      }
      return parseSearchResults(
          response.data.toString(), fileType: fileType, baseUrl: baseUrl);
    });
  }

  /// Parses a search results page. Mirrors the app parser including its
  /// fallbacks (primary selector, then any `/md5/` link containers).
  List<CliBook> parseSearchResults(String html, {String fileType = '', String baseUrl = ''}) {
    var document = parse(html);
    var containers = document.querySelectorAll('div.flex.pt-3.pb-3.border-b');

    if (containers.isEmpty) {
      final md5Links = document.querySelectorAll('a[href*="/md5/"]');
      if (md5Links.isNotEmpty) {
        containers = md5Links
            .map((link) {
              var parent = link.parent;
              while (parent != null && parent.localName != 'div') {
                parent = parent.parent;
              }
              return parent;
            })
            .whereType<dom.Element>()
            .toList();
      }
    }

    final books = <CliBook>[];
    for (final container in containers) {
      final mainLink = container.querySelector('a.line-clamp-\\[3\\].js-vim-focus');
      final md5Link = container.querySelector('a[href*="/md5/"]');
      final linkElement = mainLink ?? md5Link;
      final thumbnailElement = container.querySelector('a[href*="/md5/"] img');

      if (linkElement == null || linkElement.attributes['href'] == null) {
        continue;
      }

      final href = linkElement.attributes['href']!;
      final title = cleanText(linkElement.text.trim());
      final md5 = md5FromLink(href);
      final thumbnail = thumbnailElement?.attributes['src'];

      // Author and publisher are the two `/search?q=` links after the
      // title link, in document order.
      dom.Element? authorElement = linkElement.nextElementSibling;
      dom.Element? publisherElement = authorElement?.nextElementSibling;
      if (authorElement?.attributes['href']?.startsWith('/search?q=') != true) {
        authorElement = null;
      }
      if (publisherElement?.attributes['href']?.startsWith('/search?q=') != true) {
        publisherElement = null;
      }

      String? authorRaw = authorElement?.text.trim();
      final String? author = authorRaw == null
          ? null
          : (authorRaw.contains('icon-')
              ? cleanText(authorRaw.split(' ').skip(1).join(' ').trim())
              : cleanText(authorRaw));
      final String? publisherRaw = publisherElement?.text.trim();
      final String? publisher =
          publisherRaw != null ? cleanText(publisherRaw) : null;

      final infoElement = container.querySelector('div.text-gray-800');
      // Script/style content stripped: Anna's pages embed click-handler
      // JS inside the info boxes and a JSON field must stay readable.
      final info = infoElement == null ? null : _visibleText(infoElement);

      final matchesType = fileType.isEmpty ||
          info?.toLowerCase().contains(fileType.toLowerCase()) == true;
      if (!matchesType) continue;

      final link = href.startsWith('http') ? href : '$baseUrl$href';
      books.add(CliBook(
        title: title,
        author: author?.isEmpty == true ? 'unknown' : author,
        thumbnail: thumbnail,
        link: link,
        md5: md5,
        publisher: publisher?.isEmpty == true ? 'unknown' : publisher,
        info: info,
      ));
    }
    return books;
  }

  // ------------------------------------------------------------------
  // Detail page.
  // ------------------------------------------------------------------

  /// Fetches and parses the `/md5/<md5>` page for one book.
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
      final details = parseBookInfo(response.data.toString(),
          url: url, baseUrl: baseUrl);
      if (details == null) {
        throw CliNotFoundException(
            'No book details on $url. The md5 link may be outdated - '
            'search for the title instead.');
      }
      return details;
    });
  }

  /// Parses one `/md5/` detail page. Returns null when the page holds no
  /// book record (same contract as the app's `_bookInfoParser`).
  CliBookDetails? parseBookInfo(String html,
      {required String url, String baseUrl = ''}) {
    final document = parse(html);
    final main = document.querySelector('div.main-inner');
    if (main == null) return null;

    final titleElement = main.querySelector('div.font-semibold.text-2xl');
    if (titleElement == null) return null;

    String? slowDownload;
    final slowLinks =
        main.querySelectorAll('ul.list-inside a[href*="/slow_download/"]');
    if (slowLinks.isNotEmpty && slowLinks.first.attributes['href'] != null) {
      final href = slowLinks.first.attributes['href']!;
      slowDownload = href.startsWith('http') ? href : '$baseUrl$href';
    }

    final authorElement = main.querySelector('a[href^="/search?q="].text-base');
    dom.Element? publisherElement = authorElement?.nextElementSibling;
    if (publisherElement?.localName != 'a' ||
        publisherElement?.attributes['href']?.startsWith('/search?q=') != true) {
      publisherElement = null;
    }

    final thumbnailElement = main.querySelector('div[id^="list_cover_"] img');
    final infoElement = main.querySelector('div.text-gray-800');

    dom.Element? descriptionElement;
    final descriptionLabel = main.querySelector(
        'div.js-md5-top-box-description div.text-xs.text-gray-500.uppercase');
    if (descriptionLabel?.text.trim().toLowerCase() == 'description') {
      descriptionElement = descriptionLabel?.nextElementSibling;
    }

    final title = cleanText(titleElement.text.trim().split('<span')[0].trim());
    final author = cleanText(authorElement?.text.trim() ?? 'unknown');
    final publisher = cleanText(publisherElement?.text.trim() ?? 'unknown');
    final info = _visibleText(infoElement);
    final description = _visibleText(descriptionElement);

    return CliBookDetails(
      title: title,
      author: author,
      thumbnail: thumbnailElement?.attributes['src'],
      publisher: publisher,
      info: info,
      link: url,
      md5: md5FromLink(url),
      description: description,
      slowDownloadUrl: slowDownload,
    );
  }

  // ------------------------------------------------------------------
  // Download.
  // ------------------------------------------------------------------

  /// Resolves the direct download link behind a book's slow_download
  /// page. Mirrors what the app's MirrorFetcherService extracts in its
  /// webview: the first link inside the bold paragraph.
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

    final link = extractSlowDownloadLink(response.data.toString(),
        pageUrl: slowDownloadUrl);
    if (link == null) {
      throw CliNotFoundException(
          'No download link on the slow_download page (link expired or '
          'page changed). Re-fetch the book info and retry.');
    }
    return link;
  }

  /// Extracts the direct link from slow_download page HTML, or null.
  /// Static so tests pin the selector contract without a network call.
  static String? extractSlowDownloadLink(String html,
      {String pageUrl = ''}) {
    final document = parse(html);
    final paragraph =
        document.querySelector('p[class="mb-4 text-xl font-bold"]');
    final anchor = paragraph?.querySelector('a');
    final href = anchor?.attributes['href'];
    if (href == null || href.isEmpty) return null;
    if (href.startsWith('http') || pageUrl.isEmpty) return href;
    return resolveRelative(href, pageUrl);
  }

  /// Streams a file to [savePath] with resume support, mirroring the
  /// app's `_downloadFileWithResume` (Range on partial file, 416 means
  /// already complete, a 200 after a Range resets the file). Reports
  /// progress through [onProgress]. Returns the final byte count.
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

    Response<ResponseBody> response;
    try {
      response = await downloadDio.get<ResponseBody>(url, options: options);
    } on DioException catch (e) {
      if (e.response?.statusCode == 416) {
        return received; // Range past EOF: the file is already complete.
      }
      rethrow;
    }

    final status = response.statusCode ?? 0;
    if (status < 200 || status >= 300) {
      throw CliNetworkException('Download failed with HTTP $status for $url');
    }

    int? contentLength;
    final contentLengthHeader = response.headers.value('content-length');
    if (contentLengthHeader != null) {
      contentLength = int.parse(contentLengthHeader);
    }
    int? total = received + (contentLength ?? 0);

    // Server ignored the Range: start over.
    if (received > 0 && status == 200) {
      received = 0;
      total = contentLength;
      await file.writeAsBytes([]);
    }

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
    return await dio.get(
      url,
      options: Options(
        headers: {...defaultHeaders},
        responseType: ResponseType.plain,
        validateStatus: (_) => true,
      ),
    ).timeout(requestTimeout);
  }

  /// Normalizes an md5 or any book URL to a `/md5/<md5>` path on
  /// [baseUrl].
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

  static String md5FromLink(String urlOrPath) {
    final uri = Uri.parse(urlOrPath);
    final segments = uri.pathSegments;
    final md5Index = segments.indexOf('md5');
    if (md5Index >= 0 && md5Index + 1 < segments.length) {
      return segments[md5Index + 1];
    }
    return segments.isNotEmpty ? segments.last : '';
  }

  static String resolveRelative(String href, String pageUrl) {
    if (href.startsWith('http')) return href;
    final page = Uri.parse(pageUrl);
    return page.resolve(href).toString();
  }

  /// Removes emojis, icons and control noise - the app's `cleanText`.
  static String cleanText(String text) {
    return text
        .replaceAll(RegExp(r'[\u{1F300}-\u{1F9FF}]', unicode: true), '')
        .replaceAll(RegExp(r'[\u{2600}-\u{26FF}]', unicode: true), '')
        .replaceAll(RegExp(r'[\u{2700}-\u{27BF}]', unicode: true), '')
        .replaceAll(RegExp(r'[\u{1F600}-\u{1F64F}]', unicode: true), '')
        .replaceAll(RegExp(r'[\u{1F680}-\u{1F6FF}]', unicode: true), '')
        .replaceAll('🔍', '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  /// Skips script/style content, like a browser would render it.
  static String _visibleText(dom.Element? element) {
    if (element == null) return '';
    final clone = element.clone(true);
    for (final node in clone.querySelectorAll('script, style')) {
      node.remove();
    }
    return clone.text.trim();
  }

  /// Orders download mirrors the way the app's `_reorderMirrors` does:
  /// drop dead hosts, plain hosts before IPFS gateways.
  static List<String> reorderMirrors(List<String> input) {
    final https = <String>[];
    final ipfs = <String>[];
    for (final element in input) {
      if (deadHosts.any(element.contains)) continue;
      if (element.contains('ipfs')) {
        ipfs.add(element);
      } else {
        https.add(element);
      }
    }
    return [...https, ...ipfs];
  }

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

/// Turns a raw failure from the download path into the CLI's
/// structured network error.
CliNetworkException cliNetworkErrorFrom(Object error, {String? lastHost}) {
  var text = error.toString();
  if (text.length > 200) text = text.substring(0, 200);
  return CliNetworkException('Network failure: $text', lastHost: lastHost);
}
