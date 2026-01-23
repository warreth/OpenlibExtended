// Dart imports:
import 'dart:async';

// Package imports:
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

// Project imports:
import 'package:openlib/services/logger.dart';
import 'package:openlib/services/platform_utils.dart';

/// Service to fetch mirror links in the background without showing UI
class MirrorFetcherService {
  static final MirrorFetcherService _instance = MirrorFetcherService._internal();
  factory MirrorFetcherService() => _instance;
  MirrorFetcherService._internal();

  final AppLogger _logger = AppLogger();

  /// Fetch mirror links from the given URL in the background
  /// Returns a list of mirror download links
  Future<List<String>> fetchMirrors(String url) async {
    _logger.info('Starting background mirror fetch', tag: 'MirrorFetcher', metadata: {'url': url});
    
    // On Linux, WebView is not supported - return empty to trigger manual download flow
    if (PlatformUtils.isLinux) {
      _logger.warning('WebView not supported on Linux, returning empty mirrors', tag: 'MirrorFetcher');
      return [];
    }
    
    final Completer<List<String>> completer = Completer<List<String>>();
    final List<String> bookDownloadLinks = [];

    try {
      // Create a headless webview to load the page
      final headlessWebView = HeadlessInAppWebView(
        initialUrlRequest: URLRequest(url: WebUri(url)),
        onLoadStop: (controller, url) async {
          if (url == null) {
            _logger.warning('URL is null in onLoadStop', tag: 'MirrorFetcher');
            if (!completer.isCompleted) {
              completer.complete([]);
            }
            return;
          }
          
          _logger.debug('Page loaded successfully', tag: 'MirrorFetcher', metadata: {'url': url.toString()});
          
          try {
            if (url.toString().contains("slow_download")) {
              // For slow_download pages, extract the direct link
              String query =
                  """var paragraphTag=document.querySelector('p[class="mb-4 text-xl font-bold"]');var anchorTagHref=paragraphTag.querySelector('a').href;var url=()=>{return anchorTagHref};url();""";
              String? mirrorLink = await controller.evaluateJavascript(source: query);
              if (mirrorLink != null) {
                bookDownloadLinks.add(mirrorLink);
                _logger.info('Extracted slow_download link', tag: 'MirrorFetcher');
              }
            } else {
              // For other mirror pages, extract all IPFS/mirror links
              String query =
                  """var ipfsLinkTags=document.querySelectorAll('ul>li>a');var ipfsLinks=[];var getIpfsLinks=()=>{ipfsLinkTags.forEach(e=>{ipfsLinks.push(e.href)});return ipfsLinks};getIpfsLinks();""";
              List<dynamic> mirrorLinks =
                  await controller.evaluateJavascript(source: query);
              bookDownloadLinks.addAll(mirrorLinks.cast<String>());
              _logger.info('Extracted mirror links', tag: 'MirrorFetcher', metadata: {'count': bookDownloadLinks.length});
            }
            
            // Complete the future with the extracted links
            if (!completer.isCompleted) {
              completer.complete(bookDownloadLinks);
            }
          } catch (e) {
            _logger.error('JavaScript evaluation error', tag: 'MirrorFetcher', error: e);
            // Evaluation error, complete with empty list
            if (!completer.isCompleted) {
              completer.complete([]);
            }
          }
        },
        onReceivedError: (controller, request, error) {
          _logger.error('WebView load error', tag: 'MirrorFetcher', error: error.description);
          // Load error, complete with empty list
          if (!completer.isCompleted) {
            completer.complete([]);
          }
        },
      );

      // Run the headless webview
      await headlessWebView.run();
      _logger.debug('Headless webview started', tag: 'MirrorFetcher');

      // Wait for the page to load and links to be extracted
      // Maximum wait time of 15 seconds
      final result = await completer.future.timeout(
        const Duration(seconds: 15),
        onTimeout: () {
          _logger.warning('Mirror fetch timed out after 15 seconds', tag: 'MirrorFetcher');
          return [];
        },
      );

      // Dispose the headless webview
      await headlessWebView.dispose();
      _logger.debug('Headless webview disposed', tag: 'MirrorFetcher', metadata: {'mirrors_found': result.length});

      return result;
    } catch (e, stackTrace) {
      _logger.error('Failed to fetch mirrors', tag: 'MirrorFetcher', error: e, stackTrace: stackTrace);
      // Return empty list on error
      return [];
    }
  }
}
