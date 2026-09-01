// Dart imports:
import 'dart:typed_data';

// Flutter imports:
import 'package:flutter/foundation.dart';

// Package imports:
import 'package:crypto/crypto.dart' as crypto;
import 'package:dio/dio.dart';

/// Solves the DiamWall 503 proof-of-work gate used by Z-Library mirrors.
///
/// The 503 page embeds a SHA1 implementation plus an obfuscated script:
/// a 40-hex-char seed, a byte index `n1 = int(seed[0], 16)` derived from
/// the seed's first character, and a loop that increments `i` until
/// `SHA1(seed + i)` has bytes `0xB0` at index `n1` and `0x0B` at
/// `n1 + 1`. The script then sets cookies `c_token = seed + i` and
/// `c_time = <elapsed seconds>` and reloads. Solving it headlessly is
/// a few thousand SHA1 calls - well under a second on any device.
class DiamWallSolver {
  DiamWallSolver({Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 15),
              headers: const {
                'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
                    'AppleWebKit/537.36 (KHTML, like Gecko) '
                    'Chrome/125.0 Safari/537.36',
              },
            ));

  final Dio _dio;

  /// The Dio instance used for any network access the solver performs.
  Dio get dio => _dio;

  /// Upper bound on brute-force iterations so a malformed or adversarial
  /// page cannot spin the loop forever. The real challenge solves within
  /// a few hundred thousand iterations; 5M leaves generous headroom.
  static const maxIterations = 5000000;

  /// Markers checked against a lowercased copy of the page: the 503
  /// interstitial's title and the embedded solver script's cookie name.
  static const _titleMarker = 'checking your browser';
  static const _scriptMarker = 'c_token=';

  /// True when [statusCode]/[html] is the DiamWall 503 challenge page.
  /// The 503 status alone is conclusive; other statuses are checked by
  /// page markers so a cached/soft-challenge copy is still recognized.
  bool looksLikeChallenge(int statusCode, String html) {
    if (statusCode == 503) return true;
    final lower = html.toLowerCase();
    return lower.contains(_titleMarker) &&
        _seedPattern.hasMatch(lower) &&
        lower.contains(_scriptMarker);
  }

  /// 40-hex-char seed as embedded in the obfuscated array, e.g.
  /// `a0_0x2a54=['41422B67...','c_token=','array']`. Case-insensitive:
  /// the live page embeds uppercase hex.
  static final _seedPattern =
      RegExp(r"'([0-9a-fA-F]{40})'\s*,\s*'c_token='", caseSensitive: false);

  /// Parses the seed out of a challenge page, or null if absent.
  @visibleForTesting
  String? extractSeed(String html) => _seedPattern.firstMatch(html)?.group(1);

  /// Solves the proof-of-work embedded in [html] and returns the cookie
  /// map to attach to the retried request, or null when the page carries
  /// no seed, the seed is malformed, or the brute force hits
  /// [maxIterations] without a solution.
  ///
  /// Pure computation: no network, no clock dependency beyond `c_time`,
  /// which only needs to look like an elapsed-seconds value.
  Future<Map<String, String>?> solve(String html) {
    return compute(solveSync, html);
  }

  /// The actual brute force, isolated so it can run on another isolate
  /// and be unit-tested directly without spinning up `compute`.
  /// Static and public so tests can exercise it synchronously.
  static Map<String, String>? solveSync(String html) {
    final seed = _seedPattern.firstMatch(html)?.group(1);
    if (seed == null) return null;

    // n1 comes from the seed's first hex char; guard the +1 index against
    // a digest read past its 20-byte end.
    final n1 = int.tryParse('0x${seed[0]}') ?? -1;
    if (n1 < 0 || n1 + 1 >= 20) return null;

    final seedBytes = Uint8List.fromList(seed.codeUnits);
    final start = DateTime.now();
    for (var i = 0; i <= maxIterations; i++) {
      // SHA1 over seed + decimal counter, matching the page's JS:
      // s1.array(seed + i) with the counter as a plain decimal string.
      final input = BytesBuilder()
        ..add(seedBytes)
        ..add(i.toString().codeUnits);
      final digest = crypto.sha1.convert(input.takeBytes()).bytes;
      if (digest[n1] == 0xB0 && digest[n1 + 1] == 0x0B) {
        final elapsed =
            DateTime.now().difference(start).inMilliseconds / 1000.0;
        return {
          'c_token': '$seed$i',
          'c_time': elapsed.toStringAsFixed(3),
        };
      }
    }
    return null;
  }
}
