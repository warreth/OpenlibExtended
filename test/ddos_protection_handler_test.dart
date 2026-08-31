// Tests the real cookie persistence of DDoSProtectionHandler: cookies captured
// by the embedded webviews are stored per domain and survive retrieval.
// (Cookie replay into Dio is intentionally NOT part of this API - it never
// works against DDoS-Guard; see the handler's documentation.)

// Dart imports:
import 'dart:io';

// Package imports:
import 'package:flutter_test/flutter_test.dart';
import 'package:dio/dio.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

// Project imports:
import 'package:openlib/services/ddos_protection_handler.dart';

class _FakePathProvider extends PathProviderPlatform {
  Future<String> _dir(String name) async {
    final dir = Directory('/tmp/openlib_ddos_test/$name');
    await dir.create(recursive: true);
    return dir.path;
  }

  @override
  Future<String?> getApplicationSupportPath() => _dir('support');

  @override
  Future<String?> getApplicationDocumentsPath() => _dir('documents');

  @override
  Future<String?> getTemporaryPath() => _dir('temp');

  @override
  Future<String?> getLibraryPath() => _dir('library');
}

void main() {
  setUpAll(() {
    if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      PathProviderPlatform.instance = _FakePathProvider();
    }
  });

  group('DDoSProtectionHandler cookie persistence', () {
    test('cookies stored by the webview round-trip per domain', () async {
      final handler = DDoSProtectionHandler();
      final domain = 'annas-archive.test';

      await handler.clearCookies(domain);

      await handler.storeCookies(domain, [
        Cookie('ddg_id', 'test_token_123'),
        Cookie('session_id', 'sess_abc'),
      ]);

      final retrieved = await handler.getCookies(domain);
      expect(retrieved, isNotNull);
      expect(retrieved!.length, equals(2));
      expect(retrieved.any((c) => c.name == 'ddg_id' && c.value == 'test_token_123'),
          isTrue);

      await handler.clearCookies(domain);
      expect(await handler.getCookies(domain), isNull);
    });

    test('extractCookies parses real Set-Cookie headers', () {
      final handler = DDoSProtectionHandler();
      final response = Response(
        requestOptions: RequestOptions(path: 'https://annas-archive.pk'),
        statusCode: 200,
        headers: Headers.fromMap({
          'set-cookie': [
            'ddg_id=abc123xyz; Path=/; Domain=.annas-archive.pk; HttpOnly; Secure',
            'session_id=sess_456; Path=/',
          ],
        }),
      );

      final cookies = handler.extractCookies(response);
      expect(cookies.length, equals(2));
      expect(cookies.firstWhere((c) => c.name == 'ddg_id').value,
          equals('abc123xyz'));
      expect(cookies.any((c) => c.name == 'session_id'), isTrue);
    });

    test('extractCookies skips malformed Set-Cookie headers', () {
      final handler = DDoSProtectionHandler();
      final response = Response(
        requestOptions: RequestOptions(path: 'https://annas-archive.pk'),
        statusCode: 200,
        headers: Headers.fromMap({
          'set-cookie': ['this is not a valid cookie header at all'],
        }),
      );

      expect(handler.extractCookies(response), isEmpty);
    });
  });
}
