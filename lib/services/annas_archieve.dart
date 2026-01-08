// Package imports:
import 'package:dio/dio.dart';
import 'package:html/parser.dart' show parse;
import 'package:html/dom.dart' as dom;

// Project imports:
import 'package:openlib/services/instance_manager.dart';

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
  static const int maxRetries = 2; // Check each server 2x as per requirements
  static const int retryDelayMs = 500; // Delay between retries in milliseconds

  Map<String, dynamic> defaultDioHeaders = {
    "user-agent":
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36",
  };

  // Try request with retry logic across multiple instances
  Future<T> _requestWithRetry<T>(
    Future<T> Function(String baseUrl) requestFn,
  ) async {
    final instances = await _instanceManager.getEnabledInstances();
    
    if (instances.isEmpty) {
      // Use default if no instances are enabled
      return await requestFn(baseUrl);
    }

    Exception? lastException;
    List<String> failedInstances = []; // Track failed instances for logging
    
    // Try each instance
    for (final instance in instances) {
      // Try each instance up to maxRetries times
      for (int attempt = 0; attempt < maxRetries; attempt++) {
        try {
          return await requestFn(instance.baseUrl);
        } catch (e) {
          lastException = e is Exception ? e : Exception(e.toString());
          // Log the failure
          final attemptInfo = '${instance.name} (${instance.baseUrl}) - Attempt ${attempt + 1}/$maxRetries: ${e.toString()}';
          failedInstances.add(attemptInfo);
          // Instance failed: $attemptInfo
          
          // If this is not the last attempt for this instance, wait before retrying
          if (attempt < maxRetries - 1) {
            await Future.delayed(const Duration(milliseconds: retryDelayMs));
          }
        }
      }
    }
    
    // If all instances failed, throw the last exception with context
    // All instances failed. Attempted: ${failedInstances.join(", ")}
    throw lastException ?? Exception('All instances failed');
  }

  String getMd5(String url) {
    final uri = Uri.parse(url);
    final pathSegments = uri.pathSegments;
    return pathSegments.isNotEmpty ? pathSegments.last : '';
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

      if (mainLinkElement == null || mainLinkElement.attributes['href'] == null) {
        continue;
      }

      final String title = mainLinkElement.text.trim();
      final String link = currentBaseUrl + mainLinkElement.attributes['href']!;
      final String md5 = getMd5(mainLinkElement.attributes['href']!);
      final String? thumbnail = thumbnailElement?.attributes['src'];

      // Fix: Use sequential traversal instead of :nth-of-type
      dom.Element? authorLinkElement = mainLinkElement.nextElementSibling;
      dom.Element? publisherLinkElement = authorLinkElement?.nextElementSibling;
      
      if (authorLinkElement?.attributes['href']?.startsWith('/search?q=') != true) {
          authorLinkElement = null;
      }
      if (publisherLinkElement?.attributes['href']?.startsWith('/search?q=') != true) {
          publisherLinkElement = null;
      }

      final String? authorRaw = authorLinkElement?.text.trim();
      final String? author = (authorRaw != null && authorRaw.contains('icon-'))
          ? authorRaw.split(' ').skip(1).join(' ').trim()
          : authorRaw;
      
      final String? publisher = publisherLinkElement?.text.trim();
      
      final infoElement = container.querySelector('div.text-gray-800');
      // No need for _safeParse here if we only treat info as a string
      final String? info = infoElement?.text.trim(); 
      
      final bool hasMatchingFileType = fileType.isEmpty
          ? (info?.contains(RegExp(r'(PDF|EPUB|CBR|CBZ)', caseSensitive: false)) == true)
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
  Future<BookInfoData?> _bookInfoParser(resData, url, String currentBaseUrl) async {
    var document = parse(resData.toString());
    final main = document.querySelector('div.main-inner'); 
    if (main == null) return null;

    // --- Mirror Link Extraction ---
    String? mirror;
    final slowDownloadLinks = main.querySelectorAll('ul.list-inside a[href*="/slow_download/"]');
    if (slowDownloadLinks.isNotEmpty && slowDownloadLinks.first.attributes['href'] != null) {
        mirror = currentBaseUrl + slowDownloadLinks.first.attributes['href']!;
    }
    // --------------------------------


    // --- Core Info Extraction ---
    
    // Title
    final titleElement = main.querySelector('div.font-semibold.text-2xl'); 
    
    // Author
    final authorLinkElement = main.querySelector('a[href^="/search?q="].text-base');
    
    // Publisher
    dom.Element? publisherLinkElement = authorLinkElement?.nextElementSibling;
    if (publisherLinkElement?.localName != 'a' || publisherLinkElement?.attributes['href']?.startsWith('/search?q=') != true) {
        publisherLinkElement = null;
    }

    // Thumbnail
    final thumbnailElement = main.querySelector('div[id^="list_cover_"] img');
    
    // Info/Metadata
    final infoElement = main.querySelector('div.text-gray-800');
    
    // Description
    dom.Element? descriptionElement;
    final descriptionLabel = main.querySelector('div.js-md5-top-box-description div.text-xs.text-gray-500.uppercase');
    
    if (descriptionLabel?.text.trim().toLowerCase() == 'description') {
        descriptionElement = descriptionLabel?.nextElementSibling;
    }
    String description = descriptionElement?.text.trim() ?? " ";

    if (titleElement == null) {
      return null;
    }

    final String title = titleElement.text.trim().split('<span')[0].trim(); 
    final String author = authorLinkElement?.text.trim() ?? "unknown";
    final String? thumbnail = thumbnailElement?.attributes['src'];
    
    final String publisher = publisherLinkElement?.text.trim() ?? "unknown";
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
      required bool enableFilters,
      required String currentBaseUrl}) {
    searchQuery = searchQuery.replaceAll(" ", "+");
    if (!enableFilters) {
      return '$currentBaseUrl/search?q=$searchQuery';
    }
    return '$currentBaseUrl/search?index=&q=$searchQuery&content=$content&ext=$fileType&sort=$sort';
  }

  Future<List<BookData>> searchBooks(
      {required String searchQuery,
      String content = "",
      String sort = "",
      String fileType = "",
      bool enableFilters = true}) async {
    try {
      return await _requestWithRetry<List<BookData>>((currentBaseUrl) async {
        final String encodedURL = urlEncoder(
            searchQuery: searchQuery,
            content: content,
            sort: sort,
            fileType: fileType,
            enableFilters: enableFilters,
            currentBaseUrl: currentBaseUrl);

        final response = await dio.get(encodedURL,
            options: Options(headers: defaultDioHeaders));
        return _parser(response.data, fileType, currentBaseUrl);
      });
    } on DioException catch (e) {
        if (e.type == DioExceptionType.unknown) {
            throw "socketException";
        }
        rethrow;
    }
  }

  Future<BookInfoData> bookInfo({required String url}) async {
    try {
      return await _requestWithRetry<BookInfoData>((currentBaseUrl) async {
        // Replace the base URL in the url parameter if it contains a different one
        String adjustedUrl = url;
        final urlParsed = Uri.parse(url);
        final currentParsed = Uri.parse(currentBaseUrl);
        
        // If the URL has a different host, replace it with current instance's host
        if (urlParsed.host != currentParsed.host) {
          adjustedUrl = '$currentBaseUrl${urlParsed.path}${urlParsed.query.isNotEmpty ? "?${urlParsed.query}" : ""}';
        }
        
        final response = await dio.get(adjustedUrl, 
            options: Options(headers: defaultDioHeaders));
        BookInfoData? data = await _bookInfoParser(response.data, adjustedUrl, currentBaseUrl);
        if (data != null) {
          return data;
        } else {
          throw 'unable to get data';
        }
      });
    } on DioException catch (e) {
      if (e.type == DioExceptionType.unknown) {
        throw "socketException";
      }
      rethrow;
    }
  }
}