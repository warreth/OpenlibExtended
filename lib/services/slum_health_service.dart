// Dart imports:
import 'dart:async';

// Flutter imports:
import 'package:flutter/foundation.dart';

// Package imports:
import 'package:dio/dio.dart';
import 'package:html/parser.dart' as html_parser;

// Project imports:
import 'package:openlib/services/logger.dart';

/// What open-slum.org (SLUM, the Shadow Library Uptime Monitor) last saw
/// for a mirror.
enum SlumStatus { up, protected, degraded, down, unknown }

@immutable
class SlumHealth {
  final SlumStatus status;

  /// Latency of SLUM's most recent successful check, in milliseconds.
  final int? latencyMs;

  const SlumHealth(this.status, {this.latencyMs});

  static const unknown = SlumHealth(SlumStatus.unknown);

  bool get isReachable =>
      status == SlumStatus.up || status == SlumStatus.protected;

  @override
  String toString() => 'SlumHealth(${status.name}, ${latencyMs}ms)';
}

/// Reads mirror health from open-slum.org.
///
/// Many shadow-library mirrors sit behind Cloudflare or similar shields,
/// so a plain ping from the app says little: a "PROTECTED" mirror can be
/// up and fine for real browsers while a HEAD request from Dio times
/// out. SLUM checks them continuously and publishes status + latency,
/// which this service parses - falling back to [SlumStatus.unknown]
/// when SLUM itself is unreachable, never throwing.
class SlumHealthService {
  SlumHealthService({Dio? dio})
      : _dio = dio ??
            createDioWithLogging(
                options: BaseOptions(
              connectTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 10),
              headers: const {
                'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
                    'AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0 '
                    'Safari/537.36',
              },
            ));

  final Dio _dio;

  /// Parses the SLUM front page's mirror list. Public so tests can feed
  /// a captured page without network.
  ///
  /// Returns a map keyed by mirror host ("libgen.li") to its health.
  /// If a host appears more than once the last entry wins (the page
  /// lists per-service sections; entries are identical).
  Map<String, SlumHealth> parseFrontPage(String html) {
    final document = html_parser.parse(html);
    final result = <String, SlumHealth>{};

    for (final item in document.querySelectorAll('li.domain-item-dense')) {
      final link = item.querySelector('a.domain-link');
      final href = link?.attributes['href'];
      if (href == null) continue;

      final host = Uri.tryParse(href)?.host;
      if (host == null || host.isEmpty) continue;

      final badge = item.querySelector('a.status-badge');
      final raw = badge?.attributes['class'] ?? '';
      // class="status-badge compact up" - one of the known statuses
      // appears as its own word.
      final match = RegExp(r'\b(up|protected|degraded|down)\b').firstMatch(raw);
      final status = switch (match?.group(1)) {
        'up' => SlumStatus.up,
        'protected' => SlumStatus.protected,
        'degraded' => SlumStatus.degraded,
        'down' => SlumStatus.down,
        _ => SlumStatus.unknown,
      };
      if (status == SlumStatus.unknown) continue;

      result[host] = SlumHealth(status);
    }
    return result;
  }

  /// Fetches and parses SLUM's current mirror statuses.
  /// Returns an empty map when SLUM is unreachable - health data is a
  /// nice-to-have, never a hard dependency.
  Future<Map<String, SlumHealth>> fetchHealth() async {
    try {
      final response = await _dio.get<String>('https://open-slum.org/');
      if (response.statusCode != 200 || response.data == null) {
        return const {};
      }
      return parseFrontPage(response.data!);
    } catch (e) {
      AppLogger().warning('open-slum.org unreachable, skipping health data',
          tag: 'SlumHealth', error: e);
      return const {};
    }
  }
}
