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
import 'package:openlib/services/database.dart';
import 'package:openlib/services/diamwall_solver.dart';
import 'package:openlib/services/instance_manager.dart';
import 'package:openlib/services/logger.dart';

/// One searchable catalog the app can query.
enum SearchProviderId { annasArchive, libgen, zlibrary }

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
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 30),
              headers: _browserHeaders,
            )),
        _mirrors = mirrors;

  final Dio _dio;
  final List<String>? _mirrors;

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

    final mirrors = _mirrors ??
        await InstanceManager().getEnabledUrls(MirrorService.libgen);

    Object? lastError;
    for (final mirror in mirrors) {
      try {
        final response = await _dio.get('$mirror/index.php?$params&res=100');
        if (response.statusCode != 200) continue;
        return parseResults(response.data.toString(), mirror);
      } catch (e) {
        lastError = e;
      }
    }
    throw Exception('Library Genesis unreachable: $lastError');
  }
}

/// Z-Library: mirrors sit behind a DiamWall proof-of-work gate, so the
/// provider solves the 503 challenge headlessly (no webview) before
/// parsing results. It still yields an empty result when every mirror
/// fails instead of failing the whole search.
class ZlibraryProvider implements SearchProvider {
  ZlibraryProvider({Dio? dio, List<String>? mirrors})
      : _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 30),
              headers: _browserHeaders,
            )),
        _mirrors = mirrors,
        _solver = DiamWallSolver();

  /// Default mirror order when no explicit list is given and the
  /// instance manager has nothing enabled: z-lib.gd first (the only
  /// mirror with working anonymous book pages and downloads over
  /// https), then z-lib.gl and articles.sk (https, 503-tier PoW), then
  /// the plain-http variants of z-library.sk and 1lib.sk whose https
  /// side sits behind the browser-only DiamWall v2 tier. z-lib.fm is
  /// v2-only on both schemes and is deliberately absent.
  static const defaultMirrors = [
    'https://z-lib.gd',
    'https://z-lib.gl',
    'https://articles.sk',
    'http://z-library.sk',
    'http://1lib.sk',
  ];

  /// The enabled Z-Library instances, best mirror first; falls back to
  /// [defaultMirrors] when the instance manager is unavailable or has
  /// nothing enabled. Never throws.
  Future<List<String>> _resolveMirrors() async {
    try {
      final enabled =
          await InstanceManager().getEnabledUrls(MirrorService.zlibrary);
      if (enabled.isNotEmpty) {
        // Prefer the known-good order: any default mirror keeps its
        // default rank, unknown/custom mirrors go after them.
        enabled.sort((a, b) {
          final ra = defaultMirrors.indexOf(_normalizeMirror(a));
          final rb = defaultMirrors.indexOf(_normalizeMirror(b));
          return _mirrorRank(ra).compareTo(_mirrorRank(rb));
        });
        return enabled;
      }
    } catch (_) {
      // Instance manager unavailable; defaults below.
    }
    return defaultMirrors;
  }

  int _mirrorRank(int defaultIndex) => defaultIndex >= 0 ? defaultIndex : 99;

  String _normalizeMirror(String url) =>
      url.endsWith('/') ? url.substring(0, url.length - 1) : url;

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

    // Dio throws on non-2xx by default; the DiamWall gate is a 503
    // whose body we must read, so accept any status and inspect.
    final acceptAnyStatus = Options(validateStatus: (_) => true);

    for (final mirror in mirrors) {
      try {
        var response = await _dio.get(
          '$mirror/s/${Uri.encodeQueryComponent(query.text)}',
          queryParameters: {if (query.page > 1) 'page': query.page},
          options: acceptAnyStatus,
        );
        if (_solver.looksLikeChallenge(
            response.statusCode ?? 0, response.data.toString())) {
          // DiamWall 503: solve the embedded SHA1 proof-of-work,
          // attach the resulting cookies and retry once.
          final cookies = await _solver.solve(response.data.toString());
          if (cookies != null) {
            final cookieHeader =
                cookies.entries.map((e) => '${e.key}=${e.value}').join('; ');
            try {
              response = await _dio.get(
                '$mirror/s/${Uri.encodeQueryComponent(query.text)}',
                queryParameters: {if (query.page > 1) 'page': query.page},
                options:
                    acceptAnyStatus.copyWith(headers: {'Cookie': cookieHeader}),
              );
            } catch (_) {
              continue; // Next mirror.
            }
          } else {
            continue; // Unsolvable challenge; next mirror.
          }
        }
        if (response.statusCode != 200) continue;
        final books = parseResults(response.data.toString(), mirror);
        if (books.isNotEmpty) return books;
      } catch (_) {
        // Next mirror; Z-Library mirrors are unstable by nature.
      }
    }
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
  Future<BookInfoData?> bookInfo(String url) async {
    final mirrors = _mirrors ?? await _resolveMirrors();
    final path = Uri.parse(url).path;
    final acceptAnyStatus = Options(validateStatus: (_) => true);

    for (final mirror in mirrors) {
      try {
        var response = await _dio.get('$mirror$path', options: acceptAnyStatus);
        response = await _passDiamWall(mirror, response, '$mirror$path');
        if (response.statusCode != 200) continue;

        final pageUrl = '$mirror$path';
        final data = parseBookPage(response.data.toString(), mirror, pageUrl);
        if (data != null) return data;
      } catch (_) {
        // Next mirror; Z-Library mirrors are unstable by nature.
      }
    }
    return null;
  }

  /// GETs [url], solving a DiamWall 503 (once) and a second 503 on the
  /// download hop if present. Returns the first response that is not a
  /// challenge. A non-challenge response is returned as-is.
  Future<Response> _passDiamWall(
      String mirror, Response first, String url) async {
    var response = first;
    final acceptAnyStatus = Options(validateStatus: (_) => true);

    if (!_solver.looksLikeChallenge(
        response.statusCode ?? 0, response.data.toString())) {
      return response;
    }
    final cookies = await _solver.solve(response.data.toString());
    if (cookies == null) return response;
    final cookieHeader =
        cookies.entries.map((e) => '${e.key}=${e.value}').join('; ');

    response = await _dio.get(url,
        options: acceptAnyStatus.copyWith(headers: {'Cookie': cookieHeader}));
    // A second challenge can appear right at the download hop; solve
    // it too before giving up on this mirror.
    if (_solver.looksLikeChallenge(
        response.statusCode ?? 0, response.data.toString())) {
      final again = await _solver.solve(response.data.toString());
      if (again != null) {
        final header =
            again.entries.map((e) => '${e.key}=${e.value}').join('; ');
        response = await _dio.get(url,
            options: acceptAnyStatus.copyWith(headers: {'Cookie': header}));
      }
    }
    return response;
  }

  /// Convenience for the download button: re-fetches the book page
  /// (fresh /dl/ ids), then resolves the first id that answers with
  /// a real CDN redirect. One DiamWall solve for the page plus one
  /// per dead id - usually a single solve in total.
  Future<String?> resolveBookDownload(String bookPageUrl) async {
    final links = await _allDownloadLinks(bookPageUrl);
    if (links.isEmpty) return null;
    final acceptAnyStatus = Options(
      validateStatus: (_) => true,
      followRedirects: false,
      maxRedirects: 0,
    );
    for (final link in links) {
      final resolved = await _resolveOneDownloadUrl(link, acceptAnyStatus);
      if (resolved != null) return resolved;
    }
    return null;
  }

  /// Fetches a book page and returns every `/dl/<id>` link on it,
  /// visible (actions section) ones first. Empty when the page cannot
  /// be fetched or parsed on any mirror.
  Future<List<String>> _allDownloadLinks(String bookPageUrl) async {
    final mirrors = _mirrors ?? await _resolveMirrors();
    final path = Uri.parse(bookPageUrl).path;
    final acceptAnyStatus = Options(validateStatus: (_) => true);

    for (final mirror in mirrors) {
      try {
        var response = await _dio.get('$mirror$path', options: acceptAnyStatus);
        response = await _passDiamWall(mirror, response, '$mirror$path');
        if (response.statusCode != 200) continue;

        final links = _extractDownloadLinks(response.data.toString());
        if (links.isNotEmpty) {
          return links
              .map((href) => href.startsWith('http') ? href : '$mirror$href')
              .toList();
        }
      } catch (_) {
        // Next mirror; Z-Library mirrors are unstable by nature.
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
      final resolved = await _resolveOneDownloadUrl(candidate, acceptAnyStatus);
      if (resolved != null) return resolved;
    }
    return null;
  }

  /// One `/dl/<id>` candidate: solve DiamWall if challenged, then read
  /// the 302 Location. 200 (js/meta redirect page) counts as resolved -
  /// the downloader follows redirects anyway. 204 and 404 mean this id
  /// is dead; the caller tries the next one.
  Future<String?> _resolveOneDownloadUrl(
      String candidate, Options acceptAnyStatus) async {
    var response = await _dio.get(candidate, options: acceptAnyStatus);
    if (_solver.looksLikeChallenge(
        response.statusCode ?? 0, response.data.toString())) {
      final cookies = await _solver.solve(response.data.toString());
      if (cookies == null) return null;
      final cookieHeader =
          cookies.entries.map((e) => '${e.key}=${e.value}').join('; ');
      response = await _dio.get(candidate,
          options: acceptAnyStatus.copyWith(headers: {'Cookie': cookieHeader}));
    }

    if (response.statusCode == 302 || response.statusCode == 301) {
      final location = response.headers.value('location');
      if (location != null && location.startsWith('http')) {
        return location;
      }
    }
    if (response.statusCode == 200) {
      final body = response.data.toString();
      // A bare 200 from /dl/ is usually the js-redirect landing page,
      // not the book: only accept it when it is not the challenge and
      // not an HTML page at all (the CDN serves the book bytes).
      if (!_solver.looksLikeChallenge(200, body) &&
          !body.toLowerCase().contains('<html')) {
        return candidate;
      }
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
      description: null,
      mirror: dlHref == null ? null : '$baseUrl$dlHref',
      isFastDownload: false,
    );
  }
}

/// Combined outcome of a fan-out search.
@immutable
class SearchManagerResult {
  final List<BookData> books;

  /// Display names of providers that threw; the UI can mention them while
  /// still showing the surviving results.
  final List<String> failedProviders;

  const SearchManagerResult(
      {required this.books, required this.failedProviders});
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
              AnnasArchiveProvider(),
            ];

  final MyLibraryDb _database;
  final List<SearchProvider> _providers;

  static const _providerPrefsKey = 'searchProviders';

  /// Which providers the user enabled in settings. Defaults to all three:
  /// LibGen downloads fast and works without a browser challenge, so it
  /// leads; Anna's Archive is behind DDoS-Guard and arrives last.
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
      return {
        SearchProviderId.libgen,
        SearchProviderId.zlibrary,
        SearchProviderId.annasArchive,
      };
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

  /// Searches the enabled providers in order and stops at the first one
  /// that returns results. The order is the provider list order:
  /// LibGen (fast, challenge-free downloads) first, then Z-Library, then
  /// Anna's Archive (behind DDoS-Guard). A provider that finds nothing
  /// (empty, not an error) does not stop the chain - the next one runs.
  /// Errors are collected and surface only when every provider fails.
  Future<SearchManagerResult> search(SearchQuery query) async {
    final enabled = await enabledProviders();
    final active = _providers.where((p) => enabled.contains(p.id)).toList();
    if (active.isEmpty) {
      return const SearchManagerResult(books: [], failedProviders: []);
    }

    final logger = AppLogger();
    final books = <BookData>[];
    final failed = <String>[];
    for (final provider in active) {
      final outcome = await _searchOne(provider, query, logger);
      if (outcome.error != null) {
        failed.add(provider.displayName);
      } else {
        books.addAll(outcome.books);
      }
      if (books.isNotEmpty) break;
    }

    return SearchManagerResult(books: _dedupe(books), failedProviders: failed);
  }

  Future<_Outcome> _searchOne(
      SearchProvider provider, SearchQuery query, AppLogger logger) async {
    try {
      final books = await provider.search(query);
      return _Outcome(provider, books, null);
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
