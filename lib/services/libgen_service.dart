// Dart imports:
import 'dart:async';

// Package imports:
import 'package:dio/dio.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:meta/meta.dart';

// Project imports:
import 'package:openlib/services/annas_archieve.dart';
import 'package:openlib/services/instance_manager.dart';
import 'package:openlib/services/logger.dart';

/// Library Genesis book-info + download service.
///
/// The libgen.li/bz/vg family serves book details on `ads.php?md5=<32 hex>`
/// pages: a `table#main` with a "Title:/Author(s):/Publisher:/Year:" text
/// row, a cover `<img>` and one `get.php?md5=...&key=...` anchor. The key
/// is minted per page load and the link 307-redirects to the CDN file, so
/// it doubles as a native download URL - no webview needed.
class LibgenService {
  static const _browserHeaders = {
    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/'
        '537.36 (KHTML, like Gecko) Chrome/125.0 Safari/537.36',
  };

  final Dio _dio;
  final InstanceManager _instanceManager = InstanceManager();
  final AppLogger _logger = AppLogger();

  LibgenService({Dio? dio})
      : _dio = dio ??
            createDioWithLogging(
                options: BaseOptions(
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 30),
              headers: _browserHeaders,
              followRedirects: true,
              maxRedirects: 5,
            ));

  /// Fetches and parses a libgen `ads.php` page.
  ///
  /// [url] is the link from search results: either absolute
  /// (`https://libgen.vg/ads.php?md5=...`) or bare (`/ads.php?md5=...`,
  /// resolved against the first enabled libgen mirror). When the page's
  /// host fails, the other enabled libgen mirrors are tried by swapping
  /// the host and keeping path + query.
  ///
  /// The page is fetched fresh on every call - the get.php key it
  /// contains is per-page-load and must never be cached.
  Future<BookInfoData?> bookInfo(String url, {String? donationKey}) async {
    final mirrors = await _instanceManager.getEnabledUrls(MirrorService.libgen);
    final candidates = _candidateUrls(url, mirrors);

    Object? lastError;
    for (final candidate in candidates) {
      try {
        _logger.debug('Fetching libgen ads page',
            tag: 'LibgenService', metadata: {'url': candidate});
        final response = await _dio.get(candidate);
        if (response.statusCode != 200) continue;

        final baseUrl = Uri.parse(candidate).origin;
        final data = parseAdsPage(response.data.toString(), baseUrl, candidate);
        if (data != null) return data;

        _logger.warning('Libgen ads page did not parse',
            tag: 'LibgenService', metadata: {'url': candidate});
      } catch (e) {
        lastError = e;
        _logger.debug('Libgen mirror failed, trying next',
            tag: 'LibgenService',
            metadata: {
              'url': candidate,
              'error': e.toString(),
            });
      }
    }

    if (lastError != null) {
      _logger.error('All libgen mirrors failed for book info',
          tag: 'LibgenService', error: lastError);
    }
    return null;
  }

  /// The [url] first, then every enabled libgen mirror with the same
  /// path + query. Bare paths resolve against the first mirror.
  @visibleForTesting
  List<String> candidateUrls(String url, List<String> mirrors) =>
      _candidateUrls(url, mirrors);

  List<String> _candidateUrls(String url, List<String> mirrors) {
    if (mirrors.isEmpty) return [url];

    final effective = url.startsWith('http')
        ? url
        : '${mirrors.first}${url.startsWith('/') ? url : '/$url'}';
    final origin = Uri.parse(effective).origin;
    return [
      effective,
      for (final mirror in mirrors)
        if (mirror != origin) swapHost(effective, mirror),
    ];
  }

  /// Replaces [url]'s scheme + host with [newBaseUrl]'s, keeping its
  /// path and query intact.
  @visibleForTesting
  String swapHost(String url, String newBaseUrl) {
    final original = Uri.parse(url);
    final replacement = Uri.parse(newBaseUrl);
    final port = replacement.hasPort ? ':${replacement.port}' : '';
    final query = original.query.isNotEmpty ? '?${original.query}' : '';
    return '${replacement.scheme}://${replacement.host}$port'
        '${original.path}$query';
  }

  /// Parses a libgen `ads.php` page into [BookInfoData]. Public so tests
  /// can feed captured pages without network.
  ///
  /// Extracts the "Title:/Author(s):/Publisher:/Year:/Series:" row of
  /// the `table#main`, the cover `<img>`, and the get.php download link
  /// (stored absolute in [BookInfoData.mirror]). Returns null on markup
  /// this parser does not recognize - never throws.
  BookInfoData? parseAdsPage(String html, String baseUrl, String url) {
    try {
      final document = html_parser.parse(html);

      final getHref =
          document.querySelector('a[href*="get.php?md5="]')?.attributes['href'];
      if (getHref == null) return null;

      final mainTable = document.querySelector('table#main');
      if (mainTable == null) return null;

      // The metadata row: "Title: ... <br> Author(s): ... <br> ...".
      // The row's raw text keeps label ordering; fields are split on
      // their labels because cover links and stray anchors may appear
      // between them.
      String rowText = '';
      for (final row in mainTable.querySelectorAll('tr')) {
        final text = row.text;
        if (text.contains('Title:') && text.contains('Author')) {
          rowText = _collapseWhitespace(text);
          break;
        }
      }
      if (rowText.isEmpty) return null;

      final fields = _labeledFields(rowText);
      final title = fields['Title'];
      if (title == null || title.isEmpty) return null;

      final md5 = RegExp(r'[?&]md5=([0-9a-fA-F]{32})')
              .firstMatch(url)
              ?.group(1) ??
          RegExp(r'[?&]md5=([0-9a-fA-F]{32})').firstMatch(getHref)?.group(1) ??
          title;

      // Cover: the img inside the main table near the metadata row.
      String? thumbnail;
      final img = mainTable.querySelector('img');
      final src = img?.attributes['src'];
      if (src != null && src.isNotEmpty) {
        thumbnail = _absolute(src, baseUrl);
      }

      final series = fields['Series'];
      final year = fields['Year'];
      final publisher = [
        if ((fields['Publisher'] ?? '').isNotEmpty) fields['Publisher'],
        if ((year ?? '').isNotEmpty) year,
        if ((series ?? '').isNotEmpty) 'Series: $series',
      ].join(', ');

      final info = [
        if ((fields['Language'] ?? '').isNotEmpty) fields['Language'],
      ].join(', ');

      return BookInfoData(
        title: title,
        author: (fields['Author(s)'] ?? '').isEmpty
            ? 'Unknown'
            : fields['Author(s)'],
        thumbnail: thumbnail,
        publisher: publisher.isEmpty ? 'Unknown' : publisher,
        info: info.isEmpty ? null : info,
        link: url,
        md5: md5,
        format: _formatFrom(html, url),
        mirror: _absolute(getHref, baseUrl),
        description: null,
      );
    } catch (e) {
      _logger.warning('Libgen ads page parse failed',
          tag: 'LibgenService', error: e.toString());
      return null;
    }
  }

  /// Splits "Title: A Series: B Author(s): C" on known labels. Value of
  /// a label runs until the next label or end of text.
  static const _labels = [
    'Title:',
    'Series:',
    'Author(s):',
    'Author:',
    'Publisher:',
    'Year:',
    'ISBN:',
    'Language:',
    'Size:',
    'Pages:',
  ];

  Map<String, String> _labeledFields(String text) {
    final fields = <String, String>{};
    for (var i = 0; i < _labels.length; i++) {
      final label = _labels[i];
      final start = text.indexOf(label);
      if (start == -1) continue;
      final valueStart = start + label.length;
      // Value ends at the next label that occurs after this one.
      var end = text.length;
      for (final other in _labels) {
        final idx = text.indexOf(other, valueStart);
        if (idx != -1 && idx < end) end = idx;
      }
      fields[label.substring(0, label.length - 1)] =
          _collapseWhitespace(text.substring(valueStart, end));
    }
    return fields;
  }

  /// File format: from the get.php link or page when it carries an
  /// extension hint; defaults to epub. Libgen pages carry no explicit
  /// format field, so only a real `.<ext>` token counts - the ads
  /// scripts and crypto addresses would otherwise match loose words.
  String _formatFrom(String html, String url) {
    for (final source in [url, html]) {
      final match = RegExp(
        r'[?&](?:ext|format)=\w*?(epub|pdf|mobi|azw3?|cbr|cbz|djvu)|'
        r'\.(epub|pdf|mobi|azw3?|cbr|cbz|djvu)(?=["<\s?])',
        caseSensitive: false,
      ).firstMatch(source);
      final ext = match?.group(1) ?? match?.group(2);
      if (ext != null) return ext.toLowerCase();
    }
    return 'epub';
  }

  String _absolute(String href, String baseUrl) {
    if (href.startsWith('http')) return href;
    return '$baseUrl${href.startsWith('/') ? href : '/$href'}';
  }

  String _collapseWhitespace(String text) =>
      text.replaceAll(RegExp(r'\s+'), ' ').trim();
}
