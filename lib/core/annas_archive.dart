// Pure-Dart Anna's Archive parsing shared by the Flutter app and the CLI.
//
// Nothing in this file may import Flutter: `bin/ai_cli.dart` runs in a plain
// `dart` process, and the app services import these helpers too.

// Package imports:
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' show parse;

/// One search result or detail record from Anna's Archive.
class ArchiveBook {
  final String title;
  final String? author;
  final String? thumbnail;
  final String link;
  final String md5;
  final String? publisher;
  final String? info;

  const ArchiveBook({
    required this.title,
    this.author,
    this.thumbnail,
    required this.link,
    required this.md5,
    this.publisher,
    this.info,
  });

  /// Best-effort format guess from the metadata line.
  String get format => ArchiveParsing.formatFromInfo(info);
}

/// A parsed `/md5/<md5>` detail page.
class ArchiveBookDetails extends ArchiveBook {
  /// The book description, when the page has one.
  final String? description;

  /// The `/slow_download/<...>` link on the detail page, when present.
  final String? slowDownloadUrl;

  const ArchiveBookDetails({
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
}

/// Stateless Anna's Archive parsing and URL building.
///
/// The app and the CLI both call these functions so a selector fix or a URL
/// change only has to be made once.
class ArchiveParsing {
  /// Removes emoji/icon noise and collapses whitespace.
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

  /// Detects `pdf` / `cbr` / `cbz` from the info line, defaulting to `epub`.
  static String formatFromInfo(String? info) {
    final lower = (info ?? '').toLowerCase();
    if (lower.contains('pdf')) return 'pdf';
    if (lower.contains('cbr')) return 'cbr';
    if (lower.contains('cbz')) return 'cbz';
    return 'epub';
  }

  /// Returns the md5 segment from a path or URL.
  static String md5FromLink(String urlOrPath) {
    final uri = Uri.parse(urlOrPath);
    final segments = uri.pathSegments;
    final md5Index = segments.indexOf('md5');
    if (md5Index >= 0 && md5Index + 1 < segments.length) {
      return segments[md5Index + 1];
    }
    return segments.isNotEmpty ? segments.last : '';
  }

  /// Text as a browser renders it: script/style contents are removed.
  ///
  /// Anna's Archive embeds click handlers as inline `<script>` tags inside
  /// metadata boxes, and `package:html`'s `.text` includes their source.
  static String visibleText(dom.Element? element) {
    if (element == null) return '';
    final clone = element.clone(true);
    for (final node in clone.querySelectorAll('script, style')) {
      node.remove();
    }
    return clone.text.trim();
  }

  static String resolveUrl(String baseUrl, String href) {
    if (href.startsWith('http://') || href.startsWith('https://')) {
      return href;
    }
    final base = Uri.parse(baseUrl.endsWith('/') ? baseUrl : '$baseUrl/');
    return base.resolve(href).toString();
  }

  static String resolveRelative(String href, String pageUrl) {
    if (href.startsWith('http://') || href.startsWith('https://')) {
      return href;
    }
    return Uri.parse(pageUrl).resolve(href).toString();
  }

  /// Builds a `/search` URL. Mirrors the app's historical `urlEncoder`:
  /// author/publisher become field-scoped terms inside `q`, filters ride the
  /// documented query parameters, and page 1 omits `page`.
  ///
  /// [enableFilters] lets callers force the plain URL (the app disables the
  /// filter UI on trending/category pages). When omitted, filters are used
  /// whenever any filter value is present.
  static String buildSearchUrl({
    required String baseUrl,
    required String query,
    String content = '',
    String sort = '',
    String fileType = '',
    String language = '',
    String year = '',
    String? yearFrom,
    String? yearTo,
    String author = '',
    String publisher = '',
    bool? enableFilters,
    int page = 1,
  }) {
    final fieldTerms = StringBuffer();
    if (author.trim().isNotEmpty) {
      fieldTerms
          .write('author:%22${Uri.encodeQueryComponent(author.trim())}%22 ');
    }
    if (publisher.trim().isNotEmpty) {
      fieldTerms.write(
          'publisher:%22${Uri.encodeQueryComponent(publisher.trim())}%22 ');
    }
    final encodedQuery = '${fieldTerms.toString()}$query'.replaceAll(' ', '+');

    final hasYearRange =
        (yearFrom?.isNotEmpty ?? false) || (yearTo?.isNotEmpty ?? false);
    final filters = enableFilters ??
        (content.isNotEmpty ||
            sort.isNotEmpty ||
            fileType.isNotEmpty ||
            language.isNotEmpty ||
            year.isNotEmpty ||
            hasYearRange);

    final pageParam = page > 1 ? '&page=$page' : '';
    if (!filters) {
      return '$baseUrl/search?q=$encodedQuery$pageParam';
    }

    var url = '$baseUrl/search?index=&sort=$sort';
    if (language.isNotEmpty) url += '&lang=$language';
    url += '&display=';
    url += '&q=$encodedQuery';
    if (content.isNotEmpty) url += '&content=$content';
    if (fileType.isNotEmpty) url += '&ext=$fileType';
    if (year.isNotEmpty) {
      if (year == 'Before 1980') {
        url += '&year_end=1979';
      } else if (year.contains('-')) {
        final parts = year.split('-');
        if (parts.length == 2) {
          url += '&year_from=${parts[0].trim()}&year_end=${parts[1].trim()}';
        }
      } else {
        url += '&year=$year';
      }
    }
    if (yearFrom != null && yearFrom.isNotEmpty) {
      url += '&year_from=${yearFrom.trim()}';
    }
    if (yearTo != null && yearTo.isNotEmpty) {
      url += '&year_end=${yearTo.trim()}';
    }
    return '$url$pageParam';
  }

  /// Parses a search results page, including the `/md5/` link fallback used
  /// when Anna's Archive changes the container markup.
  static List<ArchiveBook> parseSearchResults(
    String html, {
    required String baseUrl,
    String fileType = '',
  }) {
    final document = parse(html);
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

    final books = <ArchiveBook>[];
    for (final container in containers) {
      final mainLink =
          container.querySelector('a.line-clamp-\\[3\\].js-vim-focus');
      final md5Link = container.querySelector('a[href*="/md5/"]');
      final linkElement = mainLink ?? md5Link;
      final thumbnailElement = container.querySelector('a[href*="/md5/"] img');

      final href = linkElement?.attributes['href'];
      if (href == null) continue;

      final title = cleanText(linkElement!.text.trim());
      final md5 = md5FromLink(href);
      final thumbnail = thumbnailElement?.attributes['src'];

      // Author and publisher are the two `/search?q=` links after the title
      // link, in document order.
      dom.Element? authorElement = linkElement.nextElementSibling;
      dom.Element? publisherElement = authorElement?.nextElementSibling;
      if (authorElement?.attributes['href']?.startsWith('/search?q=') != true) {
        authorElement = null;
      }
      if (publisherElement?.attributes['href']?.startsWith('/search?q=') !=
          true) {
        publisherElement = null;
      }

      final authorRaw = authorElement?.text.trim();
      final author = authorRaw == null
          ? null
          : (authorRaw.contains('icon-')
              ? cleanText(authorRaw.split(' ').skip(1).join(' ').trim())
              : cleanText(authorRaw));
      final publisherRaw = publisherElement?.text.trim();
      final publisher = publisherRaw != null ? cleanText(publisherRaw) : null;

      final info = visibleText(container.querySelector('div.text-gray-800'));

      final matchesType = fileType.isEmpty ||
          info.toLowerCase().contains(fileType.toLowerCase());
      if (!matchesType) continue;

      books.add(ArchiveBook(
        title: title,
        author: author?.isEmpty == true ? 'unknown' : author,
        thumbnail: thumbnail,
        link: resolveUrl(baseUrl, href),
        md5: md5,
        publisher: publisher?.isEmpty == true ? 'unknown' : publisher,
        info: info,
      ));
    }
    return books;
  }

  /// Parses one `/md5/` detail page. Returns null when the page has no book
  /// record, which lets callers distinguish "not found" from a network error.
  static ArchiveBookDetails? parseBookDetails(
    String html, {
    required String url,
    required String baseUrl,
  }) {
    final document = parse(html);
    final main = document.querySelector('div.main-inner');
    if (main == null) return null;

    final titleElement = main.querySelector('div.font-semibold.text-2xl');
    if (titleElement == null) return null;

    String? slowDownload;
    final slowLinks =
        main.querySelectorAll('ul.list-inside a[href*="/slow_download/"]');
    final slowHref =
        slowLinks.isEmpty ? null : slowLinks.first.attributes['href'];
    if (slowHref != null && slowHref.isNotEmpty) {
      slowDownload = resolveUrl(baseUrl, slowHref);
    }

    final authorElement = main.querySelector('a[href^="/search?q="].text-base');
    dom.Element? publisherElement = authorElement?.nextElementSibling;
    if (publisherElement?.localName != 'a' ||
        publisherElement?.attributes['href']?.startsWith('/search?q=') !=
            true) {
      publisherElement = null;
    }

    final thumbnailElement = main.querySelector('div[id^="list_cover_"] img');

    dom.Element? descriptionElement;
    final descriptionLabel = main.querySelector(
        'div.js-md5-top-box-description div.text-xs.text-gray-500.uppercase');
    if (descriptionLabel?.text.trim().toLowerCase() == 'description') {
      descriptionElement = descriptionLabel?.nextElementSibling;
    }

    final title = cleanText(titleElement.text.trim().split('<span')[0].trim());
    final author = cleanText(authorElement?.text.trim() ?? 'unknown');
    final publisher = cleanText(publisherElement?.text.trim() ?? 'unknown');
    final info = visibleText(main.querySelector('div.text-gray-800'));

    return ArchiveBookDetails(
      title: title,
      author: author,
      thumbnail: thumbnailElement?.attributes['src'],
      publisher: publisher,
      info: info,
      link: url,
      md5: md5FromLink(url),
      description: visibleText(descriptionElement),
      slowDownloadUrl: slowDownload,
    );
  }

  /// True when a response is a bot-protection interstitial rather than the
  /// page that was requested.
  static bool isChallengeResponse({
    required int statusCode,
    required String body,
    String? cfMitigated,
  }) {
    if (cfMitigated?.toLowerCase() == 'challenge') return true;

    final lower = body.toLowerCase();
    if (lower.isEmpty) return false;

    final title = RegExp(r'<title[^>]*>([^<]*)</title>')
            .firstMatch(lower)
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
    if (hardMarkers.any(lower.contains)) return true;

    if (statusCode == 403 || statusCode == 503) {
      const softMarkers = [
        'checking your browser',
        'enable javascript and cookies',
        'needs to review the security of your connection',
        'verifying you are human',
        'browser check',
        'security check',
      ];
      if (softMarkers.any(lower.contains)) return true;
    }
    return false;
  }

  /// True when [html] is an Anna's Archive page rather than an unrelated
  /// site that happens to share the mirror host.
  static bool isArchivePage(String html) {
    final title = RegExp(r'<title[^>]*>([^<]*)</title>', caseSensitive: false)
            .firstMatch(html)
            ?.group(1)
            ?.toLowerCase() ??
        '';
    return title.contains('anna') && title.contains('archive');
  }

  /// Extracts the direct download link from a `slow_download` page.
  static String? extractSlowDownloadLink(String html, {String pageUrl = ''}) {
    final document = parse(html);
    final paragraph =
        document.querySelector('p[class="mb-4 text-xl font-bold"]');
    final href = paragraph?.querySelector('a')?.attributes['href'];
    if (href == null || href.isEmpty) return null;
    if (pageUrl.isEmpty) return href;
    return resolveRelative(href, pageUrl);
  }
}
