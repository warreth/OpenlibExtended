// Cookie persistence for the embedded browser views.
//
// The embedded webviews (download-link capture, visible challenge solver) run
// the REAL browser engine, so their cookie jar is legitimate. This handler
// persists those cookies per domain so the webview can restore them on the
// next visit.
//
// NOTE: these cookies are deliberately NOT replayed into plain Dio HTTP
// requests. DDoS-Guard clearance is bound to the browser's TLS fingerprint;
// replaying it from Dio gets blocked anyway (that was the alpha's approach
// and it caused endless 403 loops).

// Dart imports:
import 'dart:io';

// Package imports:
import 'package:dio/dio.dart';

// Project imports:
import 'package:openlib/services/logger.dart';
import 'package:openlib/services/database.dart';

class DDoSProtectionHandler {
  static final DDoSProtectionHandler _instance =
      DDoSProtectionHandler._internal();
  factory DDoSProtectionHandler() => _instance;
  DDoSProtectionHandler._internal();

  final AppLogger _logger = AppLogger();
  final MyLibraryDb _database = MyLibraryDb.instance;

  // Cookies cached in memory per domain
  final Map<String, List<Cookie>> _cachedCookies = {};

  /// Store cookies for a domain to avoid repeated captchas
  Future<void> storeCookies(String domain, List<Cookie> cookies) async {
    try {
      final cookieString = cookies.map((c) => '${c.name}=${c.value}').join('; ');
      await _database.setBrowserOptions('cookies_$domain', cookieString);

      // Also cache in memory
      _cachedCookies[domain] = cookies;

      _logger.debug('Cookies stored for domain',
          tag: 'DDoSHandler',
          metadata: {'domain': domain, 'count': cookies.length});
    } catch (e, stackTrace) {
      _logger.error('Failed to store cookies',
          tag: 'DDoSHandler',
          error: e,
          stackTrace: stackTrace);
    }
  }

  /// Retrieve stored cookies for a domain
  Future<List<Cookie>?> getCookies(String domain) async {
    try {
      // Check memory cache first
      if (_cachedCookies.containsKey(domain)) {
        return _cachedCookies[domain];
      }

      // Check database
      final cookieString = await _database.getBrowserOptions('cookies_$domain');
      if (cookieString.isNotEmpty) {
        final cookies = <Cookie>[];
        final pairs = cookieString.split(';');
        for (var pair in pairs) {
          final parts = pair.trim().split('=');
          if (parts.length == 2) {
            cookies.add(Cookie(parts[0], parts[1]));
          }
        }

        // Cache for future use
        _cachedCookies[domain] = cookies;
        _logger.debug('Cookies retrieved from storage',
            tag: 'DDoSHandler',
            metadata: {'domain': domain, 'count': cookies.length});
        return cookies;
      }
    } catch (e) {
      _logger.debug('No stored cookies for domain',
          tag: 'DDoSHandler',
          metadata: {'domain': domain});
    }
    return null;
  }

  /// Clear stored cookies for a domain (useful after manual verification)
  Future<void> clearCookies(String domain) async {
    await _database.setBrowserOptions('cookies_$domain', '');
    _cachedCookies.remove(domain);
    _logger.debug('Cookies cleared for domain',
        tag: 'DDoSHandler',
        metadata: {'domain': domain});
  }

  /// Extract cookies from a response for storage
  List<Cookie> extractCookies(Response response) {
    final cookies = <Cookie>[];

    // Get cookies from Set-Cookie header
    final setCookieHeaders = response.headers.map['set-cookie'];
    if (setCookieHeaders != null) {
      for (var header in setCookieHeaders) {
        try {
          cookies.add(Cookie.fromSetCookieValue(header));
        } catch (e) {
          _logger.debug('Failed to parse Set-Cookie header',
              tag: 'DDoSHandler',
              metadata: {'header': header});
        }
      }
    }

    return cookies;
  }
}
