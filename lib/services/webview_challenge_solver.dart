// Desktop DDoS-challenge solver.
//
// Anna's Archive is protected by DDoS-Guard (server: ddos-guard). Its clearance
// cookies (__ddg2_, __ddg5_, __ddgid_, __ddgmark_) are all HttpOnly, so they can
// NOT be read out of a webview via document.cookie and replayed from Dio - that
// approach failed repeatedly. Instead we let a real webview solve the challenge
// and then pull the fully rendered page HTML out of it; the browser attaches its
// own cookies automatically, so no cookie juggling is needed at all.

// Dart imports:
import 'dart:async';

// Package imports:
import 'package:desktop_webview_window/desktop_webview_window.dart'
    as desktop_webview;

// Project imports:
import 'package:openlib/services/logger.dart';
import 'package:openlib/services/platform_utils.dart';

class WebviewChallengeSolver {
  WebviewChallengeSolver._();

  static final AppLogger _logger = AppLogger();

  /// Solver only works where desktop_webview_window is available.
  static bool get isSupported => PlatformUtils.isLinux || PlatformUtils.isWindows;

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
      'please wait',
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

  /// Opens a visible webview window at [url] so the user can pass the
  /// DDoS-Guard / Cloudflare check (usually automatic, ~3 seconds), waits until
  /// real content renders, then returns the page HTML.
  ///
  /// Returns null if unsupported, the window was closed early, or [timeout]
  /// elapsed without the challenge clearing.
  static Future<String?> fetchHtmlAfterChallenge(
    String url, {
    Duration timeout = const Duration(minutes: 3),
  }) async {
    if (!isSupported) return null;

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
      while (DateTime.now().isBefore(deadline)) {
        await Future.delayed(const Duration(milliseconds: 1500));
        if (closedByUser) {
          _logger.info('Challenge webview closed by user',
              tag: 'ChallengeSolver');
          return null;
        }
        final live = webview;
        if (live == null) return null;

        final title =
            await _js(live, "document.title") ?? '';
        final bodySnippet = await _js(
              live,
              "(document.body ? document.body.innerHTML.slice(0, 3000) : '')",
            ) ??
            '';

        if (title.isEmpty && bodySnippet.isEmpty) continue;

        if (isChallengePage(title: title, bodySnippet: bodySnippet)) {
          _logger.debug('Challenge still active',
              tag: 'ChallengeSolver',
              metadata: {'title': title.isEmpty ? '(none)' : title});
          continue;
        }

        // Challenge cleared - grab rendered HTML.
        final html = await _js(live, "document.documentElement.outerHTML");
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
      _logger.error('Challenge solver failed',
          tag: 'ChallengeSolver', error: e, stackTrace: st);
      return null;
    } finally {
      // Don't call close() - causes GTK crashes. Let user close manually or GC clean up.
      webview = null;
    }
  }

  static Future<String?> _js(
      desktop_webview.Webview webview, String script) async {
    try {
      final result = await webview.evaluateJavaScript(script);
      if (result == null) return null;
      // evaluateJavaScript may wrap strings in quotes; strip them for checks.
      var s = result.toString();
      if (s.length >= 2 && s.startsWith('"') && s.endsWith('"')) {
        s = s.substring(1, s.length - 1);
      }
      return s;
    } catch (_) {
      return null;
    }
  }
}
