import 'package:openlib/core/book_language.dart';
// Dart imports:
import 'dart:async';

// Flutter imports:
import 'package:flutter/foundation.dart';

// Package imports:
import 'package:dio/dio.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

// Project imports:
import 'package:openlib/services/annas_archieve.dart';
import 'package:openlib/services/challenge_html_cache.dart';
import 'package:openlib/services/database.dart';
import 'package:openlib/services/diamwall_solver.dart';
import 'package:openlib/services/instance_manager.dart';
import 'package:openlib/services/logger.dart';
import 'package:openlib/services/webview_challenge_solver.dart';

/// One searchable catalog the app can query.
enum SearchProviderId { annasArchive, libgen, zlibrary, welib }

/// A source of [BookData] results. Implementations own their fetching,
/// parsing and error handling - the manager merges whatever comes back.
abstract class SearchProvider {
  /// Stable id for persistence and settings toggles.
  SearchProviderId get id;

  /// Human name shown in settings.
  String get displayName;

  /// Runs a search. Must return [] when nothing matches; throws when the
  /// provider is unreachable. A throw is contained by the manager.
  Future<List<BookData>> search(SearchQuery query);
}

/// The filters the results page collects, in provider-neutral form.
///
/// [author], [publisher] and [year] carry field-specific values from
/// the advanced search panel; providers translate them into whatever
/// their backend supports.
@immutable
class SearchQuery {
  final String text;
  final String content;
  final String sort;
  final String fileType;
  final String language;
  final String year;
  final String author;
  final String publisher;
  final bool filtersEnabled;
  final int page;

  /// Null keeps the automatic fallback chain; a selection searches only that catalog.
  final SearchProviderId? source;

  const SearchQuery({
    required this.text,
    this.content = '',
    this.sort = '',
    this.fileType = '',
    this.language = '',
    this.year = '',
    this.author = '',
    this.publisher = '',
    this.filtersEnabled = false,
    this.page = 1,
    this.source,
  });

  bool get isEmpty =>
      text.trim().isEmpty && author.trim().isEmpty && publisher.trim().isEmpty;
}

/// The plain-HTML header most library mirrors expect from a browser.
const _browserHeaders = {
  'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/125.0 Safari/537.36',
};

/// Anna's Archive behind the provider interface: the existing
/// AnnasArchieve service with its challenge handling, unchanged.
class AnnasArchiveProvider implements SearchProvider {
  AnnasArchiveProvider({AnnasArchieve? api}) : _api = api ?? AnnasArchieve();

  final AnnasArchieve _api;

  @override
  SearchProviderId get id => SearchProviderId.annasArchive;

  @override
  String get displayName => "Anna's Archive";

  @override
  Future<List<BookData>> search(SearchQuery query) {
    return _api.searchBooks(
      searchQuery: query.text,
      content: query.content,
      sort: query.sort,
      fileType: query.fileType,
      language: query.language,
      year: query.year,
      author: query.author,
      publisher: query.publisher,
      enableFilters: query.filtersEnabled,
      page: query.page,
    );
  }
}

/// Library Genesis (libgen.li family): an HTML table of results, one
/// row per book. Mirror order comes from the instance manager so the
/// user's enabled/prioritized mirrors in settings are respected.
class LibgenProvider implements SearchProvider {
  LibgenProvider({Dio? dio, List<String>? mirrors})
      : _dio = dio ??
            createDioWithLogging(
                options: BaseOptions(
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 30),
              headers: _browserHeaders,
            )),
        _mirrors = mirrors;

  final Dio _dio;
  final List<String>? _mirrors;
  final AppLogger _logger = AppLogger();

  @override
  SearchProviderId get id => SearchProviderId.libgen;

  @override
  String get displayName => 'Library Genesis';

  /// Parses a libgen results page. Public so tests can feed a captured
  /// page without network. Handles both table layouts in the wild:
  /// the libgen.li/vg "tablelibgen" table and the older table.c.
  List<BookData> parseResults(String html, String baseUrl) {
    final document = html_parser.parse(html);

    // The libgen.li/vg family marks its results table with an id. The
    // older libgen layout uses a table.c; rows live in its tbody.
    final liRows = document.querySelectorAll('#tablelibgen tr');
    if (liRows.any((row) => row.querySelectorAll('td').length >= 9)) {
      return liRows
          .map((row) => _liRowToBook(row, baseUrl))
          .whereType<BookData>()
          .toList();
    }

    final legacyRows = document.querySelectorAll('table.c tbody tr');
    return legacyRows
        .map((row) => _legacyRowToBook(row, baseUrl))
        .whereType<BookData>()
        .toList();
  }

  BookData? _liRowToBook(dom.Element row, String baseUrl) {
    final cells = row.querySelectorAll('td');
    // libgen.li-family layout: [title(+links), author, series,
    // year, language, pages, size, extension, mirrors].
    if (cells.length < 9) return null;

    final titleCell = cells[0];
    // The first link points at series.php - the work's own title. The
    // edition links below it describe specific editions and DOI lines;
    // they are longer and would drown the real title out.
    final seriesLink =
        titleCell.querySelector('a[href*="series.php"], a[href*="index.php?"]');
    final title = (seriesLink ?? titleCell.querySelector('a'))?.text.trim() ??
        titleCell.text.trim();
    if (title.isEmpty) return null;

    // An md5 download link from the mirrors cell, if present. Fall
    // back to the edition link's id - unique per book either way.
    final md5Link = cells[8]
        .querySelectorAll('a[href*="md5="]')
        .map((a) => a.attributes['href'] ?? '')
        .whereType<String>()
        .toList();
    final md5 = _md5FromHref(md5Link) ??
        cells[0]
            .querySelectorAll('a[href*="id="]')
            .map((a) => RegExp(r'id=(\d+)')
                .firstMatch(a.attributes['href'] ?? '')
                ?.group(1))
            .whereType<String>()
            .firstOrNull;

    String cell(int i) => cells.length > i ? cells[i].text.trim() : '';

    final info = [
      cell(4), // language
      if (cell(7).isNotEmpty) cell(7).toUpperCase(), // extension
      cell(6).replaceAll(RegExp(r'\s+'), ' '), // size
      cell(3), // year
    ].where((s) => s.isNotEmpty).join(', ');

    final md5Value = md5;
    final fallbackLink = titleCell.querySelector('a');
    final fallbackHref = fallbackLink?.attributes['href'] ?? '';
    return BookData(
      title: title,
      author: cell(1).isEmpty ? 'Unknown' : cell(1),
      thumbnail: null,
      link: md5Value != null
          ? '$baseUrl/ads.php?md5=$md5Value'
          : (fallbackHref.startsWith('http')
              ? fallbackHref
              : '$baseUrl$fallbackHref'),
      md5: md5Value ?? title,
      publisher: cell(2).isEmpty ? null : cell(2),
      info: info.isEmpty ? null : info,
    );
  }

  BookData? _legacyRowToBook(dom.Element row, String baseUrl) {
    final cells = row.querySelectorAll('td');
    // Older libgen layout: [id, author, title(+link), publisher, year,
    // pages, language, size, extension, ...mirror links].
    if (cells.length < 5) return null;

    final titleCell = cells[2];
    final titleLink = titleCell.querySelector('a');
    final href = titleLink?.attributes['href'];
    final title = (titleLink?.text ?? titleCell.text).trim();
    if (title.isEmpty || href == null) return null;

    String cell(int i) => cells.length > i ? cells[i].text.trim() : '';

    final info = [
      cell(6), // language
      if (cell(8).isNotEmpty) cell(8).toUpperCase(), // extension
      cell(7), // size
      cell(4), // year
    ].where((s) => s.isNotEmpty).join(', ');

    return BookData(
      title: title,
      author: cell(1).isEmpty ? 'Unknown' : cell(1),
      thumbnail: null,
      link: href.startsWith('http') ? href : '$baseUrl$href',
      md5: _md5FromHref([href]) ?? title,
      publisher: cell(3).isEmpty ? null : cell(3),
      info: info.isEmpty ? null : info,
    );
  }

  String? _md5FromHref(List<String> hrefs) {
    for (final href in hrefs) {
      final match = RegExp(r'[?&]md5=([0-9a-fA-F]{32})').firstMatch(href);
      if (match != null) return match.group(1);
    }
    return null;
  }

  @override
  Future<List<BookData>> search(SearchQuery query) async {
    // Field-specific search: libgen.li/vg accept columns[]= codes
    // restricting which fields 'req' is matched against - a=author,
    // p=publisher, t=title. When the user gave an author or publisher,
    // fold both into req and restrict matching to those columns so
    // 'Asimov' finds books BY Asimov, not books mentioning him.
    final author = query.author.trim();
    final publisher = query.publisher.trim();
    final useColumns =
        query.filtersEnabled && (author.isNotEmpty || publisher.isNotEmpty);
    final req = useColumns
        ? [
            if (author.isNotEmpty) author,
            if (publisher.isNotEmpty) publisher,
            if (query.text.trim().isNotEmpty) query.text.trim(),
          ].join(' ')
        : query.text;

    final params = StringBuffer('req=${Uri.encodeQueryComponent(req)}');
    if (useColumns) {
      if (author.isNotEmpty) params.write('&columns[]=a');
      if (publisher.isNotEmpty) params.write('&columns[]=p');
    }
    if (query.filtersEnabled) {
      if (query.fileType.isNotEmpty) {
        params.write('&extension=${Uri.encodeQueryComponent(query.fileType)}');
      }
      if (query.language.isNotEmpty) {
        params.write('&language=${Uri.encodeQueryComponent(query.language)}');
      }
      if (query.year.isNotEmpty) {
        params.write('&year=${Uri.encodeQueryComponent(query.year)}');
      }
    }
    if (query.page > 1) {
      params.write('&page=${query.page}');
    }

    final mirrors =
        _mirrors ?? await InstanceManager().enabledUrls(MirrorService.libgen);

    if (mirrors.isEmpty) {
      // Every libgen mirror SLUM knows is DOWN (or switched off by the
      // user). The contract is to never touch a down host, so this ends
      // here instead of throwing against a dead address.
      _logger.warning('No attemptable libgen mirror; not searching',
          tag: 'LibgenProvider');
      return const [];
    }

    _logger.info('Searching Library Genesis', tag: 'LibgenProvider', metadata: {
      'req': req,
      'page': query.page,
      'mirrors': mirrors.length,
    });

    Object? lastError;
    for (final mirror in mirrors) {
      try {
        final response = await _dio.get('$mirror/index.php?$params&res=100');
        if (response.statusCode != 200) {
          _logger.warning('Libgen mirror answered with a non-200',
              tag: 'LibgenProvider',
              metadata: {'mirror': mirror, 'status': response.statusCode});
          continue;
        }
        final books = parseResults(response.data.toString(), mirror);
        _logger.info('Libgen search returned ${books.length} books',
            tag: 'LibgenProvider', metadata: {'mirror': mirror});
        return books;
      } catch (e) {
        lastError = e;
        _logger.warning('Libgen mirror failed, trying next',
            tag: 'LibgenProvider', error: e, metadata: {'mirror': mirror});
      }
    }
    _logger.error('All libgen mirrors failed',
        tag: 'LibgenProvider', error: lastError);
    throw Exception('Library Genesis unreachable: $lastError');
  }
}

/// Outcome of asking a Z-Library mirror for a book's file URL.
///
/// Exactly one of [url] / [refusal] is meaningful: a resolved signed CDN
/// URL, or a reason the user can act on.
@immutable
class ZlibraryDownload {
  final String? url;

  /// Human-readable reason the mirror withheld the file. Null when the
  /// mirror simply had no working link.
  final String? refusal;

  const ZlibraryDownload({this.url, this.refusal});

  bool get ok => url != null;
}

/// Z-Library: mirrors sit behind a DiamWall proof-of-work gate, so the
/// provider solves the 503 challenge headlessly (no webview) before
/// parsing results. It still yields an empty result when every mirror
/// fails instead of failing the whole search.
class ZlibraryProvider implements SearchProvider {
  ZlibraryProvider({Dio? dio, List<String>? mirrors})
      : _dio = dio ??
            createDioWithLogging(
                options: BaseOptions(
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 30),
              headers: _browserHeaders,
            )),
        _mirrors = mirrors,
        _solver = DiamWallSolver();

  final AppLogger _logger = AppLogger();

  /// The Z-Library mirrors to try, best first, from open-slum.org.
  ///
  /// Nothing here is hardcoded: the instance manager reads SLUM's
  /// zlibrary page and orders deliberately - unprotected before
  /// DiamWall before the browser-only gates - and drops mirrors SLUM
  /// reports DOWN. When no webview solver exists on this platform the
  /// browser-only gates are filtered out entirely, because a 503 from
  /// them can never be passed headlessly.
  Future<List<String>> _resolveMirrors() async {
    return InstanceManager().enabledUrls(
      MirrorService.zlibrary,
      headlessOnly: !WebviewChallengeSolver.isSupported,
    );
  }

  final Dio _dio;
  final List<String>? _mirrors;
  final DiamWallSolver _solver;

  @override
  SearchProviderId get id => SearchProviderId.zlibrary;

  @override
  String get displayName => 'Z-Library';

  @override
  Future<List<BookData>> search(SearchQuery query) async {
    final mirrors = _mirrors ?? await _resolveMirrors();

    _logger.info('Searching Z-Library', tag: 'ZlibraryProvider', metadata: {
      'query': query.text,
      'page': query.page,
      'mirrors': mirrors.length,
    });

    // Names and parameter keys come from Z-Library's search form.
    final language = bookLanguageName(query.language)?.toLowerCase();
    final parameters = <String, dynamic>{
      if (query.page > 1) 'page': query.page,
      if (query.filtersEnabled && language != null) 'languages[]': language,
      if (query.filtersEnabled && query.fileType.isNotEmpty)
        'extensions[]': query.fileType.toUpperCase(),
    };

    for (final mirror in mirrors) {
      try {
        var response = await _followDiamWallRedirect(
          '$mirror/s/${Uri.encodeComponent(query.text)}',
          queryParameters: parameters,
        );
        if (_solver.looksLikeBlock(
            response.statusCode ?? 0, response.data.toString())) {
          _logger.warning('Z-Library blocked this network; trying next mirror',
              tag: 'ZlibraryProvider',
              metadata: {'mirror': mirror, 'status': response.statusCode});
          continue;
        }
        if (_solver.looksLikeChallenge(
            response.statusCode ?? 0, response.data.toString())) {
          // DiamWall 503: solve the embedded SHA1 proof-of-work,
          // attach the resulting cookies and retry once.
          final cookies = await _solver.solve(response.data.toString());
          if (cookies != null) {
            _logger.debug('DiamWall solved, retrying with cookies',
                tag: 'ZlibraryProvider', metadata: {'mirror': mirror});
            final cookieHeader =
                cookies.entries.map((e) => '${e.key}=${e.value}').join('; ');
            try {
              response = await _followDiamWallRedirect(
                '$mirror/s/${Uri.encodeComponent(query.text)}',
                queryParameters: parameters,
                headers: {'Cookie': cookieHeader},
              );
            } catch (e) {
              _logger.warning('Request failed after solving the challenge',
                  tag: 'ZlibraryProvider',
                  error: e,
                  metadata: {'mirror': mirror});
              continue; // Next mirror.
            }
          } else {
            _logger.warning('Unsolvable DiamWall challenge, skipping mirror',
                tag: 'ZlibraryProvider', metadata: {'mirror': mirror});
            continue; // Unsolvable challenge; next mirror.
          }
        }
        if (response.statusCode != 200) {
          _logger.warning('Z-Library mirror answered with a non-200',
              tag: 'ZlibraryProvider',
              metadata: {'mirror': mirror, 'status': response.statusCode});
          continue;
        }
        final books =
            parseResults(response.data.toString(), mirror).where((book) {
          if (!query.filtersEnabled) return true;
          final matchesLanguage = language == null ||
              bookLanguageName(book.info)?.toLowerCase() == language;
          final matchesType = query.fileType.isEmpty ||
              (book.info ?? '')
                  .toLowerCase()
                  .contains(query.fileType.toLowerCase());
          return matchesLanguage && matchesType;
        }).toList();
        if (books.isNotEmpty) {
          _logger.info('Z-Library search returned ${books.length} books',
              tag: 'ZlibraryProvider', metadata: {'mirror': mirror});
          return books;
        }
      } catch (e) {
        // Next mirror; Z-Library mirrors are unstable by nature.
        _logger.warning('Z-Library mirror failed, trying next',
            tag: 'ZlibraryProvider', error: e, metadata: {'mirror': mirror});
      }
    }
    _logger.warning('All Z-Library mirrors failed for this search',
        tag: 'ZlibraryProvider');
    return const [];
  }

  /// Parses a Z-Library results page. Public so tests can feed a
  /// captured page without network. Live markup uses custom
  /// `z-bookcard` elements - there are no `<a href="/book/">` anchors -
  /// with metadata in attributes (`extension`, `filesize`, `year`,
  /// `language`, `publisher`, `rating`) and in `slot=` divs (`title`,
  /// `author`).
  List<BookData> parseResults(String html, String baseUrl) {
    final document = html_parser.parse(html);
    final books = <BookData>[];
    for (final card in document.querySelectorAll('z-bookcard')) {
      // No-results pages contain a realistic but hidden decoy card.
      // Respect the page's visibility instead of treating it as a match.
      dom.Element? ancestor = card;
      var hidden = false;
      while (ancestor != null) {
        if (ancestor.attributes.containsKey('hidden') ||
            ancestor.attributes['aria-hidden']?.trim().toLowerCase() ==
                'true') {
          hidden = true;
          break;
        }
        ancestor = ancestor.parent;
      }
      if (hidden) continue;
      final href = card.attributes['href'];
      final title = card.querySelector('div[slot="title"]')?.text.trim() ?? '';
      if (href == null || href.isEmpty || title.isEmpty) continue;

      final author =
          card.querySelector('div[slot="author"]')?.text.trim() ?? '';
      final cover = card.querySelector('img')?.attributes['data-src'] ??
          card.querySelector('img')?.attributes['src'];

      final info = [
        card.attributes['language'],
        card.attributes['extension']?.toUpperCase(),
        card.attributes['filesize'],
        card.attributes['year'],
      ].whereType<String>().where((s) => s.isNotEmpty).join(', ');

      books.add(BookData(
        title: title,
        author: author.isEmpty ? 'Unknown' : author,
        thumbnail: cover,
        link: href.startsWith('http') ? href : '$baseUrl$href',
        md5: _bookIdFromHref(href) ?? href,
        publisher: card.attributes['publisher'],
        info: info.isEmpty ? null : info,
      ));
    }
    return books;
  }

  /// Z-Library has no md5 on its search pages; the book href's id
  /// segment (`/book/<id>/slug.html`) is the stable unique id instead.
  String? _bookIdFromHref(String href) =>
      RegExp(r'/book/([0-9a-zA-Z]+)').firstMatch(href)?.group(1);

  /// Fetches a book detail page (`/book/<id>/slug.html`) and returns it
  /// as [BookInfoData], with [BookInfoData.mirror] pointing at the
  /// resolved CDN download URL and `isFastDownload` true - the resolved
  /// link serves the file directly, exactly like libgen's get.php.
  /// Null when every mirror fails or the page cannot be parsed.
  Future<BookInfoData?> bookInfo(
    String url, {
    Duration timeout = const Duration(seconds: 20),
  }) async {
    final cancellation = CancelToken();
    try {
      return await _bookInfo(url, cancellation).timeout(timeout, onTimeout: () {
        _logger.warning('Z-Library book page timed out',
            tag: 'ZlibraryProvider', metadata: {'url': url});
        return null;
      });
    } finally {
      cancellation.cancel('Book detail request finished');
    }
  }

  Future<BookInfoData?> _bookInfo(String url, CancelToken cancellation) async {
    final available = _mirrors ?? await _resolveMirrors();
    final origin = Uri.parse(url).origin;
    // Start with the mirror that actually returned this result. Only use
    // configured mirrors, retaining the user's disabled-host choices.
    final mirrors = [
      ...available.where((mirror) => Uri.parse(mirror).origin == origin),
      ...available.where((mirror) => Uri.parse(mirror).origin != origin),
    ];
    final path = Uri.parse(url).path;

    for (final mirror in mirrors) {
      if (cancellation.isCancelled) return null;
      try {
        var response = await _followDiamWallRedirect('$mirror$path',
            cancelToken: cancellation);
        response = await _passDiamWall(mirror, response, '$mirror$path',
            cancelToken: cancellation);
        if (response.statusCode != 200) continue;
        final pageUrl = '$mirror$path';
        final data = parseBookPage(response.data.toString(), mirror, pageUrl);
        if (data != null) return data;
      } catch (error) {
        if (cancellation.isCancelled) return null;
        _logger.warning('Z-Library book page failed',
            tag: 'ZlibraryProvider',
            error: error,
            metadata: {'mirror': mirror});
      }
    }
    return null;
  }

  /// GETs [url] and follows DiamWall's newer 307 self-redirect by
  /// replaying its `__diamwall` cookie. Without this Dio sees a redirect
  /// loop and the mirror is written off, even though a browser would
  /// simply retry with the cookie. [headers] (e.g. a solved PoW cookie)
  /// are kept on the replayed request and merged with the gate's cookie.
  Future<Response> _followDiamWallRedirect(
    String url, {
    Map<String, dynamic>? queryParameters,
    CancelToken? cancelToken,
    Map<String, String>? headers,
  }) async {
    final noRedirect = Options(
      validateStatus: (_) => true,
      followRedirects: false,
      maxRedirects: 0,
      headers: headers,
    );
    var response = await _dio.get(
      url,
      queryParameters: queryParameters,
      cancelToken: cancelToken,
      options: noRedirect,
    );
    for (var hop = 0; hop < 4; hop++) {
      final status = response.statusCode ?? 0;
      if (status < 300 || status >= 400) break;
      final location = response.headers.value('location');
      if (location == null) break;
      final from = Uri.tryParse(url);
      // A Location may be relative; resolve it before comparing origins.
      final to = from?.resolve(location);
      if (from == null || to == null || from.origin != to.origin) break;
      final cookie = DiamWallSolver.cookieHeaderFrom(response);
      final mergedHeaders = <String, String>{
        ...?headers,
        if (cookie != null)
          'Cookie': [headers?['Cookie'], cookie]
              .whereType<String>()
              .join('; '),
      };
      response = await _dio.get(
        to.toString(),
        // The 307 target usually drops the query; keep the filters when
        // it does, and let the target's own query win when it has one.
        queryParameters: to.query.isEmpty ? queryParameters : null,
        cancelToken: cancelToken,
        options: noRedirect.copyWith(headers: mergedHeaders),
      );
    }
    return response;
  }

  /// GETs [url], solving a DiamWall 503 (once) and a second 503 on the
  /// download hop if present. Returns the first response that is not a
  /// challenge. A non-challenge response is returned as-is.
  Future<Response> _passDiamWall(String mirror, Response first, String url,
      {CancelToken? cancelToken}) async {
    var response = first;

    if (!_solver.looksLikeChallenge(
        response.statusCode ?? 0, response.data.toString())) {
      return response;
    }
    final cookies = await _solver.solve(response.data.toString());
    if (cookies == null) return response;
    final cookieHeader =
        cookies.entries.map((e) => '${e.key}=${e.value}').join('; ');

    response = await _followDiamWallRedirect(url,
        cancelToken: cancelToken, headers: {'Cookie': cookieHeader});
    // A second challenge can appear right at the download hop; solve
    // it too before giving up on this mirror.
    if (_solver.looksLikeChallenge(
        response.statusCode ?? 0, response.data.toString())) {
      final again = await _solver.solve(response.data.toString());
      if (again != null) {
        final header =
            again.entries.map((e) => '${e.key}=${e.value}').join('; ');
        response = await _followDiamWallRedirect(url,
            cancelToken: cancelToken, headers: {'Cookie': header});
      }
    }
    return response;
  }

  /// Convenience for the download button: re-fetches the book page
  /// (fresh /dl/ ids), then resolves the first id that answers with
  /// a real CDN redirect. One DiamWall solve for the page plus one
  /// per dead id - usually a single solve in total.
  ///
  /// Mirrors refuse for reasons the user can act on (the anonymous
  /// daily download limit, a login wall); [ZlibraryDownload.refusal]
  /// carries that reason instead of a bare null.
  Future<ZlibraryDownload> resolveBookDownload(String bookPageUrl) async {
    final links = await _allDownloadLinks(bookPageUrl);
    if (links.isEmpty) {
      return const ZlibraryDownload(
          refusal: 'No download link found on the book page. '
              'The book may have no files on this mirror.');
    }

    final acceptAnyStatus = Options(
      validateStatus: (_) => true,
      followRedirects: false,
      maxRedirects: 0,
    );

    String? refusal;
    for (final link in links) {
      final outcome = await _resolveOneDownloadUrl(link, acceptAnyStatus);
      if (outcome.url != null) return ZlibraryDownload(url: outcome.url);
      refusal ??= outcome.refusal;
    }
    // Only a reason the mirror itself gave is reported; when there is
    // none the caller's own generic message applies.
    return ZlibraryDownload(refusal: refusal);
  }

  /// Fetches a book page and returns every `/dl/<id>` link on it,
  /// visible (actions section) ones first. Empty when the page cannot
  /// be fetched or parsed on any mirror.
  Future<List<String>> _allDownloadLinks(String bookPageUrl) async {
    final mirrors = _mirrors ?? await _resolveMirrors();
    final path = Uri.parse(bookPageUrl).path;

    for (final mirror in mirrors) {
      try {
        var response = await _followDiamWallRedirect('$mirror$path');
        response = await _passDiamWall(mirror, response, '$mirror$path');
        if (response.statusCode != 200) {
          _logger.warning('Book page fetch got a non-200',
              tag: 'ZlibraryProvider',
              metadata: {'mirror': mirror, 'status': response.statusCode});
          continue;
        }

        final links = _extractDownloadLinks(response.data.toString());
        if (links.isNotEmpty) {
          return links
              .map((href) => href.startsWith('http') ? href : '$mirror$href')
              .toList();
        }
      } catch (e) {
        // Next mirror; Z-Library mirrors are unstable by nature.
        _logger.warning('Book page fetch failed, trying next mirror',
            tag: 'ZlibraryProvider', error: e, metadata: {'mirror': mirror});
      }
    }
    return const [];
  }

  /// Pulls every distinct /dl/ href out of a book page, visible ones
  /// first (hidden <template> links go last - they are often dead).
  List<String> _extractDownloadLinks(String html) {
    final document = html_parser.parse(html);
    final links = <String>[];
    for (final a in document.querySelectorAll('a[href^="/dl/"]')) {
      final href = a.attributes['href'];
      if (href == null || links.contains(href)) continue;
      final inTemplate = aAncestorHasClass(a, 'template');
      if (inTemplate) {
        links.add(href);
      } else {
        links.insert(0, href);
      }
    }
    return links;
  }

  /// True when [element] sits inside a <template> (z-lib hides its
  /// first download link there for bots).
  bool aAncestorHasClass(dom.Element element, String needle) {
    dom.Element? node = element;
    while (node != null) {
      if (node.localName == needle) return true;
      node = node.parent;
    }
    return false;
  }

  /// Resolves the `/dl/<id>` link on a book page to its final CDN URL
  /// (DiamWall once, then a 302 to a signed CDN link). The resolved
  /// URL expires, so it is only worth fetching right before a download.
  /// Some `/dl/` ids answer 204 forever; [alternates] (the other ids
  /// from the book page) are tried in order when the primary fails.
  Future<String?> resolveDownloadUrl(String dlUrl,
      {List<String> alternates = const []}) async {
    final acceptAnyStatus = Options(
      validateStatus: (_) => true,
      // Follow nothing: the 302 Location is the answer we want.
      followRedirects: false,
      maxRedirects: 0,
    );

    for (final candidate in [dlUrl, ...alternates]) {
      final outcome = await _resolveOneDownloadUrl(candidate, acceptAnyStatus);
      if (outcome.url != null) return outcome.url;
    }
    return null;
  }

  /// One `/dl/<id>` candidate: solve DiamWall if challenged, then read
  /// the 302 Location. 200 that is not an HTML page counts as resolved -
  /// the downloader follows redirects anyway. 204 and 404 mean this id
  /// is dead; the caller tries the next one.
  ///
  /// A 200 that IS an HTML page is the mirror talking to us: Z-Library
  /// answers with a "Downloading ..." page carrying a reason
  /// ("Daily limit reached ... more than 5 downloads from your IP",
  /// "Please sign in"). That reason is returned so the UI can tell the
  /// user something actionable instead of a bare failure.
  Future<({String? url, String? refusal})> _resolveOneDownloadUrl(
      String candidate, Options acceptAnyStatus) async {
    var response = await _dio.get(candidate, options: acceptAnyStatus);
    if (_solver.looksLikeChallenge(
        response.statusCode ?? 0, response.data.toString())) {
      final cookies = await _solver.solve(response.data.toString());
      if (cookies == null) return (url: null, refusal: null);
      final cookieHeader =
          cookies.entries.map((e) => '${e.key}=${e.value}').join('; ');
      response = await _dio.get(candidate,
          options: acceptAnyStatus.copyWith(headers: {'Cookie': cookieHeader}));
    }

    final status = response.statusCode ?? 0;
    if (status == 302 || status == 301) {
      final location = response.headers.value('location');
      if (location != null && location.startsWith('http')) {
        return (url: location, refusal: null);
      }
    }
    if (status == 200) {
      final body = response.data.toString();
      if (_solver.looksLikeChallenge(200, body)) {
        return (url: null, refusal: null);
      }
      if (!body.toLowerCase().contains('<html')) {
        // The CDN itself served the bytes.
        return (url: candidate, refusal: null);
      }
      return (url: null, refusal: _refusalFromPage(body));
    }
    return (url: null, refusal: null);
  }

  /// Reads the reason out of a Z-Library download page that withheld the
  /// file. Returns null when the page says nothing we recognize, so a
  /// caller never shows an invented message.
  String? _refusalFromPage(String html) {
    final text = html_parser
            .parse(html)
            .body
            ?.text
            .replaceAll(RegExp(r'\s+'), ' ')
            .trim()
            .toLowerCase() ??
        '';
    if (text.isEmpty) return null;

    if (text.contains('downloads from your ip') ||
        text.contains('daily limit reached')) {
      return 'Daily download limit reached for this network. '
          'Sign in to Z-Library in the app browser, or try again tomorrow.';
    }
    // Deliberately specific: every z-lib page carries a "Login" nav link,
    // so a bare 'login' match would mislabel any unrecognized page.
    if (text.contains('please sign in to your account') ||
        text.contains('registration to download')) {
      return 'Z-Library asks to sign in before serving this file.';
    }
    return null;
  }

  /// Parses a Z-Library book detail page. Public so tests can feed a
  /// captured page without network. Live markup: `h1[itemprop=name]`
  /// title, `.authors a` author, `bookProperty property_*` rows for
  /// year/publisher/language/file, and `/dl/<id>` anchors for the
  /// download. The file row reads like "EPUB, 430.04 MB".
  BookInfoData? parseBookPage(String html, String baseUrl, String pageUrl) {
    final document = html_parser.parse(html);

    final title =
        document.querySelector('h1[itemprop="name"]')?.text.trim() ?? '';
    if (title.isEmpty) return null;

    final author =
        document.querySelector('.authors a')?.text.trim() ?? 'Unknown';

    final cover =
        document.querySelector('img[src*="covers"]')?.attributes['src'] ??
            document.querySelector('img')?.attributes['src'];

    String? format;
    String? size;
    String? year;
    String? publisher;
    String? language;
    for (final row in document.querySelectorAll('.bookProperty')) {
      final label =
          row.querySelector('.property_label')?.text.trim().toLowerCase() ?? '';
      final value = row.querySelector('.property_value')?.text.trim() ?? '';
      if (label.startsWith('file:')) {
        final parts = value.split(',');
        format = parts.isNotEmpty ? parts[0].trim() : null;
        size = parts.length > 1 ? parts[1].trim() : null;
      } else if (label.startsWith('year:')) {
        year = value;
      } else if (label.startsWith('publisher:')) {
        publisher = value;
      } else if (label.startsWith('language:')) {
        language = value;
      }
    }

    // A book page carries several /dl/ ids and some answer 204
    // forever; the visible ones are the live ones, so prefer those.
    final dlHrefs = _extractDownloadLinks(html);
    final dlHref = dlHrefs.isEmpty ? null : dlHrefs.first;

    final info = [
      language,
      format,
      size,
      year,
    ].whereType<String>().where((s) => s.isNotEmpty).join(', ');

    final descriptionElement = document.querySelector('#bookDescriptionBox');
    final description = descriptionElement == null
        ? ''
        : html_parser
                .parseFragment(descriptionElement.innerHtml
                    .replaceAll(
                        RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
                    .replaceAll(
                        RegExp(r'</p\s*>', caseSensitive: false), '\n\n'))
                .text
                ?.trim() ??
            '';

    return BookInfoData(
      title: title,
      author: author,
      thumbnail: cover,
      publisher: publisher,
      info: info.isEmpty ? null : info,
      // The book page URL is stable across mirrors; keep the one we
      // actually loaded so re-opens do not loop through dead mirrors.
      link: pageUrl,
      md5: _bookIdFromHref(pageUrl) ?? title,
      format: format ?? '',
      description: description.isEmpty ? null : description,
      mirror: dlHref == null ? null : '$baseUrl$dlHref',
      isFastDownload: false,
    );
  }
}

/// Outcome of asking WeLib for a book's file URL.
///
/// Exactly one of [url] / [refusal] is meaningful: a resolved download
/// link, or a reason the user can act on.
@immutable
class WelibDownload {
  final String? url;

  /// Human-readable reason WeLib did not offer the file. Null when the
  /// page simply carried no link.
  final String? refusal;

  const WelibDownload({this.url, this.refusal});

  bool get ok => url != null;
}

/// True when [url] is a WeLib page, i.e. one [WelibProvider.resolveDownload]
/// understands.
///
/// A single predicate beside the provider, so the UI's routing and the
/// parser cannot drift apart; the host test is the same admission rule the
/// catalogue applies to the "other" page's welib mirrors.
bool isWelibUrl(String? url) {
  if (url == null || url.isEmpty) return false;
  return (Uri.tryParse(url)?.host ?? '').contains('welib');
}

/// WeLib (welib.org) - open-slum.org's "other" page.
///
/// welib.org gates `/search` behind Cloudflare. A search therefore only
/// succeeds when a webview solver is available (the same machinery
/// Anna's Archive uses); without one the provider reports no results
/// rather than pretending. Book detail (`/md5/<id>`) and the
/// public-server download page (`/slow_download/<id>/0/0`) need no
/// browser - but Cloudflare fingerprints a plain HTTP client on some
/// paths, so the solver path is kept as fallback there too.
class WelibProvider implements SearchProvider {
  WelibProvider({Dio? dio, List<String>? mirrors})
      : _dio = dio ??
            createDioWithLogging(
                options: BaseOptions(
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 30),
              headers: _browserHeaders,
            )),
        _mirrors = mirrors;

  final Dio _dio;
  final List<String>? _mirrors;
  final AppLogger _logger = AppLogger();

  @override
  SearchProviderId get id => SearchProviderId.welib;

  @override
  String get displayName => 'WeLib';

  /// Mirrors come from open-slum.org's "other" page; a down mirror is
  /// never attempted. With a webview solver the Cloudflare-gated search
  /// is solvable, so the mirror stays in the list.
  Future<List<String>> _resolveMirrors() =>
      InstanceManager().enabledUrls(MirrorService.welib);

  @override
  Future<List<BookData>> search(SearchQuery query) async {
    final mirrors = _mirrors ?? await _resolveMirrors();
    if (mirrors.isEmpty) {
      _logger.warning('No attemptable WeLib mirror; not searching',
          tag: 'WelibProvider');
      return const [];
    }

    for (final mirror in mirrors) {
      try {
        final html = await _fetchHtml('$mirror/search${_queryString(query)}');
        if (html == null) continue;
        final books = parseResults(html, mirror);
        if (books.isNotEmpty) return books;
      } catch (e) {
        _logger.warning('WeLib mirror failed, trying next',
            tag: 'WelibProvider', error: e, metadata: {'mirror': mirror});
      }
    }
    _logger.warning('All WeLib mirrors failed for this search',
        tag: 'WelibProvider');
    return const [];
  }

  /// GETs [url] and returns the body, clearing a Cloudflare challenge
  /// with the webview solver when one appears.
  ///
  /// This is not optional for WeLib: Cloudflare fronts both `/search` and
  /// the book pages, and it fingerprints clients (a plain HTTP request
  /// from Dart is challenged while the same request from curl is not).
  /// Without a solver the page is simply unavailable, so this returns
  /// null rather than pretending.
  Future<String?> _fetchHtml(String url) async => (await _fetchPage(url)).html;

  /// [_fetchHtml] with the HTTP status kept, so a caller can tell a rate
  /// limit (429) apart from a page that simply carried no link.
  Future<({String? html, int? status})> _fetchPage(String url) async {
    // A page the solver already captured in a real browser is the best
    // possible answer for exactly this URL - and skipping the request
    // avoids a fresh 403 round trip and another solve. (Same policy as
    // Anna's Archive; the cache self-expires after 10 minutes.)
    final cached = ChallengeHtmlCache.get(url);
    if (cached != null) {
      _logger.debug('Using cached challenge HTML',
          tag: 'WelibProvider', metadata: {'url': url});
      return (html: cached, status: 200);
    }

    final acceptAnyStatus = Options(validateStatus: (_) => true);

    final Response<String> response;
    try {
      response = await _dio.get<String>(url, options: acceptAnyStatus);
    } catch (e) {
      _logger.warning('WeLib request failed', tag: 'WelibProvider', error: e);
      return (html: null, status: null);
    }

    final status = response.statusCode;
    final body = response.data ?? '';
    if (!_isCloudflareChallenge(response, body)) {
      final ok = status != null && status >= 200 && status < 300;
      return (html: ok ? body : null, status: status);
    }

    if (!WebviewChallengeSolver.isSupported) {
      _logger.warning('WeLib is Cloudflare-gated and no solver is available',
          tag: 'WelibProvider', metadata: {'url': url});
      return (html: null, status: status);
    }
    final html = await WebviewChallengeSolver.fetchHtmlAfterChallenge(url);
    return (
      html: WebviewChallengeSolver.isUsableHtml(html) ? html : null,
      status: status,
    );
  }

  /// welib search params: `q` plus the page number when paging.
  String _queryString(SearchQuery query) {
    final params = <String, String>{'q': query.text};
    if (query.page > 1) params['page'] = query.page.toString();
    return '?${params.entries.map((e) => '${e.key}=${Uri.encodeQueryComponent(e.value)}').join('&')}';
  }

  /// Cloudflare's interstitial. Signals in order of conclusiveness:
  ///
  /// 1. the `cf-mitigated: challenge` response header - Cloudflare's own
  ///    statement, status-independent (welib.org serves the challenge as
  ///    403 against Dart's plain HTTP fingerprint);
  /// 2. the interstitial's own text, but only on a status a challenge
  ///    actually uses (403/429/503) - so a normal page that embeds a
  ///    Cloudflare script (or a Turnstile widget) is never mistaken for
  ///    a block.
  bool _isCloudflareChallenge(Response<String> response, String html) {
    if (response.headers.value('cf-mitigated')?.toLowerCase() == 'challenge') {
      return true;
    }

    final status = response.statusCode ?? 0;
    if (status != 403 && status != 429 && status != 503) return false;

    final lower = html.toLowerCase();
    if (lower.isEmpty) return false;
    const markers = [
      'just a moment',
      'attention required',
      'challenges.cloudflare.com',
      'cf-browser-verification',
    ];
    return markers.any(lower.contains);
  }

  /// Parses welib book cards. Live markup (captured from a book page's
  /// related-books section) is a `div.book-card` holding an
  /// `a[href^="/md5/"]` with the title, an `a[href^="/search?q="]<` with
  /// the author and an `<img>` whose `data-title`/`data-author`
  /// attributes repeat the same data. Public so tests can feed a
  /// captured page without network.
  List<BookData> parseResults(String html, String baseUrl) {
    final document = html_parser.parse(html);
    final books = <BookData>[];

    for (final card in document.querySelectorAll('.book-card')) {
      final link = card.querySelector('a[href^="/md5/"]');
      final href = link?.attributes['href'];
      if (href == null || href.isEmpty) continue;

      final img = card.querySelector('img');
      final title = _firstNonEmpty([
        link?.querySelector('h2')?.text,
        link?.text,
        img?.attributes['data-title'],
      ]);
      if (title == null) continue;

      final author = _firstNonEmpty([
        card.querySelector('a[href^="/search?q="]')?.text,
        img?.attributes['data-author'],
      ]);

      // The first .text-sm is the author. File metadata lives in its own
      // horizontally scrolling row: format, language, year and file size.
      final metadata = card
              .querySelector('div.overflow-x-auto.whitespace-nowrap')
              ?.children
              .where((element) => element.localName == 'span')
              .map((element) =>
                  element.text.replaceFirst(RegExp(r'^\s*·\s*'), '').trim())
              .where((value) => value.isNotEmpty)
              .toList() ??
          const <String>[];
      final language = metadata
          .skip(1)
          .map(bookLanguageName)
          .whereType<String>()
          .firstOrNull;
      final info = [
        if (language != null) language,
        if (metadata.isNotEmpty) metadata.first.toUpperCase(),
        ...metadata.skip(1).where((value) => bookLanguageName(value) == null),
      ].join(', ');

      books.add(BookData(
        title: title,
        author: author,
        thumbnail: img?.attributes['data-src'] ?? img?.attributes['src'],
        link: href.startsWith('http') ? href : '$baseUrl$href',
        md5: _bookIdFromHref(href) ?? href,
        publisher: null,
        info: info.isEmpty ? null : info,
      ));
    }
    return books;
  }

  String? _firstNonEmpty(List<String?> values) {
    for (final value in values) {
      final trimmed = value?.trim() ?? '';
      if (trimmed.isNotEmpty) return trimmed;
    }
    return null;
  }

  String? _bookIdFromHref(String href) =>
      RegExp(r'/md5/([0-9a-fA-F]{32})').firstMatch(href)?.group(1);

  /// Fetches a welib `/md5/<id>` page and returns it as [BookInfoData].
  /// Null when the page cannot be fetched (no attemptable mirror, or
  /// Cloudflare with no solver) or does not parse.
  Future<BookInfoData?> bookInfo(String url) async {
    final mirrors = _mirrors ?? await _resolveMirrors();
    final id = _bookIdFromHref(url);
    if (id == null) return null;

    for (final mirror in mirrors) {
      try {
        final pageUrl = '$mirror/md5/$id';
        final html = await _fetchHtml(pageUrl);
        if (html == null) continue;
        final data = parseBookPage(html, mirror, pageUrl);
        if (data != null) return data;
      } catch (e) {
        _logger.warning('WeLib book page failed, trying next mirror',
            tag: 'WelibProvider', error: e, metadata: {'mirror': mirror});
      }
    }
    return null;
  }

  /// Parses a welib book page. Live markup: `<h1>` is the title, the
  /// `<title>` tag carries `( FORMAT, SIZE )`, `og:image` the cover,
  /// and the free download lives at `/slow_download/<md5>/0/0`.
  BookInfoData? parseBookPage(String html, String baseUrl, String pageUrl) {
    final document = html_parser.parse(html);

    final title = document.querySelector('h1')?.text.trim() ?? '';
    if (title.isEmpty) return null;

    final id = _bookIdFromHref(pageUrl) ?? title;

    // "The Score ( PDF, 1.7 MB ) - WeLib"
    String? format;
    String? size;
    final pageTitle = document.querySelector('title')?.text ?? '';
    final meta = RegExp(r'\(\s*([A-Za-z0-9]+)\s*,\s*([\d.]+\s*[KMGT]?B)\s*\)')
        .firstMatch(pageTitle);
    if (meta != null) {
      format = meta.group(1);
      size = meta.group(2);
    }

    final cover = document
        .querySelector('meta[property="og:image"]')
        ?.attributes['content'];

    // The description meta reads "Author Downloaded from z-lib.org ...".
    final description = document
        .querySelector('meta[name="description"]')
        ?.attributes['content'];
    final author =
        description != null && description.contains('Downloaded from')
            ? description.split('Downloaded from').first.trim()
            : null;

    String? language;
    String? publisher;
    for (final row in document.querySelectorAll('div')) {
      final text = row.text;
      if (text.length > 200) continue;
      final lower = text.toLowerCase();
      if (lower.startsWith('language') && language == null) {
        language = text
            .replaceFirst(RegExp(r'^language', caseSensitive: false), '')
            .trim();
      }
      if (lower.startsWith('publisher') && publisher == null) {
        publisher = text
            .replaceFirst(RegExp(r'^publisher', caseSensitive: false), '')
            .trim();
      }
    }

    final slowDownload = document
            .querySelector('a[href^="/slow_download/"]')
            ?.attributes['href'] ??
        '/slow_download/$id/0/0';

    final info = [
      language,
      format,
      size,
    ].whereType<String>().where((s) => s.isNotEmpty).join(', ');

    return BookInfoData(
      title: title,
      author: (author == null || author.isEmpty) ? 'Unknown' : author,
      thumbnail: cover,
      publisher: publisher,
      info: info.isEmpty ? null : info,
      link: pageUrl,
      md5: id,
      format: format?.toLowerCase() ?? 'epub',
      description: null,
      mirror: slowDownload.startsWith('http')
          ? slowDownload
          : '$baseUrl$slowDownload',
      isFastDownload: false,
    );
  }

  /// Resolves a WeLib download page (`/slow_download/<md5>/0/0`) to a
  /// file URL, or to the reason there is none.
  ///
  /// The page carries the partner-server file as a plain anchor:
  /// `<a class="js-partner-download-link" href="https://x-cdn-x.com/...pdf">`
  /// inside `<div class="mb-4 text-xl font-bold">`. The old path handed
  /// the page to the Anna's Archive webview scraper, which looks for that
  /// class on a `<p>` element - WeLib uses a `<div>` - so it never found
  /// the link and hung on "detecting the download link".
  ///
  /// The page also renders the same "private content" badges and an
  /// in-app-browser warning template for anonymous visitors; neither
  /// gates the file - the link is in the HTML.
  Future<WelibDownload> resolveDownload(String pageUrl) async {
    final page = await _fetchPage(pageUrl);
    if (page.html == null) {
      // WeLib throttles anonymous clients by IP; a 429 is temporary.
      if (page.status == 429) {
        return const WelibDownload(
          refusal: 'WeLib is rate-limiting downloads right now. '
              'Wait a few minutes and try again.',
        );
      }
      // 403/503 is Cloudflare holding this client: the page is there, the
      // bot check just did not clear (no solver, or the window was closed).
      // Say that instead of blaming the book for having no link.
      if (page.status == 403 || page.status == 503) {
        return const WelibDownload(
          refusal: 'WeLib did not let this client through its bot check. '
              'Try again, or open the book in the app browser.',
        );
      }
      return const WelibDownload();
    }

    final html = page.html!;
    // The page is a /slow_download/<md5>/... URL, so the /md5/ helper
    // does not see the id - read it straight out of either shape.
    final md5 = RegExp(r'/(?:md5|slow_download|fast_download|auto_download)/'
            r'([0-9a-fA-F]{32})')
        .firstMatch(pageUrl)
        ?.group(1);
    final origin = Uri.tryParse(pageUrl)?.origin ?? '';
    final document = html_parser.parse(html);

    // WeLib's own hook first: the partner-server file anchor.
    final partnerHref = document
        .querySelector('a.js-partner-download-link[href]')
        ?.attributes['href'];
    if (partnerHref != null && partnerHref.isNotEmpty) {
      return WelibDownload(
          url: partnerHref.startsWith('http')
              ? partnerHref
              : '$origin$partnerHref');
    }

    // Fallback for a page whose markup varies: this book's own download
    // route, or a direct file URL.
    for (final a in document.querySelectorAll('a[href]')) {
      final href = a.attributes['href'] ?? '';
      if (_isBookDownloadLink(href, md5)) {
        return WelibDownload(
            url: href.startsWith('http') ? href : '$origin$href');
      }
    }
    return const WelibDownload();
  }

  /// True when [href] is a download link for the book [md5]: WeLib's own
  /// `/fast_download`/`/auto_download` route for that id, or a direct
  /// file URL. The `/slow_download/<md5>/0/0` page we came from is
  /// deliberately not a match - it is the page, not the file.
  bool _isBookDownloadLink(String href, String? md5) {
    final lower = href.toLowerCase();
    if (RegExp(r'\.(epub|pdf|mobi|azw3?|fb2|djvu|cbr|cbz|zip)(\?|$)')
        .hasMatch(lower)) {
      return true;
    }
    if (md5 == null || !href.contains(md5)) return false;
    return lower.contains('/fast_download/') ||
        lower.contains('/auto_download/');
  }
}

/// Combined outcome of a fan-out search.
@immutable
class SearchManagerResult {
  final List<BookData> books;

  /// Display names of providers that threw; the UI can mention them while
  /// still showing the surviving results.
  final List<String> failedProviders;

  /// The catalog the returned books came from ('' when several sources
  /// contributed or none found anything). Single value because the chain
  /// stops at the first provider with results.
  final String resultSource;

  const SearchManagerResult(
      {required this.books,
      required this.failedProviders,
      this.resultSource = ''});
}

/// Fan-out search across the enabled providers, merging and de-duplicating
/// results. One provider failing never takes the rest down.
class SearchManager {
  SearchManager({MyLibraryDb? database, List<SearchProvider>? providers})
      : _database = database ?? MyLibraryDb.instance,
        _providers = providers ??
            [
              LibgenProvider(),
              ZlibraryProvider(),
              WelibProvider(),
              AnnasArchiveProvider(),
            ];

  final MyLibraryDb _database;
  final List<SearchProvider> _providers;

  static const _providerPrefsKey = 'searchProviders';

  /// Which providers the user enabled in settings. Defaults to all four:
  /// LibGen downloads fast and works without a browser challenge when a
  /// mirror is up; Z-Library is next (DiamWall solves headlessly); WeLib
  /// and Anna's Archive sit behind Cloudflare/DDoS-Guard and need the
  /// browser solver, so they come last.
  Future<Set<SearchProviderId>> enabledProviders() async {
    try {
      final stored = await _database.getPreference(_providerPrefsKey);
      final ids = (stored as String).split(',');
      return ids
          .map((id) =>
              SearchProviderId.values.where((v) => v.name == id).firstOrNull)
          .whereType<SearchProviderId>()
          .toSet();
    } catch (_) {
      return SearchProviderId.values.toSet();
    }
  }

  Future<void> setProviderEnabled(SearchProviderId id, bool enabled) async {
    final current = await enabledProviders();
    if (enabled) {
      current.add(id);
    } else {
      // The app needs at least one source to search.
      if (current.length == 1) return;
      current.remove(id);
    }
    await _database.savePreference(
        _providerPrefsKey, current.map((p) => p.name).join(','));
  }

  /// Turns every search provider back on. Used by the upgrade flow so
  /// a new release's providers are not silently disabled by an old
  /// install's saved toggles.
  Future<void> enableAllProviders() async {
    await _database.savePreference(_providerPrefsKey,
        SearchProviderId.values.map((p) => p.name).join(','));
  }

  /// Searches the enabled providers in order and stops at the first one
  /// that returns results. The order is the provider list order:
  /// LibGen (fast, challenge-free downloads) first, then Z-Library, then
  /// Anna's Archive (behind DDoS-Guard). A provider that finds nothing
  /// (empty, not an error) does not stop the chain - the next one runs.
  /// Errors are collected and surface only when every provider fails.
  Future<SearchManagerResult> search(SearchQuery query) async {
    final enabled = await enabledProviders();
    final active = _providers
        .where((p) => query.source == null
            ? enabled.contains(p.id)
            : p.id == query.source)
        .toList();
    if (active.isEmpty) {
      return const SearchManagerResult(books: [], failedProviders: []);
    }

    final logger = AppLogger();
    logger.info('Searching sources', tag: 'SearchManager', metadata: {
      'query': query.text,
      'providers': [for (final p in active) p.displayName],
    });
    final books = <BookData>[];
    final failed = <String>[];
    String resultSource = '';
    for (final provider in active) {
      logger.debug('Trying ${provider.displayName}', tag: 'SearchManager');
      final outcome = await _searchOne(provider, query, logger);
      if (outcome.error != null) {
        // Keep the website-check URL and recovery controls for an explicit source.
        if (query.source != null) throw outcome.error!;
        failed.add(provider.displayName);
      } else {
        books.addAll(outcome.books);
        if (books.isNotEmpty) resultSource = provider.displayName;
      }
      if (books.isNotEmpty) break;
    }

    logger.info('Search finished', tag: 'SearchManager', metadata: {
      'results': books.length,
      'failed': failed,
      'source': resultSource,
    });
    return SearchManagerResult(
        books: _dedupe(books),
        failedProviders: failed,
        resultSource: resultSource);
  }

  Future<_Outcome> _searchOne(
      SearchProvider provider, SearchQuery query, AppLogger logger) async {
    try {
      final books = await provider.search(query);
      logger.info('${provider.displayName} returned ${books.length} books',
          tag: 'SearchManager');
      // Stamp every result with its catalog so the UI can show where
      // each book came from.
      final language =
          query.filtersEnabled ? bookLanguageName(query.language) : null;
      final tagged = books
          .where((book) =>
              language == null || bookLanguageName(book.info) == language)
          .map((b) => b.copyWith(source: provider.displayName))
          .toList();
      return _Outcome(provider, tagged, null);
    } catch (e) {
      logger.warning('${provider.displayName} search failed',
          tag: 'SearchManager', error: e);
      return _Outcome(provider, const <BookData>[], e);
    }
  }

  /// Keeps the first occurrence per md5. LibGen runs first in the
  /// provider list (fastest, challenge-free downloads), so its entry
  /// wins over the same edition on the other sources.
  List<BookData> _dedupe(List<BookData> books) {
    final seen = <String>{};
    return books.where((b) => seen.add(b.md5)).toList();
  }
}

@immutable
class _Outcome {
  final SearchProvider provider;
  final List<BookData> books;
  final Object? error;

  const _Outcome(this.provider, this.books, this.error);
}
