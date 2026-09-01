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
@immutable
class SearchQuery {
  final String text;
  final String content;
  final String sort;
  final String fileType;
  final String language;
  final String year;
  final bool filtersEnabled;
  final int page;

  const SearchQuery({
    required this.text,
    this.content = '',
    this.sort = '',
    this.fileType = '',
    this.language = '',
    this.year = '',
    this.filtersEnabled = false,
    this.page = 1,
  });

  bool get isEmpty => text.trim().isEmpty;
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
    final params = StringBuffer('req=${Uri.encodeQueryComponent(query.text)}');
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

/// Z-Library: public mirrors rotate constantly and gate search behind
/// logins, so it ships disabled by default and yields an empty result
/// when its mirrors are unreachable instead of failing the whole search.
class ZlibraryProvider implements SearchProvider {
  ZlibraryProvider({Dio? dio, List<String>? mirrors})
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
  SearchProviderId get id => SearchProviderId.zlibrary;

  @override
  String get displayName => 'Z-Library';

  @override
  Future<List<BookData>> search(SearchQuery query) async {
    final mirrors = _mirrors ??
        await InstanceManager().getEnabledUrls(MirrorService.zlibrary);
    for (final mirror in mirrors) {
      try {
        final response = await _dio.get(
          '$mirror/s/${Uri.encodeQueryComponent(query.text)}',
          queryParameters: {if (query.page > 1) 'page': query.page},
        );
        if (response.statusCode != 200) continue;
        final books = _parse(response.data.toString(), mirror);
        if (books.isNotEmpty) return books;
      } catch (_) {
        // Next mirror; Z-Library mirrors are unstable by nature.
      }
    }
    return const [];
  }

  /// Z-Library lists books as item blocks; selectors keep to the parts
  /// that survived its markup generations.
  List<BookData> _parse(String html, String baseUrl) {
    final document = html_parser.parse(html);
    final items = document.querySelectorAll('div.z-book-item, div.book-item');
    final books = <BookData>[];
    for (final item in items) {
      final link = item.querySelector('a[href*="/book/"]');
      final title = link?.text.trim() ?? '';
      if (link == null || title.isEmpty) continue;
      final href = link.attributes['href']!;
      books.add(BookData(
        title: title,
        author: item.querySelector('a[href*="authorsName"]')?.text.trim() ??
            'Unknown',
        thumbnail: null,
        link: href.startsWith('http') ? href : '$baseUrl$href',
        md5: href,
        publisher: null,
        info: null,
      ));
    }
    return books;
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
              AnnasArchiveProvider(),
              LibgenProvider(),
              ZlibraryProvider(),
            ];

  final MyLibraryDb _database;
  final List<SearchProvider> _providers;

  static const _providerPrefsKey = 'searchProviders';

  /// Which providers the user enabled in settings. Defaults to
  /// Anna's Archive only - it was the app's only source before, so a
  /// fresh install keeps its behavior identical.
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
      return {SearchProviderId.annasArchive};
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

  /// Searches all enabled providers concurrently and merges results.
  Future<SearchManagerResult> search(SearchQuery query) async {
    final enabled = await enabledProviders();
    final active = _providers.where((p) => enabled.contains(p.id)).toList();
    if (active.isEmpty) {
      return const SearchManagerResult(books: [], failedProviders: []);
    }

    final logger = AppLogger();
    final outcomes =
        await Future.wait(active.map((p) => _searchOne(p, query, logger)));

    final books = <BookData>[];
    final failed = <String>[];
    for (final outcome in outcomes) {
      if (outcome.error != null) {
        failed.add(outcome.provider.displayName);
      } else {
        books.addAll(outcome.books);
      }
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

  /// Keeps the first occurrence per md5. AA runs first in the provider
  /// list, so AA's richer metadata wins over the same edition on libgen.
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
