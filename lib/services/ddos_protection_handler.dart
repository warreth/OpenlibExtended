// Modular DDoS protection handler with cookie persistence and browser fallback
// Handles Cloudflare, DDoS-Guard, and other DDoS protection mechanisms

// Dart imports:
import 'dart:async';
import 'dart:convert';
import 'dart:io';

// Package imports:
import 'package:dio/dio.dart';

// Project imports:
import 'package:openlib/services/logger.dart';
import 'package:openlib/services/database.dart';

// ====================================================================
// DDOs PROTECTION TYPES
// ====================================================================

enum DDoSProvider {
  cloudflare,
  ddosGuard,
  unknown,
}

class DDoSProtectionData {
  final DDoSProvider provider;
  final String challengeUrl;
  final Map<String, String> headers;
  final String? formData;
  final String? formAction;
  final List<Cookie> cookies;

  DDoSProtectionData({
    required this.provider,
    required this.challengeUrl,
    required this.headers,
    this.formData,
    this.formAction,
    required this.cookies,
  });

  Map<String, dynamic> toJson() {
    return {
      'provider': provider.name,
      'challengeUrl': challengeUrl,
      'headers': headers,
      'formData': formData,
      'formAction': formAction,
      'cookies': cookies.map((c) => {'name': c.name, 'value': c.value}).toList(),
    };
  }

  factory DDoSProtectionData.fromJson(Map<String, dynamic> json) {
    return DDoSProtectionData(
      provider: DDoSProvider.values.firstWhere(
        (e) => e.name == json['provider'],
        orElse: () => DDoSProvider.unknown,
      ),
      challengeUrl: json['challengeUrl'] as String,
      headers: Map<String, String>.from(json['headers'] as Map),
      formData: json['formData'] as String?,
      formAction: json['formAction'] as String?,
      cookies: (json['cookies'] as List)
          .map((c) => Cookie((c as Map)['name'] as String, c['value'] as String))
          .toList(),
    );
  }

  String toJsonString() => jsonEncode(toJson());

  factory DDoSProtectionData.fromJsonString(String jsonStr) =>
      DDoSProtectionData.fromJson(jsonDecode(jsonStr));
}

// ====================================================================
// DDOs PROTECTION HANDLER
// ====================================================================

class DDoSProtectionHandler {
  static final DDoSProtectionHandler _instance =
      DDoSProtectionHandler._internal();
  factory DDoSProtectionHandler() => _instance;
  DDoSProtectionHandler._internal();

  final AppLogger _logger = AppLogger();
  final MyLibraryDb _database = MyLibraryDb.instance;

  // Cookies stored per domain for automatic retry
  final Map<String, List<Cookie>> _cachedCookies = {};

  // ====================================================================
  // COOKIE MANAGEMENT
  // ====================================================================

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

  // ====================================================================
  // DDOs DETECTION
  // ====================================================================

  /// Detect DDoS protection in response
  DDoSProtectionData? detectProtection(Response response) {
    final body = response.data?.toString().toLowerCase() ?? "";
    final headers = response.headers.map;

    // Check for Cloudflare
    if (headers.containsKey('cf-mitigated') || 
        headers.containsKey('cf-ray') ||
        headers.containsKey('cf-cache-status') ||
        body.contains('cloudflare') ||
        body.contains('cf-turnstile') ||
        body.contains('turnstile') ||
        body.contains('just a moment...') ||
        body.contains('cf-browser-verification')) {
      return _extractCloudflareChallenge(response, body);
    }

    // Check for DDoS-Guard
    if (body.contains('ddos-guard') ||
        body.contains('ddos guard') ||
        headers.containsKey('x-ddos-guard')) {
      return _extractDdosGuardChallenge(response, body);
    }

    return null;
  }

  DDoSProtectionData _extractCloudflareChallenge(Response response, String body) {
    _logger.info('Cloudflare DDoS protection detected',
        tag: 'DDoSHandler',
        metadata: {
          'statusCode': response.statusCode,
          'hasCfMitigated': response.headers.value('cf-mitigated') != null,
        });

    // Extract form data if present
    String? formData;
    String? formAction;
    
    // Look for the challenge form
    if (body.contains('<form') && body.contains('type="hidden"')) {
      // Extract action
      final formMatch = RegExp(r'<form[^>]*action="([^"]*)"').firstMatch(body);
      if (formMatch != null) {
        formAction = formMatch.group(1);
      }

      // Extract hidden inputs
      final hiddenInputs = RegExp(r'<input[^>]*type="hidden"[^>]*name="([^"]*)"[^>]*value="([^"]*)"')
          .allMatches(body)
          .map((m) => '${m.group(1)}=${Uri.encodeComponent(m.group(2) ?? "")}')
          .join('&');
      if (hiddenInputs.isNotEmpty) {
        formData = hiddenInputs;
      }
    }

    return DDoSProtectionData(
      provider: DDoSProvider.cloudflare,
      challengeUrl: formAction ?? response.requestOptions.uri.toString(),
      headers: {'content-type': 'application/x-www-form-urlencoded'},
      formData: formData,
      formAction: formAction,
      cookies: response.headers.allCookies,
    );
  }

  DDoSProtectionData _extractDdosGuardChallenge(Response response, String body) {
    _logger.info('DDoS-Guard protection detected',
        tag: 'DDoSHandler',
        metadata: {'statusCode': response.statusCode});

    String? formData;
    String? formAction;

    // DDoS-Guard typically has a form with JS verification
    final formMatch = RegExp(r'<form[^>]*action="([^"]*)"').firstMatch(body);
    if (formMatch != null) {
      formAction = formMatch.group(1);
    }

    return DDoSProtectionData(
      provider: DDoSProvider.ddosGuard,
      challengeUrl: formAction ?? response.requestOptions.uri.toString(),
      headers: {'content-type': 'application/x-www-form-urlencoded'},
      formData: formData,
      formAction: formAction,
      cookies: response.headers.allCookies,
    );
  }

  // ====================================================================
  // RESOLVE PROTECTION
  // ====================================================================

  /// Attempt to automatically resolve DDoS protection (if we have cookies)
  /// Returns true if request should be retried, false if user needs to verify
  Future<bool?> resolveProtection(String url, DDoSProtectionData data) async {
    _logger.info('Attempting to resolve DDoS protection',
        tag: 'DDoSHandler',
        metadata: {'provider': data.provider.name, 'url': url});

    // Check if we have valid cookies for this domain
    final domain = Uri.parse(url).host;
    final storedCookies = await getCookies(domain);

    if (storedCookies != null && storedCookies.isNotEmpty) {
      _logger.info('Using stored cookies for automatic resolution',
          tag: 'DDoSHandler',
          metadata: {'cookieCount': storedCookies.length});

      // Add cookies to request and retry
      return true;
    }

    // User needs to manually verify
    _logger.info('Manual verification required',
        tag: 'DDoSHandler',
        metadata: {'provider': data.provider.name, 'challengeUrl': data.challengeUrl});

    return null;
  }

  /// Add cookies to a request
  void addCookiesToRequest(RequestOptions options, List<Cookie> cookies) {
    if (cookies.isNotEmpty) {
      final cookieString = cookies.map((c) => '${c.name}=${c.value}').join('; ');
      options.headers['cookie'] = cookieString;
      _logger.debug('Added cookies to request',
          tag: 'DDoSHandler',
          metadata: {'cookieCount': cookies.length});
    }
  }

  /// Extract cookies from response for storage
  List<Cookie> extractCookies(Response response) {
    final cookies = <Cookie>[];
    
    // Get cookies from Set-Cookie header
    final setCookieHeaders = response.headers.map['set-cookie'];
    if (setCookieHeaders != null) {
      for (var header in setCookieHeaders) {
        try {
          final cookie = Cookie.fromSetCookieValue(header);
          cookies.add(cookie);
        } catch (e) {
          _logger.debug('Failed to parse Set-Cookie header',
              tag: 'DDoSHandler',
              metadata: {'header': header});
        }
      }
    }

    // Also check allCookies from dio
    for (var cookie in response.headers.allCookies) {
      if (!cookies.any((c) => c.name == cookie.name)) {
        cookies.add(cookie);
      }
    }

    return cookies;
  }
}

// Extension for Dio headers
extension DioHeadersExtension on Headers {
  /// Get all cookies from response headers
  List<Cookie> get allCookies {
    final cookies = <Cookie>[];
    final setCookieHeaders = map['set-cookie'];
    
    if (setCookieHeaders != null) {
      for (var header in setCookieHeaders) {
        try {
          final cookie = Cookie.fromSetCookieValue(header);
          cookies.add(cookie);
        } catch (e) {
          // Skip invalid cookies
        }
      }
    }
    
    return cookies;
  }
}
