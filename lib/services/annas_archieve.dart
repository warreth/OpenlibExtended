// Dart imports:
import 'dart:async';

// Package imports:
import 'package:dio/dio.dart';
import 'package:html/parser.dart' show parse;
import 'package:html/dom.dart' as dom;

// Project imports:
import 'package:openlib/services/instance_manager.dart';
import 'package:openlib/services/logger.dart';
import 'package:openlib/services/network_error.dart';

// ====================================================================
// DATA MODELS
// ====================================================================

class BookData {
  final String title;
  final String? author;
  final String? thumbnail;
  final String link;
  final String md5;
  final String? publisher;
  final String? info;

  BookData(
      {required this.title,
      this.author,
      this.thumbnail,
      required this.link,
      required this.md5,
      this.publisher,
      this.info});
}

class BookInfoData extends BookData {
  String? mirror;
  final String? description;
  final String? format;

  BookInfoData(
      {required super.title,
      required super.author,
      required super.thumbnail,
      required super.publisher,
      required super.info,
      required super.link,
      required super.md5,
      required this.format,
      required this.mirror,
      required this.description});
}

// ====================================================================
// ANNA'S ARCHIVE SERVICE (ALL FIXES APPLIED)
// ====================================================================

class AnnasArchieve {
  static const String baseUrl = "https://annas-archive.org"; // Fallback default

  final Dio dio = Dio();
  final InstanceManager _instanceManager = InstanceManager();
  final AppLogger _logger = AppLogger();

  // Optimized retry settings for faster response
  static const int maxRetriesPerInstance =
      1; // Only 1 retry per instance for speed
  static const int requestTimeoutSeconds = 8; // Shorter timeout per request
  static const int retryDelayMs = 200; // Shorter delay between retries

  Map<String, dynamic> defaultDioHeaders = {
    "user-agent":
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36",
  };

  // Check for Cloudflare block in response
  bool _isCloudflareBlocked(Response response) {
    // Check cf-mitigated header
    if (response.headers.value("cf-mitigated") == "challenge") {
      return true;
    }

    // Check response body for Cloudflare markers
    final body = response.data?.toString().toLowerCase() ?? "";
    final markers = [
      "checking your browser",
      "cloudflare",
      "cf-browser-verification",
      "just a moment",
      "enable javascript and cookies",
      "ray id:",
      "attention required",
      "ddos protection",
    ];

    for (final marker in markers) {
      if (body.contains(marker)) {
        return true;
      }
    }
    return false;
  }

  // Convert DioException to user-friendly NetworkError with async diagnostics
  Future<NetworkError> _handleErrorAsync(dynamic error,
      {String? responseBody, String? targetHost}) async {
    return await NetworkError.fromExceptionAsync(error,
        responseBody: responseBody, targetHost: targetHost);
  }

  // Try request with optimized retry logic - fast failure and fallback
  Future<T> _requestWithRetry<T>(
    Future<T> Function(String baseUrl) requestFn,
  ) async {
    final instances = await _instanceManager.getEnabledInstances();

    if (instances.isEmpty) {
      // Use default if no instances are enabled
      return await requestFn(baseUrl);
    }

    Exception? lastException;
    String? lastUsedHost;

    // Try each instance - they should already be sorted by speed from auto-ranking
    for (int i = 0; i < instances.length; i++) {
      final instance = instances[i];
      lastUsedHost = instance.baseUrl;

      // Fewer retries for subsequent instances (they're slower)
      final retriesForThis = i == 0 ? maxRetriesPerInstance : 0;

      for (int attempt = 0; attempt <= retriesForThis; attempt++) {
        try {
          // Apply timeout to the request function
          final result = await requestFn(instance.baseUrl).timeout(
            Duration(seconds: requestTimeoutSeconds),
            onTimeout: () {
              throw TimeoutException(
                  "Request timed out after ${requestTimeoutSeconds}s");
            },
          );

          // Success - log which instance worked
          _logger.debug('Request succeeded on attempt ${attempt + 1}',
              tag: 'AnnasArchive', metadata: {'instance': instance.name});

          return result;
        } catch (e) {
          lastException = e is Exception ? e : Exception(e.toString());

          _logger.debug('Instance failed', tag: 'AnnasArchive', metadata: {
            'instance': instance.name,
            'attempt': attempt + 1,
            'error': e.toString().substring(
                0, (e.toString().length > 50) ? 50 : e.toString().length),
          });

          // Short delay before retry (only if we're retrying this instance)
          if (attempt < retriesForThis) {
            await Future.delayed(const Duration(milliseconds: retryDelayMs));
          }
        }
      }
    }

    // All instances failed - throw with diagnostic info
    _logger.error('All instances failed', tag: 'AnnasArchive');

    // Throw a diagnostic NetworkError instead of the raw exception
    throw await _handleErrorAsync(
      lastException ?? Exception('All instances failed'),
      targetHost: lastUsedHost,
    );
  }

  String getMd5(String url) {
    final uri = Uri.parse(url);
    final pathSegments = uri.pathSegments;
    return pathSegments.isNotEmpty ? pathSegments.last : '';
  }

  // Remove emojis, icons and non-standard characters from text
  String cleanText(String text) {
    return text
        .replaceAll(RegExp(r'[\u{1F300}-\u{1F9FF}]', unicode: true), '')
        .replaceAll(RegExp(r'[\u{2600}-\u{26FF}]', unicode: true), '')
        .replaceAll(RegExp(r'[\u{2700}-\u{27BF}]', unicode: true), '')
        .replaceAll(RegExp(r'[\u{1F600}-\u{1F64F}]', unicode: true), '')
        .replaceAll(RegExp(r'[\u{1F680}-\u{1F6FF}]', unicode: true), '')
        .replaceAll(RegExp(r'🔍'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  String getFormat(String info) {
    final infoLower = info.toLowerCase();
    if (infoLower.contains('pdf')) {
      return 'pdf';
    } else if (infoLower.contains('cbr')) {
      return "cbr";
    } else if (infoLower.contains('cbz')) {
      return "cbz";
    }
    return "epub";
  }

  // --------------------------------------------------------------------
  // _parser FUNCTION (Search Results - Fixed nth-of-type issue)
  // --------------------------------------------------------------------
  List<BookData> _parser(resData, String fileType, String currentBaseUrl) {
    var document = parse(resData.toString());

    var bookContainers =
        document.querySelectorAll('div.flex.pt-3.pb-3.border-b');

    List<BookData> bookList = [];

    for (var container in bookContainers) {
      final mainLinkElement =
          container.querySelector('a.line-clamp-\\[3\\].js-vim-focus');
      final thumbnailElement = container.querySelector('a[href^="/md5/"] img');

      if (mainLinkElement == null ||
          mainLinkElement.attributes['href'] == null) {
        continue;
      }

      final String title = cleanText(mainLinkElement.text.trim());
      final String link = currentBaseUrl + mainLinkElement.attributes['href']!;
      final String md5 = getMd5(mainLinkElement.attributes['href']!);
      final String? thumbnail = thumbnailElement?.attributes['src'];

      // Fix: Use sequential traversal instead of :nth-of-type
      dom.Element? authorLinkElement = mainLinkElement.nextElementSibling;
      dom.Element? publisherLinkElement = authorLinkElement?.nextElementSibling;

      if (authorLinkElement?.attributes['href']?.startsWith('/search?q=') !=
          true) {
        authorLinkElement = null;
      }
      if (publisherLinkElement?.attributes['href']?.startsWith('/search?q=') !=
          true) {
        publisherLinkElement = null;
      }

      final String? authorRaw = authorLinkElement?.text.trim();
      final String? author = (authorRaw != null && authorRaw.contains('icon-'))
          ? cleanText(authorRaw.split(' ').skip(1).join(' ').trim())
          : (authorRaw != null ? cleanText(authorRaw) : null);

      final String? publisherRaw = publisherLinkElement?.text.trim();
      final String? publisher =
          publisherRaw != null ? cleanText(publisherRaw) : null;

      final infoElement = container.querySelector('div.text-gray-800');
      // No need for _safeParse here if we only treat info as a string
      final String? info = infoElement?.text.trim();

      final bool hasMatchingFileType = fileType.isEmpty
          ? (info?.contains(
                  RegExp(r'(PDF|EPUB|CBR|CBZ)', caseSensitive: false)) ==
              true)
          : info?.toLowerCase().contains(fileType.toLowerCase()) == true;

      if (hasMatchingFileType) {
        final BookData book = BookData(
          title: title,
          author: author?.isEmpty == true ? "unknown" : author,
          thumbnail: thumbnail,
          link: link,
          md5: md5,
          publisher: publisher?.isEmpty == true ? "unknown" : publisher,
          info: info,
        );
        bookList.add(book);
      }
    }
    return bookList;
  }
  // --------------------------------------------------------------------

  // --------------------------------------------------------------------
  // _bookInfoParser FUNCTION (Detail Page - Fixed 'unable to get data' error)
  // --------------------------------------------------------------------
  Future<BookInfoData?> _bookInfoParser(
      resData, url, String currentBaseUrl) async {
    var document = parse(resData.toString());
    final main = document.querySelector('div.main-inner');
    if (main == null) return null;

    // --- Mirror Link Extraction ---
    String? mirror;
    final slowDownloadLinks =
        main.querySelectorAll('ul.list-inside a[href*="/slow_download/"]');
    if (slowDownloadLinks.isNotEmpty &&
        slowDownloadLinks.first.attributes['href'] != null) {
      mirror = currentBaseUrl + slowDownloadLinks.first.attributes['href']!;
    }
    // --------------------------------

    // --- Core Info Extraction ---

    // Title
    final titleElement = main.querySelector('div.font-semibold.text-2xl');

    // Author
    final authorLinkElement =
        main.querySelector('a[href^="/search?q="].text-base');

    // Publisher
    dom.Element? publisherLinkElement = authorLinkElement?.nextElementSibling;
    if (publisherLinkElement?.localName != 'a' ||
        publisherLinkElement?.attributes['href']?.startsWith('/search?q=') !=
            true) {
      publisherLinkElement = null;
    }

    // Thumbnail
    final thumbnailElement = main.querySelector('div[id^="list_cover_"] img');

    // Info/Metadata
    final infoElement = main.querySelector('div.text-gray-800');

    // Description
    dom.Element? descriptionElement;
    final descriptionLabel = main.querySelector(
        'div.js-md5-top-box-description div.text-xs.text-gray-500.uppercase');

    if (descriptionLabel?.text.trim().toLowerCase() == 'description') {
      descriptionElement = descriptionLabel?.nextElementSibling;
    }
    String description = descriptionElement?.text.trim() ?? " ";

    if (titleElement == null) {
      return null;
    }

    final String title =
        cleanText(titleElement.text.trim().split('<span')[0].trim());
    final String author =
        cleanText(authorLinkElement?.text.trim() ?? "unknown");
    final String? thumbnail = thumbnailElement?.attributes['src'];

    final String publisher =
        cleanText(publisherLinkElement?.text.trim() ?? "unknown");
    // NOTE: If you extract any numeric data from the 'info' string later in your app (e.g., file size or page count)
    // and attempt to convert it to an integer or double, that's where you should use _safeParse.
    final String info = infoElement?.text.trim() ?? '';

    return BookInfoData(
      title: title,
      author: author,
      thumbnail: thumbnail,
      publisher: publisher,
      info: info,
      link: url,
      md5: getMd5(url),
      format: getFormat(info),
      mirror: mirror,
      description: description,
    );
  }
  // --------------------------------------------------------------------

  String urlEncoder(
      {required String searchQuery,
      required String content,
      required String sort,
      required String fileType,
      required String language,
      required String year,
      required bool enableFilters,
      required String currentBaseUrl}) {
    searchQuery = searchQuery.replaceAll(" ", "+");
    if (!enableFilters) {
      return '$currentBaseUrl/search?q=$searchQuery';
    }

    // Build URL with parameters in correct order for Anna's Archive
    // Working format: /search?index=&sort=&lang=nl&display=&q=query
    String url = '$currentBaseUrl/search?index=&sort=$sort';

    // Add language filter if specified (must be before q=)
    if (language.isNotEmpty) {
      url += '&lang=$language';
    }

    // Add display parameter
    url += '&display=';

    // Add search query
    url += '&q=$searchQuery';

    // Add content filter only if specified
    if (content.isNotEmpty) {
      url += '&content=$content';
    }

    // Add extension filter only if specified
    if (fileType.isNotEmpty) {
      url += '&ext=$fileType';
    }

    // Add year filter if specified
    if (year.isNotEmpty) {
      if (year == "Before 1980") {
        url += '&year_end=1979';
      } else if (!year.contains('-')) {
        url += '&year=$year';
      }
    }

    return url;
  }

  Future<List<BookData>> searchBooks(
      {required String searchQuery,
      String content = "",
      String sort = "",
      String fileType = "",
      String language = "",
      String year = "",
      bool enableFilters = true}) async {
    _logger.info('Searching books', tag: 'AnnasArchive', metadata: {
      'query': searchQuery,
      'content': content,
      'sort': sort,
      'fileType': fileType,
      'language': language,
      'year': year,
      'filtersEnabled': enableFilters,
    });

    try {
      final books =
          await _requestWithRetry<List<BookData>>((currentBaseUrl) async {
        final String encodedURL = urlEncoder(
            searchQuery: searchQuery,
            content: content,
            sort: sort,
            fileType: fileType,
            language: language,
            year: year,
            enableFilters: enableFilters,
            currentBaseUrl: currentBaseUrl);

        _logger.debug('Fetching search results',
            tag: 'AnnasArchive', metadata: {'url': encodedURL});
        final response = await dio.get(encodedURL,
            options: Options(headers: defaultDioHeaders));

        // Check for Cloudflare block in the response
        if (_isCloudflareBlocked(response)) {
          _logger.warning('Cloudflare block detected in search response',
              tag: 'AnnasArchive');
          throw NetworkError(
            type: NetworkErrorType.cloudflareBlock,
            userMessage: "Access blocked by Cloudflare protection",
            solution:
                "This site is protected and blocking your access.\n\n🔧 Solutions to try:\n• Use a VPN (recommended)\n• Change your DNS to 1.1.1.1 or 8.8.8.8\n• Try a different network\n• Wait a few minutes and retry",
            technicalDetails: "Cloudflare challenge detected in response",
            rawResponseBody: response.data?.toString(),
          );
        }

        return _parser(response.data, fileType, currentBaseUrl);
      });

      _logger.info('Search completed',
          tag: 'AnnasArchive', metadata: {'results': books.length});
      return books;
    } on NetworkError {
      // Re-throw NetworkError as-is for proper UI handling
      rethrow;
    } on DioException catch (e) {
      _logger.error('Search failed',
          tag: 'AnnasArchive', error: e.message ?? e.error);
      // Convert to user-friendly NetworkError with diagnostics
      throw await _handleErrorAsync(e,
          responseBody: e.response?.data?.toString());
    } catch (e) {
      _logger.error('Unexpected search error',
          tag: 'AnnasArchive', error: e.toString());
      throw await _handleErrorAsync(e);
    }
  }

  Future<BookInfoData> bookInfo({required String url}) async {
    _logger.info('Fetching book info',
        tag: 'AnnasArchive', metadata: {'url': url});

    try {
      final data =
          await _requestWithRetry<BookInfoData>((currentBaseUrl) async {
        // Replace the base URL in the url parameter if it contains a different one
        String adjustedUrl = url;
        final urlParsed = Uri.parse(url);
        final currentParsed = Uri.parse(currentBaseUrl);

        // If the URL has a different host, replace it with current instance's host
        if (urlParsed.host != currentParsed.host) {
          adjustedUrl =
              '$currentBaseUrl${urlParsed.path}${urlParsed.query.isNotEmpty ? "?${urlParsed.query}" : ""}';
        }

        _logger.debug('Fetching book details',
            tag: 'AnnasArchive', metadata: {'url': adjustedUrl});
        final response = await dio.get(adjustedUrl,
            options: Options(headers: defaultDioHeaders));

        // Check for Cloudflare block in the response
        if (_isCloudflareBlocked(response)) {
          _logger.warning('Cloudflare block detected in book info response',
              tag: 'AnnasArchive');
          throw NetworkError(
            type: NetworkErrorType.cloudflareBlock,
            userMessage: "Access blocked by Cloudflare protection",
            solution:
                "This site is protected and blocking your access.\n\n🔧 Solutions to try:\n• Use a VPN (recommended)\n• Change your DNS to 1.1.1.1 or 8.8.8.8\n• Try a different network\n• Wait a few minutes and retry",
            technicalDetails: "Cloudflare challenge detected in response",
            rawResponseBody: response.data?.toString(),
          );
        }

        BookInfoData? data =
            await _bookInfoParser(response.data, adjustedUrl, currentBaseUrl);
        if (data != null) {
          return data;
        } else {
          throw NetworkError(
            type: NetworkErrorType.unknown,
            userMessage: "Unable to load book details",
            solution:
                "The book information could not be retrieved. Try again or try a different mirror in Settings.",
            technicalDetails: "Parser returned null for URL: $adjustedUrl",
          );
        }
      });

      _logger.info('Book info retrieved successfully',
          tag: 'AnnasArchive',
          metadata: {
            'title': data.title,
            'format': data.format,
            'hasMirror': data.mirror != null,
          });
      return data;
    } on NetworkError {
      // Re-throw NetworkError as-is for proper UI handling
      rethrow;
    } on DioException catch (e) {
      _logger.error('Failed to fetch book info',
          tag: 'AnnasArchive', error: e.message ?? e.error);
      // Convert to user-friendly NetworkError with diagnostics
      throw await _handleErrorAsync(e,
          responseBody: e.response?.data?.toString());
    } catch (e) {
      _logger.error('Unexpected book info error',
          tag: 'AnnasArchive', error: e.toString());
      throw await _handleErrorAsync(e);
    }
  }
}
