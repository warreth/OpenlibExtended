// Dart imports:
import 'dart:async';
import 'dart:io';

// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:desktop_webview_window/desktop_webview_window.dart' as desktop_webview;
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
  bool _isDesktopWebviewOpen = false;
  bool _linksFound = false;
  final List<String> _capturedDownloadLinks = [];
  Timer? _pollingTimer;
  desktop_webview.Webview? _desktopWebview;

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

      _desktopWebview = await desktop_webview.WebviewWindow.create(
        configuration: desktop_webview.CreateConfiguration(
          windowHeight: 720,
          windowWidth: 1280,
          title: "Verify Access - OpenLibExtended",
          userDataFolderWindows: webviewDataDir.path,
        ),
      );

      setState(() {
        _isDesktopWebviewOpen = true;
      });

      // Handle webview close
      _desktopWebview!.onClose.then((_) {
        _logger.info("Desktop webview closed by user", tag: "WebView", metadata: {"links_captured": _capturedDownloadLinks.length});
        _pollingTimer?.cancel();
        // Return whatever links we found
        if (mounted && !_linksFound) {
          Future.microtask(() {
            if (mounted) {
              Navigator.pop(context, _capturedDownloadLinks);
            }
          });
        }
      });

      // Launch the URL
      _desktopWebview!.launch(widget.url);
      
      // Start polling for download links after page loads
      await Future.delayed(const Duration(seconds: 2));
      _startPolling();
      
    } catch (e, stackTrace) {
      _logger.error("Failed to open desktop webview", tag: "WebView", error: e, stackTrace: stackTrace);
      if (mounted) {
        Navigator.pop(context, <String>[]);
      }
    }
  }

  void _startPolling() {
    // Poll every 2 seconds for download links
    _pollingTimer = Timer.periodic(const Duration(seconds: 2), (timer) async {
      if (_linksFound || _desktopWebview == null) {
        timer.cancel();
        return;
      }
      
      try {
        // Check current URL
        final currentUrl = await _desktopWebview!.evaluateJavaScript("window.location.href");
        if (currentUrl == null) return;
        
        final urlStr = currentUrl.toString().replaceAll('"', '');
        
        if (urlStr.contains("slow_download")) {
          // Extract slow_download link
          final result = await _desktopWebview!.evaluateJavaScript(
            """(function() {
              var paragraphTag = document.querySelector('p[class="mb-4 text-xl font-bold"]');
              if (paragraphTag) {
                var anchor = paragraphTag.querySelector('a');
                if (anchor && anchor.href) return anchor.href;
              }
              return null;
            })()"""
          );
          
          if (result != null && result.toString() != "null" && result.toString().isNotEmpty) {
            final link = result.toString().replaceAll('"', '');
            if (link.startsWith("http") && !_capturedDownloadLinks.contains(link)) {
              _capturedDownloadLinks.add(link);
              _logger.info("Extracted slow_download link", tag: "WebView", metadata: {"link": link});
              _returnLinksAndClose();
            }
          }
        } else {
          // Extract IPFS links
          final result = await _desktopWebview!.evaluateJavaScript(
            """(function() {
              var linkTags = document.querySelectorAll('ul>li>a');
              var links = [];
              linkTags.forEach(function(e) { 
                if (e.href && e.href.startsWith('http')) {
                  links.push(e.href); 
                }
              });
              return JSON.stringify(links);
            })()"""
          );
          
          if (result != null && result.toString() != "null" && result.toString() != "[]") {
            try {
              final linksStr = result.toString();
              final cleanStr = linksStr.replaceAll('[', '').replaceAll(']', '').replaceAll('"', '');
              final links = cleanStr.split(',').where((l) => l.trim().isNotEmpty && l.trim().startsWith('http')).toList();
              
              for (final link in links) {
                final cleanLink = link.trim();
                if (cleanLink.isNotEmpty && !_capturedDownloadLinks.contains(cleanLink)) {
                  _capturedDownloadLinks.add(cleanLink);
                }
              }
              if (_capturedDownloadLinks.isNotEmpty) {
                _logger.info("Extracted mirror links", tag: "WebView", metadata: {"count": _capturedDownloadLinks.length});
                _returnLinksAndClose();
              }
            } catch (e) {
              _logger.error("Failed to parse mirror links", tag: "WebView", error: e);
            }
          }
        }
      } catch (e) {
        // Ignore errors during polling, webview might be closed
      }
    });
  }

  void _returnLinksAndClose() async {
    if (_capturedDownloadLinks.isNotEmpty && !_linksFound && mounted) {
      _linksFound = true;
      _pollingTimer?.cancel();
      _logger.info("Returning download links", tag: "WebView", metadata: {"count": _capturedDownloadLinks.length});
      
      // Save links before any operations
      final links = List<String>.from(_capturedDownloadLinks);
      
      // DON'T close the webview programmatically - causes OpenGL crash on Linux
      // Instead, just clear reference and let user close it manually
      // The onClose handler will fire when user closes the window
      _desktopWebview = null;
      
      // Return the links immediately
      if (mounted) {
        Navigator.pop(context, links);
      }
    }
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    // Don't close the webview - let it remain open to avoid OpenGL crash
    // The user will close it manually
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
    
    // Mobile/Windows: Use InAppWebView
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
