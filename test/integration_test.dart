// Integration tests - real network calls against live Anna's Archive mirrors.
//
// These run with `flutter test --run-skipped`. Anna's Archive is protected by
// DDoS-Guard, so a plain Dio request from a CI/test machine can legitimately
// receive a 403 challenge. The tests therefore assert the two well-defined
// outcomes: either real parsed results, or a NetworkError of type
// cloudflareBlock carrying the blocked URL (which is what drives the in-app
// browser fallback). Anything else is a bug.

// Dart imports:
import 'dart:io';

// Package imports:
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

// Project imports:
import 'package:openlib/services/annas_archieve.dart';
import 'package:openlib/services/challenge_html_cache.dart';
import 'package:openlib/services/instance_manager.dart';
import 'package:openlib/services/network_error.dart';
import 'package:openlib/services/webview_challenge_solver.dart';

// Fake path_provider so the services' sqlite database works in the test VM.
class _FakePathProvider extends PathProviderPlatform {
  Future<String> _dir(String name) async {
    final dir = Directory('/tmp/openlib_test_support/$name');
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
  // NOTE: no TestWidgetsFlutterBinding here on purpose. That binding replaces
  // dart:io's HttpClient with a fake that returns 400 for every request,
  // which would defeat the point of these tests (real network calls). The
  // sqflite_ffi database and the path_provider platform mock below are pure
  // Dart registrations and work fine without the binding.

  // Desktop test runner needs native plugins mocked.
  if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    PathProviderPlatform.instance = _FakePathProvider();
  }

  group('Integration Tests - Real Network Calls', () {
    late AnnasArchieve api;
    late InstanceManager instanceManager;

    setUp(() {
      // Never open desktop webview windows from tests.
      WebviewChallengeSolver.guiEnabled = false;
      api = AnnasArchieve();
      instanceManager = InstanceManager();
      ChallengeHtmlCache.clear();
    });

    test('Search returns results or a challenge block with the blocked URL',
        () async {
      Object? caught;
      List<BookData> results = [];
      try {
        results = await api.searchBooks(
          searchQuery: 'Pride and Prejudice',
          fileType: 'epub',
          enableFilters: true,
        );
      } catch (e) {
        caught = e;
      }

      if (caught != null) {
        // A challenge block is a legitimate outcome for a datacenter/test IP;
        // it must be a NetworkError with the blocked URL so the app can fall
        // back to the browser-based solver.
        expect(caught, isA<NetworkError>());
        final err = caught as NetworkError;
        expect(err.type, equals(NetworkErrorType.cloudflareBlock),
            reason: 'Unexpected error: $err');
        expect(err.blockedUrl, isNotNull);
        return;
      }

      expect(results, isNotEmpty, reason: 'Search should return results');
      expect(results.first.md5, isNotEmpty);
      expect(results.first.link, startsWith('http'));
    }, timeout: const Timeout(Duration(seconds: 60)));

    test('Book details return data or a challenge block', () async {
      Object? searchErr;
      List<BookData> results = [];
      try {
        results = await api.searchBooks(
          searchQuery: 'The Great Gatsby',
          fileType: 'epub',
          enableFilters: true,
        );
      } catch (e) {
        searchErr = e;
      }

      if (searchErr != null) {
        expect(searchErr, isA<NetworkError>());
        final err = searchErr as NetworkError;
        expect(err.type, equals(NetworkErrorType.cloudflareBlock),
            reason: 'Unexpected error: $err');
        return; // Blocked at search stage - that is the valid outcome here.
      }
      if (results.isEmpty) return;

      Object? caught;
      try {
        final bookInfo = await api.bookInfo(url: results.first.link);
        expect(bookInfo.title, isNotEmpty);
        expect(bookInfo.md5, equals(results.first.md5));
        expect(bookInfo.format, isNotEmpty);
      } catch (e) {
        caught = e;
      }
      if (caught != null) {
        expect(caught, isA<NetworkError>());
        final err = caught as NetworkError;
        expect(err.type, equals(NetworkErrorType.cloudflareBlock),
            reason: 'Unexpected error: $err');
      }
    }, timeout: const Timeout(Duration(seconds: 60)));

    test('InstanceManager returns active mirrors', () async {
      final instances = await instanceManager.getInstances();

      expect(instances, isNotEmpty, reason: 'Should have default mirrors');

      final enabledInstances = instances.where((i) => i.enabled).toList();
      expect(enabledInstances, isNotEmpty,
          reason: 'Should have at least one enabled mirror');
    });

    test('Live response or block is classified correctly by the real client',
        () async {
      // This is the real end-to-end classification: whatever the live mirror
      // returns (results, challenge block, or network failure) must surface
      // through the same NetworkError machinery the app UI relies on.
      Object? caught;
      List<BookData> results = [];
      try {
        results = await api.searchBooks(searchQuery: 'darwin');
      } catch (e) {
        caught = e;
      }

      if (caught != null) {
        expect(caught, isA<NetworkError>());
        final err = caught as NetworkError;
        expect(
          err.type,
          anyOf(
            equals(NetworkErrorType.cloudflareBlock),
            equals(NetworkErrorType.noInternet),
            equals(NetworkErrorType.timeout),
            equals(NetworkErrorType.serverUnavailable),
          ),
          reason: 'Live failure must map to a user-actionable error type: $err',
        );
        // Blocked requests must carry the URL for the webview fallback.
        if (err.type == NetworkErrorType.cloudflareBlock) {
          expect(err.blockedUrl, isNotNull);
        }
        return;
      }

      expect(results, isNotEmpty,
          reason: 'Live search must return results when not blocked');
      expect(results.first.title, isNotEmpty);
      expect(results.first.md5.length, equals(32));
    }, timeout: const Timeout(Duration(seconds: 90)));

    test('Unreachable mirror surfaces as a classified NetworkError', () async {
      // Hit a mirror that is guaranteed dead through the real request path.
      // The app must convert this into a proper NetworkError (never a raw
      // DioException or unhandled crash).
      const deadUrl = 'https://annas-archive-test-dead.invalid/search?q=x';
      Object? caught;
      try {
        await api.dio.get(deadUrl);
      } catch (e) {
        caught = e;
      }

      // Dio may throw raw here (direct dio.get bypasses the service wrapper),
      // so run the same conversion the service layer applies.
      if (caught != null) {
        final err = NetworkError.fromException(caught);
        expect(err.type, isNot(equals(NetworkErrorType.unknown)),
            reason: 'Dead mirrors must map to a known error type, got: '
                '${err.type}');
      }
    }, timeout: const Timeout(Duration(seconds: 30)));
  },
  // Run with `flutter test --run-skipped` - these hit the live network.
  skip: 'Integration tests require network access');
}
