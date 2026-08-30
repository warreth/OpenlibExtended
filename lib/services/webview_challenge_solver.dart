// Cross-platform DDoS-challenge solver.
//
// Anna's Archive is protected by DDoS-Guard. Its clearance cookies are HttpOnly
// AND bound to the browser context, so extracting them and replaying through Dio
// never works (that was the alpha's approach and it loops 403 forever). Instead
// we let a real browser engine pass the challenge and capture the fully rendered
// page HTML:
//
//   - Android/iOS: HeadlessInAppWebView runs invisible and automatic. If a real
//     human CAPTCHA appears, callers fall back to the visible solver page.
//   - Linux/Windows/macOS: desktop_webview_window opens a visible window (the
//     challenge usually auto-passes within seconds).
//
// Captured HTML is stored in ChallengeHtmlCache keyed by the request URL, so a
// retry ("Try Again") or another mirror attempt can parse it directly.

// Dart imports:
import 'dart:async';
import 'dart:convert';
import 'dart:io';

// Package imports:
import 'package:desktop_webview_window/desktop_webview_window.dart'
    as desktop_webview;
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

// Project imports:
import 'package:openlib/services/challenge_html_cache.dart';
import 'package:openlib/services/logger.dart';
import 'package:openlib/services/platform_utils.dart';

class WebviewChallengeSolver {
  WebviewChallengeSolver._();

  static final AppLogger _logger = AppLogger();

  /// Android/iOS use flutter_inappwebview; desktop uses desktop_webview_window.
  static bool get isSupported =>
      PlatformUtils.isMobile || PlatformUtils.isDesktop;

  /// Escape hatch for tests and headless environments: when false,
  /// fetchHtmlAfterChallenge returns null immediately instead of opening
  /// a desktop window. Tests set this to false.
  static bool guiEnabled = true;

  /// Returns true when the given page looks like an unfinished DDoS protection
  /// challenge (DDoS-Guard or Cloudflare) instead of real content.
  static bool isChallengePage({
    required String title,
    required String bodySnippet,
  }) {
    final t = title.toLowerCase();
    final b = bodySnippet.toLowerCase();
    const titleMarkers = [
      'ddos-guard',
      'just a moment',
      'attention required',
      'checking your browser',
    ];
    const bodyMarkers = [
      'ddos-guard/js-challenge',
      'check.ddos-guard.net',
      'ddg-l10n-title',
      'cf-turnstile',
      'challenge-platform',
      'cf-browser-verification',
    ];
    return titleMarkers.any(t.contains) || bodyMarkers.any(b.contains);
  }

  /// Solves the challenge for [url] and returns the fully rendered page HTML,
  /// or null if the challenge could not be cleared within [timeout].
  ///
  /// Desktop opens a visible window (default 3 min — the user may need to
  /// click a checkbox); mobile runs a headless webview (default 60 s,
  /// fully automatic). The result is also stored in ChallengeHtmlCache.
  static Future<String?> fetchHtmlAfterChallenge(
    String url, {
    Duration? timeout,
  }) async {
    if (!isSupported || !guiEnabled) return null;

    final effectiveTimeout = timeout ??
        (PlatformUtils.isMobile
            ? const Duration(seconds: 60)
            : const Duration(minutes: 3));

    final html = PlatformUtils.isMobile
        ? await _solveHeadless(url, effectiveTimeout)
        : await _solveDesktopWindow(url, effectiveTimeout);

    if (html != null) {
      ChallengeHtmlCache.store(url, html);
    }
    return html;
  }

  // ------------------------------------------------------------------
  // MOBILE: HeadlessInAppWebView (invisible, automatic)
  // ------------------------------------------------------------------

  static Future<String?> _solveHeadless(String url, Duration timeout) async {
    HeadlessInAppWebView? headless;
    try {
      final completer = Completer<String?>();
      final controllerHolder = Completer<InAppWebViewController>();

      headless = HeadlessInAppWebView(
        initialUrlRequest: URLRequest(url: WebUri(url)),
        initialSettings: InAppWebViewSettings(
          javaScriptEnabled: true,
          supportZoom: false,
          incognito: false,
          clearCache: false,
        ),
        onLoadStop: (controller, loadedUrl) async {
          try {
            final title = (await controller.getTitle()) ?? '';
            final bodySnippet = (await _js(
                    controller, "document.body ? document.body.innerHTML.slice(0, 3000) : ''")) ??
                '';
            _logger.debug('Headless load stopped',
                tag: 'ChallengeSolver',
                metadata: {'title': title, 'url': loadedUrl.toString()});
            if (isChallengePage(title: title, bodySnippet: bodySnippet)) {
              return; // challenge page; wait for next load
            }
            final html = await _captureHtml(controller);
            if (!completer.isCompleted) completer.complete(html);
          } catch (e) {
            _logger.debug('Headless onLoadStop check failed',
                tag: 'ChallengeSolver', metadata: {'error': e.toString()});
          }
        },
        onWebViewCreated: (controller) {
          if (!controllerHolder.isCompleted) controllerHolder.complete(controller);
        },
      );

      unawaited(headless.run());
      final deadline = DateTime.now().add(timeout);
      InAppWebViewController? controller;
      while (DateTime.now().isBefore(deadline)) {
        if (completer.isCompleted) break;
        // Headless webviews can stop loading without an onLoadStop for the
        // final page; also poll the controller directly.
        try {
          controller ??= await _waitForController(controllerHolder);
          if (controller != null) {
            final title = (await controller.getTitle()) ?? '';
            if (title.isNotEmpty &&
                !isChallengePage(title: title, bodySnippet: '')) {
              final html = await _captureHtml(controller);
              if (html != null &&
                  html.isNotEmpty &&
                  !completer.isCompleted) {
                completer.complete(html);
              }
            }
          }
        } catch (_) {}
        await Future.delayed(const Duration(milliseconds: 1000));
      }

      if (!completer.isCompleted) completer.complete(null);
      return await completer.future;
    } catch (e, st) {
      _logger.error('Headless challenge solver failed',
          tag: 'ChallengeSolver', error: e, stackTrace: st);
      return null;
    } finally {
      try {
        await headless?.dispose();
      } catch (_) {}
    }
  }

  static Future<InAppWebViewController?> _waitForController(
      Completer<InAppWebViewController> completer) async {
    if (completer.isCompleted) return await completer.future;
    // Poll the completer without a typed onTimeout closure.
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (DateTime.now().isBefore(deadline)) {
      if (completer.isCompleted) return await completer.future;
      await Future.delayed(const Duration(milliseconds: 200));
    }
    return null;
  }

  // ------------------------------------------------------------------
  // DESKTOP: visible desktop_webview_window
  // ------------------------------------------------------------------

  static Future<String?> _solveDesktopWindow(
      String url, Duration timeout) async {
    desktop_webview.Webview? webview;
    var closedByUser = false;
    try {
      webview = await desktop_webview.WebviewWindow.create(
        configuration: const desktop_webview.CreateConfiguration(
          windowHeight: 700,
          windowWidth: 1000,
          title: "Verifying access...",
        ),
      );
      webview.onClose.then((_) => closedByUser = true);
      webview.launch(url);

      final deadline = DateTime.now().add(timeout);
      var titleOkPolls = 0;
      while (DateTime.now().isBefore(deadline)) {
        await Future.delayed(const Duration(milliseconds: 1500));
        if (closedByUser) {
          _logger.info('Challenge webview closed by user',
              tag: 'ChallengeSolver');
          return null;
        }

        final title = await _js(webview, "document.title") ?? '';
        final bodySnippet = await _js(
              webview,
              "(document.body ? document.body.innerHTML.slice(0, 3000) : '')",
            ) ??
            '';

        if (title.isEmpty && bodySnippet.isEmpty) continue;

        if (isChallengePage(title: title, bodySnippet: bodySnippet)) {
          titleOkPolls = 0;
          _logger.debug('Challenge still active',
              tag: 'ChallengeSolver',
              metadata: {'title': title.isEmpty ? '(none)' : title});
          continue;
        }

        final readyState = await _js(webview, "document.readyState") ?? '';
        if (readyState != 'complete') {
          titleOkPolls++;
          _logger.debug('Page rendering, waiting for readyState=complete',
              tag: 'ChallengeSolver',
              metadata: {'readyState': readyState, 'polls': titleOkPolls});
          if (titleOkPolls < 10) continue;
        }

        final html = await _js(webview, "document.documentElement.outerHTML");
        if (html != null && html.isNotEmpty) {
          _logger.info('Challenge solved, captured page HTML',
              tag: 'ChallengeSolver',
              metadata: {'length': html.length, 'title': title});
          return html;
        }
      }
      _logger.warning('Challenge solver timed out', tag: 'ChallengeSolver');
      return null;
    } catch (e, st) {
      _logger.error('Desktop challenge solver failed',
          tag: 'ChallengeSolver', error: e, stackTrace: st);
      return null;
    } finally {
      // Closing programmatically crashed GTK in earlier versions; the user
      // closes the window manually.
      webview = null;
    }
  }

  // ------------------------------------------------------------------
  // SHARED HELPERS
  // ------------------------------------------------------------------

  /// Captures outerHTML once the document is complete and settled.
  static Future<String?> _captureHtml(dynamic controllerOrWebview) async {
    final ready = await _js(controllerOrWebview, "document.readyState") ?? '';
    if (ready != 'complete') return null;
    // Settle delay so late XHR content lands in the DOM.
    await Future.delayed(const Duration(milliseconds: 2000));
    final html = await _js(controllerOrWebview, "document.documentElement.outerHTML");
    return html;
  }

  /// Evaluates JS and decodes the result, handling JSON-encoded bridges.
  static Future<String?> _js(dynamic view, String script) async {
    try {
      final result = await view.evaluateJavaScript(script);
      if (result == null) return null;
      var s = result.toString();
      if (s == 'null') return null;
      // WebKit and inappwebview bridges may return strings JSON-encoded.
      if (s.length >= 2 && s.startsWith('"') && s.endsWith('"')) {
        try {
          final decoded = json.decode(s);
          if (decoded is String) return decoded;
        } catch (_) {}
        return s.substring(1, s.length - 1);
      }
      return s;
    } catch (_) {
      return null;
    }
  }
}
