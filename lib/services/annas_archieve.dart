// Dart imports:
import 'dart:async';
import 'dart:convert';

// Package imports:
import 'package:dio/dio.dart';
import 'package:html/parser.dart' show parse;
import 'package:html/dom.dart' as dom;
import 'package:meta/meta.dart';

// Project imports:
import 'package:openlib/services/instance_manager.dart';
import 'package:openlib/services/logger.dart';
import 'package:openlib/services/network_error.dart';
import 'package:openlib/services/ddos_protection_handler.dart';
import 'package:openlib/services/webview_challenge_solver.dart';

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
  bool isFastDownload;

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
      required this.description,
      this.isFastDownload = false});
}

// ====================================================================
// ANNA'S ARCHIVE SERVICE (ALL FIXES APPLIED)
// ====================================================================

class AnnasArchieve {
  static const String baseUrl = "https://annas-archive.org"; // Fallback default

  final Dio dio = Dio();
  final InstanceManager _instanceManager = InstanceManager();
  final AppLogger _logger = AppLogger();
  final DDoSProtectionHandler _ddosHandler = DDoSProtectionHandler();

  // Optimized retry settings for faster response
  static const int maxRetriesPerInstance =
      1; // Only 1 retry per instance for speed
  static const int requestTimeoutSeconds = 8; // Shorter timeout per request
  static const int retryDelayMs = 200; // Shorter delay between retries

  Map<String, dynamic> defaultDioHeaders = {
    "user-agent":
        "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36",
    "accept":
        "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8",
    "accept-language": "en-US,en;q=0.9",
    "sec-ch-ua": '"Chromium";v="122", "Not(A:Brand";v="24", "Google Chrome";v="122"',
    "sec-ch-ua-mobile": "?0",
    "sec-ch-ua-platform": '"Linux"',
    "sec-fetch-dest": "document",
    "sec-fetch-mode": "navigate",
    "sec-fetch-site": "none",
    "sec-fetch-user": "?1",
    "upgrade-insecure-requests": "1",
  };

  // Check for Cloudflare/DDoS block in response
  bool _isCloudflareBlocked(Response response) {
    // Check cf-mitigated header
    if (response.headers.value("cf-mitigated") == "challenge") {
      _logger.warning('DDoS protection detected: cf-mitigated header',
          tag: 'AnnasArchive');
      return true;
    }

    // Check response body for Cloudflare and other DDoS protection markers
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
      "ddos-guard",
      "ddos guard",
      "checking if the site connection is secure",
      "needs to review the security of your connection",
      "security check",
      "verifying you are human",
      "please wait",
      "browser check",
    ];

    for (final marker in markers) {
      if (body.contains(marker)) {
        _logger.warning('DDoS protection detected in response body',
            tag: 'AnnasArchive',
            metadata: {
              'marker': marker,
              'responseLength': body.length,
              'statusCode': response.statusCode,
              'headers': response.headers.map.toString(),
            });
        
        // Log first 500 chars of response for debugging
        final preview = response.data?.toString().substring(
            0, response.data.toString().length > 500 ? 500 : response.data.toString().length);
        _logger.debug('Response preview', 
            tag: 'AnnasArchive',
            metadata: {'preview': preview});
        
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
            const Duration(seconds: requestTimeoutSeconds),
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

  // Helper to make request with cookies if available
  Future<Response> _makeRequest(
    String url, {
    Map<String, String>? headers,
  }) async {
    final domain = Uri.parse(url).host;
    final requestHeaders = <String, dynamic>{
      ...defaultDioHeaders,
      if (headers != null) ...headers,
    };

    // Inject stored cookies directly into the request headers.
    final cookies = await _ddosHandler.getCookies(domain);
    if (cookies != null && cookies.isNotEmpty) {
      requestHeaders['cookie'] =
          cookies.map((c) => '${c.name}=${c.value}').join('; ');
    }

    return await dio.get(url, options: Options(headers: requestHeaders));
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

  /// Test-only wrappers around the private parsers so tests can verify real
  /// HTML parsing without going through the network layer.
  @visibleForTesting
  List<BookData> parser(resData, String fileType, String currentBaseUrl) =>
      _parser(resData, fileType, currentBaseUrl);

  @visibleForTesting
  Future<BookInfoData?> bookInfoParser(resData, url, String currentBaseUrl) =>
      _bookInfoParser(resData, url, currentBaseUrl);
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
      } else if (year.contains('-')) {
        // Handle year ranges like "2020-2024"
        final parts = year.split('-');
        if (parts.length == 2) {
          url += '&year_from=${parts[0].trim()}&year_end=${parts[1].trim()}';
        }
      } else {
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
        final response = await _makeRequest(encodedURL);

        // Log response details for debugging
        _logger.debug('Search response received',
            tag: 'AnnasArchive',
            metadata: {
              'statusCode': response.statusCode,
              'contentType': response.headers.value('content-type'),
              'responseLength': response.data?.toString().length ?? 0,
            });

        // Store cookies from successful response for future use
        if (response.statusCode == 200) {
          final cookies = _ddosHandler.extractCookies(response);
          if (cookies.isNotEmpty) {
            final domain = Uri.parse(encodedURL).host;
            await _ddosHandler.storeCookies(domain, cookies);
          }
        }

        // Check for Cloudflare block in the response
        if (_isCloudflareBlocked(response)) {
          _logger.warning('Cloudflare/DDoS block detected in search response',
              tag: 'AnnasArchive');
          throw NetworkError(
            type: NetworkErrorType.cloudflareBlock,
            userMessage: "Access blocked by DDoS protection",
            solution:
                "This site is protected and blocking your access.\n\n🔧 Solutions to try:\n• Use a VPN (recommended)\n• Change your DNS to 1.1.1.1 or 8.8.8.8\n• Try a different network\n• Wait a few minutes and retry\n• Click 'Verify in Browser' to solve the captcha manually",
            technicalDetails: "DDoS challenge detected in response",
            rawResponseBody: response.data?.toString(),
            blockedUrl: encodedURL,
          );
        }

        return _parser(response.data, fileType, currentBaseUrl);
      });

      _logger.info('Search completed',
          tag: 'AnnasArchive', metadata: {'results': books.length});
      return books;
    } on NetworkError catch (networkErr) {
      // If all instances failed with 403 and webview solver is available, try automatic solve.
      if (networkErr.type == NetworkErrorType.cloudflareBlock &&
          WebviewChallengeSolver.isSupported) {
        _logger.info('Attempting automatic challenge solve via webview',
            tag: 'AnnasArchive');
        
        final instances = await _instanceManager.getEnabledInstances();
        final targetUrl = networkErr.blockedUrl ??
            urlEncoder(
              searchQuery: searchQuery,
              content: content,
              sort: sort,
              fileType: fileType,
              language: language,
              year: year,
              enableFilters: enableFilters,
              currentBaseUrl: instances.isEmpty ? baseUrl : instances.first.baseUrl,
            );

        final html = await WebviewChallengeSolver.fetchHtmlAfterChallenge(targetUrl);
        if (html != null && html.length > 1000) {
          _logger.info('Challenge solved, parsing results from webview HTML',
              tag: 'AnnasArchive');
          final currentBaseUrl = Uri.parse(targetUrl).origin;
          return _parser(html, fileType, currentBaseUrl);
        } else {
          _logger.warning('Webview solver returned no usable HTML',
              tag: 'AnnasArchive');
        }
      }
      // Re-throw NetworkError as-is for UI to handle if solver failed or unavailable
      rethrow;
    } on DioException catch (e) {
      _logger.error('Search failed',
          tag: 'AnnasArchive', error: e.message ?? e.error);
      throw await _handleErrorAsync(e,
          responseBody: e.response?.data?.toString());
    } catch (e) {
      _logger.error('Unexpected search error',
          tag: 'AnnasArchive', error: e.toString());
      throw await _handleErrorAsync(e);
    }
  }

  Future<String?> getFastDownloadUrl(String md5, String key) async {
    _logger.info('Fetching fast download URL',
        tag: 'AnnasArchive', metadata: {'md5': md5});

    try {
      final url = await _requestWithRetry<String>((currentBaseUrl) async {
        final fastDownloadUrl =
            '$currentBaseUrl/dyn/api/fast_download.json?md5=$md5&key=$key';
        _logger.debug('Calling fast download API',
            tag: 'AnnasArchive', metadata: {'url': fastDownloadUrl});

        final response = await dio.get(fastDownloadUrl,
            options: Options(headers: defaultDioHeaders));

        if (response.statusCode == 200 || response.statusCode == 204) {
          dynamic data = response.data;
          if (data is String) {
            try {
              data = jsonDecode(data);
            } catch (e) {
              _logger.warning('Failed to parse fast download JSON response',
                  tag: 'AnnasArchive', error: e.toString());
              throw Exception('Invalid JSON response');
            }
          }

          if (data is Map && data['download_url'] != null) {
            _logger.info('Fast download URL obtained', tag: 'AnnasArchive');
            return data['download_url'];
          } else {
            final errorMsg = data is Map ? data['error'] : 'Unknown error';
            _logger.warning('Fast download URL not found in response',
                tag: 'AnnasArchive', metadata: {'error': errorMsg});
            throw Exception(errorMsg ?? 'Fast download URL not found');
          }
        } else {
          _logger.error('Fast download API request failed',
              tag: 'AnnasArchive', metadata: {'status': response.statusCode});
          throw Exception('Failed to get fast download URL');
        }
      });
      return url;
    } catch (e) {
      _logger.error('Failed to get fast download URL',
          tag: 'AnnasArchive', error: e.toString());
      return null;
    }
  }

  Future<BookInfoData> bookInfo(
      {required String url, String? donationKey}) async {
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
        final response = await _makeRequest(adjustedUrl);

        // Store cookies from successful response
        if (response.statusCode == 200) {
          final cookies = _ddosHandler.extractCookies(response);
          if (cookies.isNotEmpty) {
            final domain = Uri.parse(adjustedUrl).host;
            await _ddosHandler.storeCookies(domain, cookies);
          }
        }

        // Check for Cloudflare block in the response
        if (_isCloudflareBlocked(response)) {
          _logger.warning('Cloudflare/DDoS block detected in book info response',
              tag: 'AnnasArchive');
          throw NetworkError(
            type: NetworkErrorType.cloudflareBlock,
            userMessage: "Access blocked by DDoS protection",
            solution:
                "This site is protected and blocking your access.\n\n🔧 Solutions to try:\n• Use a VPN (recommended)\n• Change your DNS to 1.1.1.1 or 8.8.8.8\n• Try a different network\n• Wait a few minutes and retry\n• Click 'Verify in Browser' to solve the captcha manually",
            technicalDetails: "DDoS challenge detected in response",
            rawResponseBody: response.data?.toString(),
            blockedUrl: adjustedUrl,
          );
        }

        BookInfoData? data =
            await _bookInfoParser(response.data, adjustedUrl, currentBaseUrl);
        if (data != null) {
          return data;
        } else {
          // Log response preview when parser fails
          final responseStr = response.data?.toString() ?? "";
          final preview = responseStr.substring(
              0, responseStr.length > 1000 ? 1000 : responseStr.length);
          _logger.error('Parser returned null - possible DDoS protection page',
              tag: 'AnnasArchive',
              metadata: {
                'url': adjustedUrl,
                'responseLength': responseStr.length,
                'statusCode': response.statusCode,
                'preview': preview,
              });
          
          throw NetworkError(
            type: NetworkErrorType.unknown,
            userMessage: "Unable to load book details",
            solution:
                "The book information could not be retrieved. Try again or try a different mirror in Settings.",
            technicalDetails: "Parser returned null for URL: $adjustedUrl",
            rawResponseBody: preview,
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
    } on NetworkError catch (networkErr) {
      // If all instances failed with 403 and webview solver is available, try automatic solve.
      if (networkErr.type == NetworkErrorType.cloudflareBlock &&
          WebviewChallengeSolver.isSupported) {
        _logger.info('Attempting automatic challenge solve via webview for bookInfo',
            tag: 'AnnasArchive');
        
        final targetUrl = networkErr.blockedUrl ?? url;
        final html = await WebviewChallengeSolver.fetchHtmlAfterChallenge(targetUrl);
        if (html != null && html.length > 1000) {
          _logger.info('Challenge solved, parsing bookInfo from webview HTML',
              tag: 'AnnasArchive');
          final currentBaseUrl = Uri.parse(targetUrl).origin;
          final data = await _bookInfoParser(html, targetUrl, currentBaseUrl);
          if (data != null) {
            return data;
          } else {
            _logger.warning('Webview HTML parsed but returned null bookInfo',
                tag: 'AnnasArchive');
          }
        } else {
          _logger.warning('Webview solver returned no usable HTML for bookInfo',
              tag: 'AnnasArchive');
        }
      }
      // Re-throw NetworkError as-is for UI to handle if solver failed or unavailable
      rethrow;
    } on DioException catch (e) {
      _logger.error('Failed to fetch book info',
          tag: 'AnnasArchive', error: e.message ?? e.error);
      throw await _handleErrorAsync(e,
          responseBody: e.response?.data?.toString());
    } catch (e) {
      _logger.error('Unexpected book info error',
          tag: 'AnnasArchive', error: e.toString());
      throw await _handleErrorAsync(e);
    }
  }
}
