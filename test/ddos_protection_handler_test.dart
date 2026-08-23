import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:dio/dio.dart';
import 'package:openlib/services/ddos_protection_handler.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DDoSProtectionHandler Tests', () {
    late DDoSProtectionHandler handler;

    setUp(() {
      handler = DDoSProtectionHandler();
    });

    test('Detects Cloudflare challenge via cf-mitigated header', () {
      final response = Response(
        requestOptions: RequestOptions(path: 'https://annas-archive.pk/search'),
        statusCode: 403,
        headers: Headers.fromMap({
          'cf-mitigated': ['challenge'],
          'server': ['cloudflare'],
        }),
      );

      final protection = handler.detectProtection(response);
      expect(protection, isNotNull);
      expect(protection!.provider, equals(DDoSProvider.cloudflare));
    });

    test('Detects Cloudflare Turnstile in response body', () {
      final response = Response(
        requestOptions: RequestOptions(path: 'https://annas-archive.gl/search'),
        statusCode: 403,
        data: '<html><head><title>Just a moment...</title></head><body><div class="cf-turnstile"></div></body></html>',
        headers: Headers.fromMap({
          'content-type': ['text/html'],
        }),
      );

      final protection = handler.detectProtection(response);
      expect(protection, isNotNull);
      expect(protection!.provider, equals(DDoSProvider.cloudflare));
    });

    test('Detects DDoS-Guard in response body or headers', () {
      final response = Response(
        requestOptions: RequestOptions(path: 'https://annas-archive.gd/search'),
        statusCode: 403,
        data: '<html><body>Checking if the site connection is secure - DDoS-Guard</body></html>',
        headers: Headers.fromMap({
          'server': ['ddos-guard'],
        }),
      );

      final protection = handler.detectProtection(response);
      expect(protection, isNotNull);
      expect(protection!.provider, equals(DDoSProvider.ddosGuard));
    });

    test('Normal 200 response returns null protection', () {
      final response = Response(
        requestOptions: RequestOptions(path: 'https://annas-archive.pk/search'),
        statusCode: 200,
        data: '<html><body>Search results for books</body></html>',
        headers: Headers.fromMap({
          'content-type': ['text/html'],
        }),
      );

      final protection = handler.detectProtection(response);
      expect(protection, isNull);
    });

    test('Extracts cookies from Set-Cookie headers', () {
      final response = Response(
        requestOptions: RequestOptions(path: 'https://annas-archive.pk'),
        statusCode: 200,
        headers: Headers.fromMap({
          'set-cookie': [
            'cf_clearance=abc123xyz; Path=/; Domain=.annas-archive.pk; HttpOnly; Secure',
            'session_id=sess_456; Path=/',
          ],
        }),
      );

      final cookies = handler.extractCookies(response);
      expect(cookies.length, equals(2));
      expect(cookies.any((c) => c.name == 'cf_clearance'), isTrue);
      expect(cookies.firstWhere((c) => c.name == 'cf_clearance').value, equals('abc123xyz'));
      expect(cookies.any((c) => c.name == 'session_id'), isTrue);
    });

    test('addCookiesToRequest is no-op because cf_clearance is TLS-fingerprint bound', () {
      final requestOptions = RequestOptions(path: 'https://annas-archive.pk/search');
      final cookies = [
        Cookie('cf_clearance', 'token_valid_123'),
        Cookie('annas_session', 'sess_abc'),
      ];

      handler.addCookiesToRequest(requestOptions, cookies);

      // Cookies should NOT be added to headers (disabled due to TLS fingerprint mismatch)
      expect(requestOptions.headers['cookie'], isNull);
    });
  });
}
