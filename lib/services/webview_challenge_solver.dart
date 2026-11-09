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

// Package imports:
import 'package:desktop_webview_window/desktop_webview_window.dart'
    as desktop_webview;
import 'package:flutter/foundation.dart';
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

  /// Escape hatch for tests and headless environments: when false, no real
  /// webview is opened (headless or desktop window) and the solve returns
  /// null — but a registered [visibleSolverFallback] is still consulted,
  /// so tests can exercise the fallback without any webview.
  static bool guiEnabled = true;

  /// When false (user turned "verify in background" off in settings), the
  /// headless attempt is skipped on mobile and the visible window runs
  /// straight away - some devices never finish an invisible webview.
  static bool headlessEnabled = true;

  /// UI hook: when a headless mobile solve fails, this is called so the app
  /// shell to push the visible solver page over the current screen. It
  /// returns the captured HTML (which we then cache) or null when the user
  /// backs out without solving. A callback keeps this service free of UI
  /// imports. Registered by the app shell at startup.
  static Future<String?> Function(String url)? visibleSolverFallback;

  /// Test seam for the mobile/desktop branch: when set, overrides the real
  /// platform check. Production never sets it.
  @visibleForTesting
  static bool? overrideIsMobile;

  static bool get _isMobile => overrideIsMobile ?? PlatformUtils.isMobile;

  /// Callers discard captured pages shorter than this. The solver must not
  /// report success for a redirect stub they would throw away - that used
  /// to log "Challenge solved" and then "no usable HTML" (issue #118).
  static const int minUsableHtmlLength = 1000;

  static bool isUsableHtml(String? html) =>
      html != null && html.length >= minUsableHtmlLength;

  /// A desktop window that never renders a document is a failed load, not
  /// a slow challenge. Give up after this long instead of polling until
  /// the full solve timeout (issue #118).
  static const Duration desktopBlankTimeout = Duration(seconds: 15);

  /// Only one desktop challenge window at a time. A second
  /// `WebviewWindow.create` while the first exists destroys/reuses it on
  /// Windows; its `onClose` then aborts the first solve. A second caller
  /// waits briefly, then gives up instead of opening a competing window.
  static bool _desktopSolveActive = false;
  static const Duration _desktopQueueWait = Duration(seconds: 5);

  /// Whether the solver closes its desktop window when the solve ends.
  /// Linux keeps the old behaviour (GTK crashed on programmatic close in
  /// earlier versions); tests override this to exercise the close path.
  @visibleForTesting
  static bool closeDesktopWindow = !PlatformUtils.isLinux;

  /// Test seam for the desktop window; production uses
  /// [desktop_webview.WebviewWindow.create].
  @visibleForTesting
  static Future<desktop_webview.Webview> Function(
      desktop_webview.CreateConfiguration configuration)? desktopWindowFactory;

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

  /// True when the page is the browser's own error page (DNS failure,
  /// refused connection, offline) rather than a challenge or real content.
  /// WebView2 and WebKit use different wording; match the stable markers.
  static bool looksLikeLoadError(String title, String bodySnippet) {
    final text = '${title.toLowerCase()} ${bodySnippet.toLowerCase()}';
    const markers = [
      'err_name_not_resolved',
      'err_connection',
      'err_internet_disconnected',
      'err_address_unreachable',
      'dns_probe_finished',
      "this site can't be reached",
      "can't reach this page",
      'server not found',
    ];
    return markers.any(text.contains);
  }

  /// Solves the challenge for [url] and returns the fully rendered page HTML,
  /// or null if the challenge could not be cleared within [timeout].
  ///
  /// Desktop opens a visible window (default 3 min — the user may need to
  /// click a checkbox); mobile runs a headless webview (default 60 s,
  /// fully automatic). The result is also stored in ChallengeHtmlCache.
  ///
  /// On mobile, a headless failure falls back to [visibleSolverFallback]
  /// when it is registered (headless misses human CAPTCHAs and races like
  /// the loadStop/readyState one); the desktop window is already visible,
  /// so no fallback is needed there.
  static Future<String?> fetchHtmlAfterChallenge(
    String url, {
    Duration? timeout,
  }) async {
    if (!isSupported) return null;

    final effectiveTimeout = timeout ??
        (_isMobile ? const Duration(seconds: 60) : const Duration(minutes: 3));

    final tryHeadless = guiEnabled && (headlessEnabled || !_isMobile);
    var html = tryHeadless
        ? (_isMobile
            ? await _solveHeadless(url, effectiveTimeout)
            : await _solveDesktopWindow(url, effectiveTimeout))
        : null;

    if (html == null && _isMobile && visibleSolverFallback != null) {
      _logger.info('Headless solve failed, using visible fallback',
          tag: 'ChallengeSolver', metadata: {'url': url});
      html = await visibleSolverFallback!(url);
    }

    // A short page (a redirect stub, a block notice) is not a solved
    // challenge. Never cache it: the callers would discard it anyway and
    // the cache would then hide the real attempt.
    if (!isUsableHtml(html)) {
      if (html != null) {
        _logger.warning(
            'Challenge solver returned a page below the usable threshold',
            tag: 'ChallengeSolver',
            metadata: {'length': html.length, 'url': url});
      }
      return null;
    }
    ChallengeHtmlCache.store(url, html!);
    return html;
  }

  // ------------------------------------------------------------------
  // MOBILE: HeadlessInAppWebView (invisible, automatic)
  // ------------------------------------------------------------------

  /// Decides whether an onLoadStop may complete the solve. Only a real page
  /// with captured HTML counts — a loadStop on a page that is still loading
  /// (null/empty HTML) must NOT complete, or the poll loop below would be
  /// dead and the solve would return null even though the challenge had
  /// already been cleared. See the Android log regression this guards.
  @visibleForTesting
  static bool shouldCompleteFromLoadStop(String title, String? capturedHtml) =>
      isUsableHtml(capturedHtml) &&
      !isChallengePage(title: title, bodySnippet: '');

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
            final bodySnippet = (await _js(controller,
                    "document.body ? document.body.innerHTML.slice(0, 3000) : ''")) ??
                '';
            _logger.debug('Headless load stopped',
                tag: 'ChallengeSolver',
                metadata: {'title': title, 'url': loadedUrl.toString()});
            if (isChallengePage(title: title, bodySnippet: bodySnippet)) {
              return; // challenge page; wait for next load
            }
            // Not ready yet (readyState != complete)? Just wait — the poll
            // loop picks the page up. Never complete with null here: that
            // used to kill the solve right after the challenge was cleared.
            final html = await _captureHtml(controller);
            if (shouldCompleteFromLoadStop(title, html) &&
                !completer.isCompleted) {
              completer.complete(html);
            }
          } catch (e) {
            _logger.debug('Headless onLoadStop check failed',
                tag: 'ChallengeSolver', metadata: {'error': e.toString()});
          }
        },
        onWebViewCreated: (controller) {
          if (!controllerHolder.isCompleted) {
            controllerHolder.complete(controller);
          }
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
              if (isUsableHtml(html) && !completer.isCompleted) {
                completer.complete(html);
              }
            }
          }
        } catch (_) {}
        await Future.delayed(const Duration(milliseconds: 1000));
      }

      // The only place the completer may complete with null: the deadline.
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
    // Serialize desktop solves; see _desktopSolveActive.
    final queueDeadline = DateTime.now().add(_desktopQueueWait);
    while (_desktopSolveActive) {
      if (DateTime.now().isAfter(queueDeadline)) {
        _logger.warning('Another challenge window is already open; skipping',
            tag: 'ChallengeSolver', metadata: {'url': url});
        return null;
      }
      await Future.delayed(const Duration(milliseconds: 200));
    }
    _desktopSolveActive = true;
    try {
      return await _solveDesktopWindowLocked(url, timeout);
    } finally {
      _desktopSolveActive = false;
    }
  }

  static Future<String?> _solveDesktopWindowLocked(
      String url, Duration timeout) async {
    desktop_webview.Webview? webview;
    try {
      const configuration = desktop_webview.CreateConfiguration(
        windowHeight: 700,
        windowWidth: 1000,
        title: "Verifying access...",
      );
      final factory = desktopWindowFactory;
      webview = await (factory != null
          ? factory(configuration)
          : desktop_webview.WebviewWindow.create(configuration: configuration));
      // The DDoS-Guard gate is a silent JS check with nothing to click:
      // keep the window off-screen until an interactive challenge shows
      // up. Linux does not implement the visibility call; it stays
      // visible there, as before.
      await _setWindowVisible(webview, false);
      webview.launch(url);

      return await solveDesktopWebview(webview, timeout: timeout);
    } catch (e, st) {
      _logger.error('Desktop challenge solver failed',
          tag: 'ChallengeSolver', error: e, stackTrace: st);
      return null;
    } finally {
      // The old code left the window for the user to close, so a failed
      // search left stale "Verifying access..." windows behind (issue
      // #118). GTK crashed on programmatic close in earlier versions, so
      // Linux keeps the old behaviour; Windows/macOS close it.
      if (closeDesktopWindow) {
        try {
          webview?.close();
        } catch (e) {
          _logger.debug('Could not close the challenge window',
              tag: 'ChallengeSolver', metadata: {'error': e.toString()});
        }
      }
    }
  }

  /// Polls an already-launched desktop webview until it renders a usable
  /// page, the user closes it, the document stays blank, or [timeout]
  /// expires. Exposed for tests with a fake [desktop_webview.Webview].
  static Future<String?> solveDesktopWebview(
    desktop_webview.Webview webview, {
    required Duration timeout,
    Duration pollInterval = const Duration(milliseconds: 1500),
    Duration blankTimeout = desktopBlankTimeout,
  }) async {
    var closedByUser = false;
    unawaited(webview.onClose.then((_) => closedByUser = true));

    final deadline = DateTime.now().add(timeout);
    var blankSince = DateTime.now();
    DateTime? shortSince;
    var interactiveShown = false;
    var titleOkPolls = 0;

    while (DateTime.now().isBefore(deadline)) {
      await Future.delayed(pollInterval);
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

      if (title.isEmpty && bodySnippet.isEmpty) {
        final blankFor = DateTime.now().difference(blankSince);
        if (blankFor >= blankTimeout) {
          _logger.warning('Challenge window stayed blank; giving up',
              tag: 'ChallengeSolver',
              metadata: {'blankFor': blankFor.inSeconds});
          return null;
        }
        continue;
      }
      blankSince = DateTime.now();

      if (looksLikeLoadError(title, bodySnippet)) {
        _logger.warning('Challenge window showed a load error; giving up',
            tag: 'ChallengeSolver', metadata: {'title': title});
        return null;
      }

      if (isChallengePage(title: title, bodySnippet: bodySnippet)) {
        titleOkPolls = 0;
        if (!interactiveShown &&
            hasInteractiveChallengeMarkers(bodySnippet)) {
          interactiveShown = true;
          await _setWindowVisible(webview, true);
          await _bringToForeground(webview);
          _logger.info('Challenge needs interaction; showing the window',
              tag: 'ChallengeSolver', metadata: {'title': title});
        }
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
      if (isUsableHtml(html)) {
        _logger.info('Challenge solved, captured page HTML',
            tag: 'ChallengeSolver',
            metadata: {'length': html!.length, 'title': title});
        return html;
      }
      // A redirect stub or an empty shell is not a solved page; keep
      // polling so the real page can land, but never report success for
      // something the caller will discard. If it stays short, treat it
      // as a failed load instead of polling to the full deadline.
      shortSince ??= DateTime.now();
      final shortFor = DateTime.now().difference(shortSince);
      if (shortFor >= blankTimeout) {
        _logger.warning(
            'Captured page stayed below the usable threshold; giving up',
            tag: 'ChallengeSolver',
            metadata: {
              'length': html?.length ?? 0,
              'shortFor': shortFor.inSeconds,
              'title': title,
            });
        return null;
      }
      _logger.debug('Captured page too short; still waiting',
          tag: 'ChallengeSolver',
          metadata: {'length': html?.length ?? 0, 'title': title});
    }

    _logger.warning('Challenge solver timed out', tag: 'ChallengeSolver');
    return null;
  }

  /// True when a challenge page carries something a person can act on.
  /// DDoS-Guard's silent JS check has none; Cloudflare's Turnstile does.
  static bool hasInteractiveChallengeMarkers(String bodySnippet) {
    final b = bodySnippet.toLowerCase();
    return b.contains('<iframe') ||
        b.contains('cf-turnstile') ||
        b.contains('challenge-stage') ||
        b.contains('type="checkbox"') ||
        b.contains('<canvas') ||
        b.contains('<button');
  }

  static Future<void> _setWindowVisible(
      desktop_webview.Webview webview, bool visible) async {
    try {
      await webview.setWebviewWindowVisibility(visible);
    } catch (e) {
      // Linux does not implement this call; the window stays visible.
      _logger.debug('Could not change challenge window visibility',
          tag: 'ChallengeSolver', metadata: {'error': e.toString()});
    }
  }

  static Future<void> _bringToForeground(
      desktop_webview.Webview webview) async {
    try {
      await webview.bringToForeground();
    } catch (_) {}
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
    final html =
        await _js(controllerOrWebview, "document.documentElement.outerHTML");
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
