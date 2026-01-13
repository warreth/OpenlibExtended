// Dart imports:
import 'dart:async';
import 'dart:io';

// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:desktop_webview_window/desktop_webview_window.dart';
import 'package:path_provider/path_provider.dart';

// Project imports:
import 'package:openlib/services/platform_utils.dart';
import 'package:openlib/services/logger.dart';

class Webview extends ConsumerStatefulWidget {
  const Webview({super.key, required this.url});
  final String url;
  @override
  // ignore: library_private_types_in_public_api
  _WebviewState createState() => _WebviewState();
}

class _WebviewState extends ConsumerState<Webview> {
  final GlobalKey webViewKey = GlobalKey();
  final AppLogger _logger = AppLogger();

  InAppWebViewController? webViewController;
  Webview? _desktopWebview;
  bool _isDesktopWebviewOpen = false;
  List<String> _capturedDownloadLinks = [];

  final urlController = TextEditingController();

  @override
  void initState() {
    super.initState();
    // On Linux, use desktop_webview_window
    if (PlatformUtils.isLinux) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _openDesktopWebview();
      });
    }
  }

  Future<void> _openDesktopWebview() async {
    try {
      _logger.info("Opening desktop webview for Linux", tag: "WebView", metadata: {"url": widget.url});
      
      // Get app documents directory for webview data
      final appDir = await getApplicationSupportDirectory();
      final webviewDataDir = Directory("${appDir.path}/webview_data");
      if (!await webviewDataDir.exists()) {
        await webviewDataDir.create(recursive: true);
      }

      final webview = await WebviewWindow.create(
        configuration: CreateConfiguration(
          windowHeight: 720,
          windowWidth: 1280,
          title: "Verify Access - OpenLibExtended",
          userDataFolderWindows: webviewDataDir.path,
        ),
      );

      setState(() {
        _isDesktopWebviewOpen = true;
      });

      // Set up message handler for JavaScript communication
      webview.addOnUrlRequestCallback((url) {
        _logger.debug("URL request callback", tag: "WebView", metadata: {"url": url});
        // Check if this is a download link
        if (_isDownloadUrl(url)) {
          _capturedDownloadLinks.add(url);
          _logger.info("Captured download URL", tag: "WebView", metadata: {"url": url});
        }
      });

      // Handle page navigation to extract mirror links
      webview.setOnHistoryChangedCallback((canGoBack, canGoForward) async {
        // Wait for page to load
        await Future.delayed(const Duration(milliseconds: 500));
        
        // Try to extract download links via JavaScript
        try {
          final currentUrl = await webview.evaluateJavaScript("window.location.href");
          _logger.debug("Page navigated", tag: "WebView", metadata: {"url": currentUrl});
          
          if (currentUrl != null) {
            if (currentUrl.toString().contains("slow_download")) {
              // Extract slow_download link
              final result = await webview.evaluateJavaScript(
                """(function() {
                  var paragraphTag = document.querySelector('p[class="mb-4 text-xl font-bold"]');
                  if (paragraphTag) {
                    var anchor = paragraphTag.querySelector('a');
                    if (anchor) return anchor.href;
                  }
                  return null;
                })()"""
              );
              if (result != null && result.toString() != "null") {
                _capturedDownloadLinks.add(result.toString());
                _logger.info("Extracted slow_download link", tag: "WebView");
                // Close webview and return links
                webview.close();
              }
            } else {
              // Extract IPFS links
              final result = await webview.evaluateJavaScript(
                """(function() {
                  var linkTags = document.querySelectorAll('ul>li>a');
                  var links = [];
                  linkTags.forEach(function(e) { links.push(e.href); });
                  return JSON.stringify(links);
                })()"""
              );
              if (result != null && result.toString() != "null" && result.toString() != "[]") {
                try {
                  final links = (result as String).replaceAll('"', '').replaceAll('[', '').replaceAll(']', '').split(',');
                  for (final link in links) {
                    if (link.trim().isNotEmpty) {
                      _capturedDownloadLinks.add(link.trim());
                    }
                  }
                  if (_capturedDownloadLinks.isNotEmpty) {
                    _logger.info("Extracted mirror links", tag: "WebView", metadata: {"count": _capturedDownloadLinks.length});
                    // Close webview and return links
                    webview.close();
                  }
                } catch (e) {
                  _logger.error("Failed to parse mirror links", tag: "WebView", error: e);
                }
              }
            }
          }
        } catch (e) {
          _logger.error("JavaScript evaluation error", tag: "WebView", error: e);
        }
      });

      // Handle webview close - using onClose Future
      webview.onClose.then((_) {
        _logger.info("Desktop webview closed", tag: "WebView", metadata: {"links_captured": _capturedDownloadLinks.length});
        // Use post frame callback to ensure we're in a valid state
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            setState(() {
              _isDesktopWebviewOpen = false;
            });
            Navigator.pop(context, _capturedDownloadLinks);
          }
        });
      });

      // Launch the URL
      webview.launch(widget.url);
      
    } catch (e, stackTrace) {
      _logger.error("Failed to open desktop webview", tag: "WebView", error: e, stackTrace: stackTrace);
      if (mounted) {
        Navigator.pop(context, <String>[]);
      }
    }
  }

  bool _isDownloadUrl(String url) {
    // Check if URL looks like a book download link
    final downloadPatterns = [
      "ipfs.io",
      "cloudflare-ipfs.com",
      "dweb.link",
      "gateway.ipfs",
      ".epub",
      ".pdf",
      ".mobi",
      ".azw",
      "download",
    ];
    final lowerUrl = url.toLowerCase();
    return downloadPatterns.any((pattern) => lowerUrl.contains(pattern));
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Show a waiting message for Linux users while desktop webview is open
    if (PlatformUtils.isLinux) {
      return Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: true,
          title: const Text("Verifying Access"),
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(
                color: Theme.of(context).colorScheme.secondary,
              ),
              const SizedBox(height: 20),
              Text(
                _isDesktopWebviewOpen
                    ? "A browser window has opened..."
                    : "Opening browser window...",
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.tertiary,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                "Complete the verification in the browser window.\nThe download will start automatically when ready.",
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.tertiary.withValues(alpha: 0.7),
                ),
              ),
              if (_capturedDownloadLinks.isNotEmpty) ...[
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.check_circle, color: Colors.green),
                      const SizedBox(width: 8),
                      Text(
                        "${_capturedDownloadLinks.length} download link(s) found",
                        style: const TextStyle(color: Colors.green),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    }
    
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: true,
        title: const Text("Verifying Access"),
      ),
      body: SafeArea(
        child: Stack(
          children: [
            InAppWebView(
              key: webViewKey,
              initialUrlRequest: URLRequest(url: WebUri(widget.url)),
              onWebViewCreated: (controller) {
                webViewController = controller;
              },
              onLoadStart: (controller, url) {},
              onLoadStop: (controller, url) async {
                List<String> bookDownloadLinks = [];
                if (url.toString().contains("slow_download")) {
                  String query =
                      """var paragraphTag=document.querySelector('p[class="mb-4 text-xl font-bold"]');var anchorTagHref=paragraphTag.querySelector('a').href;var url=()=>{return anchorTagHref};url();""";
                  String? mirrorLink = await webViewController
                      ?.evaluateJavascript(source: query);
                  if (mirrorLink != null) {
                    bookDownloadLinks.add(mirrorLink);
                  }
                } else {
                  String query =
                      """var ipfsLinkTags=document.querySelectorAll('ul>li>a');var ipfsLinks=[];var getIpfsLinks=()=>{ipfsLinkTags.forEach(e=>{ipfsLinks.push(e.href)});return ipfsLinks};getIpfsLinks();""";
                  List<dynamic> mirrorLinks = await webViewController
                      ?.evaluateJavascript(source: query);
                  bookDownloadLinks = mirrorLinks.cast<String>();
                }

                if (bookDownloadLinks.isNotEmpty) {
                  Future.delayed(const Duration(milliseconds: 70), () {
                    // ignore: use_build_context_synchronously
                    Navigator.pop(context, bookDownloadLinks);
                  });
                }
              },
            ),
            // Loading overlay to hide countdown
            Positioned.fill(
              child: Container(
                color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.9),
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: 40,
                        height: 40,
                        child: CircularProgressIndicator(
                          color: Theme.of(context).colorScheme.secondary,
                          strokeWidth: 3,
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        'Preparing download...',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.tertiary,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 40),
                        child: Text(
                          'Please wait while we verify access and fetch download links',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 13,
                            color: Theme.of(context).colorScheme.tertiary.withValues(alpha: 0.67),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
