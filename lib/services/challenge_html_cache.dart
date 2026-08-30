// Cache for HTML pages captured by the challenge solver, keyed by request URL.
//
// When DDoS-Guard blocks every mirror, the solver opens a real browser, lets it
// pass the challenge, and captures the fully rendered page. That HTML is the
// ONLY trustworthy result of that request - replaying cookies through Dio never
// works because the clearance is bound to the browser. This cache hands the
// captured HTML back to the caller (search/bookInfo retry, "Try Again" button)
// so the data survives even after the webview is gone.

// Dart imports:
import 'dart:async';

// Project imports:
import 'package:openlib/services/logger.dart';

class ChallengeHtmlCache {
  ChallengeHtmlCache._();

  static final AppLogger _logger = AppLogger();

  static const _ttl = Duration(minutes: 10);

  // Full request URL -> (html, capturedAt)
  static final Map<String, _CacheEntry> _entries = {};

  static void store(String url, String html) {
    if (url.isEmpty || html.isEmpty) return;
    _entries[url] = _CacheEntry(html: html, capturedAt: DateTime.now());
    _logger.debug('Cached challenge HTML',
        tag: 'ChallengeCache',
        metadata: {'url': url, 'size': html.length, 'entries': _entries.length});
  }

  /// Returns the cached HTML for [url] if it is fresh, otherwise null.
  /// A fresh entry is one captured within the TTL.
  static String? get(String url) {
    if (url.isEmpty) return null;
    _evictExpired();
    return _entries[url]?.html;
  }

  static bool has(String url) => get(url) != null;

  static void clear() => _entries.clear();

  static void _evictExpired() {
    final now = DateTime.now();
    _entries.removeWhere((_, e) => now.difference(e.capturedAt) > _ttl);
  }
}

class _CacheEntry {
  final String html;
  final DateTime capturedAt;

  _CacheEntry({required this.html, required this.capturedAt});
}
