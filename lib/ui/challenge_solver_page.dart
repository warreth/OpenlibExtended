// Full-screen fallback page shown when the automatic headless challenge
// solver could not clear DDoS-Guard on its own (e.g. a real human CAPTCHA).
// The page loads the blocked URL in a visible InAppWebView, waits until the
// challenge is gone and the page has fully rendered, stores the captured HTML
// in ChallengeHtmlCache (keyed by request URL) and pops itself. The caller then
// simply retries - the cached HTML is used instead of a doomed Dio request.

// Flutter imports:
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:openlib/l10n/app_localizations.dart';

// Package imports:
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

// Project imports:
import 'package:openlib/services/challenge_html_cache.dart';
import 'package:openlib/services/logger.dart';
import 'package:openlib/services/webview_challenge_solver.dart';

class ChallengeSolverPage extends StatefulWidget {
  const ChallengeSolverPage({super.key, required this.url});

  final String url;

  @override
  State<ChallengeSolverPage> createState() => _ChallengeSolverPageState();
}

class _ChallengeSolverPageState extends State<ChallengeSolverPage> {
  final AppLogger _logger = AppLogger();
  InAppWebViewController? _controller;
  Timer? _pollTimer;
  bool _done = false;

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  void _startPolling() {
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
      if (_done || !mounted) return;
      final controller = _controller;
      if (controller == null) return;

      try {
        final title = (await controller.getTitle()) ?? '';
        final bodySnippet = (await controller.evaluateJavascript(
                source:
                    "document.body ? document.body.innerHTML.slice(0, 3000) : ''"))
            ?.toString() ?? '';

        if (title.isEmpty && bodySnippet.isEmpty) return;

        if (WebviewChallengeSolver.isChallengePage(
            title: title, bodySnippet: bodySnippet)) {
          _logger.debug('Challenge still active (solver page)',
              tag: 'ChallengeSolver', metadata: {'title': title});
          return;
        }

        final ready =
            (await controller.evaluateJavascript(source: "document.readyState"))
                ?.toString() ?? '';
        if (ready != 'complete') return;

        // Settle so late XHR content lands in the DOM.
        await Future.delayed(const Duration(milliseconds: 2000));
        if (_done || !mounted) return;

        final html = (await controller.evaluateJavascript(
                source: "document.documentElement.outerHTML"))
            ?.toString() ?? '';
        if (html.isNotEmpty) {
          _done = true;
          ChallengeHtmlCache.store(widget.url, html);
          _logger.info('Solver page captured HTML',
              tag: 'ChallengeSolver',
              metadata: {'url': widget.url, 'length': html.length});
          _pollTimer?.cancel();
          if (mounted) Navigator.pop(context, true);
        }
      } catch (_) {
        // webview might be mid-navigation; keep polling
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.of(context).verifyingAccess)),
      body: SafeArea(
        child: InAppWebView(
          initialUrlRequest: URLRequest(url: WebUri(widget.url)),
          initialSettings: InAppWebViewSettings(
            javaScriptEnabled: true,
            supportZoom: false,
          ),
          onWebViewCreated: (controller) {
            _controller = controller;
            _startPolling();
          },
        ),
      ),
    );
  }
}
