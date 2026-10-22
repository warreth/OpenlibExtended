// Dart imports:
import 'dart:async';

// Package imports:
import 'package:dio/dio.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

/// What open-slum.org (SLUM) last saw for a mirror.
///
/// Mirrors the app-side enum in `lib/services/slum_catalogue.dart`. The
/// CLI cannot import that file (it transitively depends on Flutter), so
/// the few values it needs are re-declared here. Keep both in sync.
enum CliSlumStatus { up, protected_, degraded, down, unknown }

/// The bot-protection gate a mirror sits behind, ordered from easiest to
/// hardest to pass without a browser. Same contract as the app-side
/// `Protection` enum: `none` and `diamwall` are the only ones a plain
/// HTTP client has any chance against.
enum CliProtection { none, diamwall, ddosGuard, cloudflare, unknown }

extension CliProtectionRank on CliProtection {
  /// Lower is tried first.
  int get rank => switch (this) {
        CliProtection.none => 0,
        CliProtection.diamwall => 1,
        CliProtection.ddosGuard => 2,
        CliProtection.cloudflare => 3,
        CliProtection.unknown => 4,
      };
}

/// One Anna's Archive mirror as open-slum.org reports it.
class CliSlumSite {
  final String url;
  final String host;
  final CliSlumStatus status;
  final CliProtection protection;
  final int? httpStatus;
  final int? latencyMs;

  const CliSlumSite({
    required this.url,
    required this.host,
    required this.status,
    required this.protection,
    this.httpStatus,
    this.latencyMs,
  });

  /// SLUM says it is down: never search or download on it.
  bool get isDown => status == CliSlumStatus.down;

  /// Sort key: up first, down last. Same tiers as the app side.
  int get statusTier => switch (status) {
        CliSlumStatus.up => 0,
        CliSlumStatus.degraded => 1,
        CliSlumStatus.protected_ => 2,
        CliSlumStatus.unknown => 3,
        CliSlumStatus.down => 9,
      };

  Map<String, dynamic> toJson() => {
        'url': url,
        'host': host,
        'status': status.name.replaceAll('_', ''),
        'protection': protection.name,
        if (httpStatus != null) 'http_status': httpStatus,
        if (latencyMs != null) 'latency_ms': latencyMs,
      };
}

/// Reads the Anna's Archive mirror list from open-slum.org.
///
/// The app rule is "mirror URLs come only from open-slum.org - nothing
/// hardcodes a provider host". This class keeps that rule for the CLI.
/// Like the app it degrades honestly: when SLUM is unreachable the list
/// is empty and the caller reports that instead of guessing a URL.
class CliSlumCatalogue {
  CliSlumCatalogue({Dio? dio, String? baseUrl})
      : _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 20),
              headers: const {
                'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
                    'AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0 '
                    'Safari/537.36',
              },
            )),
        _baseUrl = baseUrl ?? defaultBaseUrl;

  final Dio _dio;
  final String _baseUrl;

  /// The one host the CLI is allowed to hardcode: the monitor itself.
  static const String defaultBaseUrl = 'https://open-slum.org';

  /// SLUM's Anna's Archive page.
  static const String annasPage = 'annas.html';

  /// Fetches the Anna's Archive mirror list, ordered the way the app
  /// orders it: not-down before down, then protection rank, then SLUM's
  /// own page order. Empty on any failure.
  Future<List<CliSlumSite>> fetchAnnasMirrors() async {
    try {
      final response =
          await _dio.get<String>('$_baseUrl/$annasPage');
      if (response.statusCode != 200 || response.data == null) {
        return const [];
      }
      final sites = parsePage(response.data!);
      final attemptable =
          sites.where((site) => !site.isDown).toList()
            ..sort((a, b) {
              final byTier = a.statusTier.compareTo(b.statusTier);
              if (byTier != 0) return byTier;
              final byProtection =
                  a.protection.rank.compareTo(b.protection.rank);
              if (byProtection != 0) return byProtection;
              return 0; // keep SLUM's page order inside a tier
            });
      return attemptable;
    } catch (_) {
      return const [];
    }
  }

  /// Parses one SLUM service page. Mirrors the app-side parser
  /// (`div.card[id]` blocks with a `card-title` link and a
  /// `status-badge <status>` class).
  List<CliSlumSite> parsePage(String html) {
    final document = html_parser.parse(html);
    final sites = <CliSlumSite>[];

    for (final card in document.querySelectorAll('div.card[id]')) {
      final link = card.querySelector('a.card-title');
      final href = link?.attributes['href'];
      if (href == null || href.isEmpty) continue;

      final uri = Uri.tryParse(href);
      final host = uri?.host;
      if (host == null || host.isEmpty) continue;

      final status = _parseStatus(card);
      final protection = _parseProtection(card, status);

      sites.add(CliSlumSite(
        url: normalizeUrl(href),
        host: host,
        status: status,
        protection: protection,
        httpStatus: _parseIntAfterLabel(card, 'Status:'),
        latencyMs: _parseIntAfterLabel(card, 'Latency:'),
      ));
    }

    return sites;
  }

  CliSlumStatus _parseStatus(dom.Element card) {
    final badge = card.querySelector('.status-badge');
    final raw = badge?.attributes['class'] ?? '';
    final match = RegExp(r'\b(up|protected|degraded|down|unknown)\b',
            caseSensitive: false)
        .firstMatch(raw);
    final fromBadge = _statusFromWord(match?.group(1));
    if (fromBadge != null) return fromBadge;

    final readings = card
        .querySelectorAll('[data-status]')
        .map((e) => e.attributes['data-status']);
    for (final value in readings.toList().reversed) {
      final parsed = _statusFromWord(value);
      if (parsed != null) return parsed;
    }
    return CliSlumStatus.unknown;
  }

  CliSlumStatus? _statusFromWord(String? word) => switch (word?.toLowerCase()) {
        'up' => CliSlumStatus.up,
        'protected' => CliSlumStatus.protected_,
        'degraded' => CliSlumStatus.degraded,
        'down' => CliSlumStatus.down,
        'unknown' => CliSlumStatus.unknown,
        _ => null,
      };

  CliProtection _parseProtection(dom.Element card, CliSlumStatus status) {
    final vendor = _vendorName(card);
    if (vendor != null) {
      final lower = vendor.toLowerCase();
      if (lower.contains('diamwall')) return CliProtection.diamwall;
      if (lower.contains('ddos')) return CliProtection.ddosGuard;
      if (lower.contains('cloudflare')) return CliProtection.cloudflare;
      return CliProtection.unknown;
    }
    return status == CliSlumStatus.up
        ? CliProtection.none
        : CliProtection.unknown;
  }

  String? _vendorName(dom.Element card) {
    for (final strong in card.querySelectorAll('strong')) {
      if (strong.text.trim().toLowerCase().contains('protected site')) {
        final span = strong.nextElementSibling;
        final name = span?.text.trim() ?? '';
        if (name.isNotEmpty) return name;
      }
    }
    return null;
  }

  int? _parseIntAfterLabel(dom.Element card, String label) {
    for (final div in card.querySelectorAll('div')) {
      final text = div.text;
      final index = text.indexOf(label);
      if (index == -1) continue;
      final match =
          RegExp(r'\d+').firstMatch(text.substring(index + label.length));
      if (match != null) return int.tryParse(match.group(0)!);
    }
    return null;
  }

  /// Adds the scheme when missing and strips the trailing slash, so
  /// callers can join paths directly.
  static String normalizeUrl(String href) {
    var url = href.trim();
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      url = 'https://$url';
    }
    while (url.endsWith('/')) {
      url = url.substring(0, url.length - 1);
    }
    return url;
  }
}
