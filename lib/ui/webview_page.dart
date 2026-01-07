// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

class Webview extends ConsumerStatefulWidget {
  const Webview({super.key, required this.url});
  final String url;
  @override
  // ignore: library_private_types_in_public_api
  _WebviewState createState() => _WebviewState();
}

class _WebviewState extends ConsumerState<Webview> {
  final GlobalKey webViewKey = GlobalKey();

  InAppWebViewController? webViewController;

  final urlController = TextEditingController();

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
                color: Theme.of(context).colorScheme.surface.withOpacity(0.9),
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
                            color: Theme.of(context).colorScheme.tertiary.withAlpha(170),
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
