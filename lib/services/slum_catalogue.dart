// Dart imports:
import 'dart:async';
import 'dart:convert';

// Flutter imports:
import 'package:flutter/foundation.dart';

// Package imports:
import 'package:dio/dio.dart';

// Project imports:
import 'package:openlib/services/logger.dart';
import 'package:openlib/services/preference_store.dart';

import 'package:openlib/core/slum.dart';
export 'package:openlib/core/slum.dart';

/// Reads mirror lists and their status from open-slum.org.
///
/// This is the **only** place mirror URLs come from: nothing else in
/// the app hardcodes a libgen/zlib/AA/welib host. SLUM publishes one
/// static HTML page per service:
///
///   annas.html     -> Anna's Archive mirrors
///   libgen.html    -> Library Genesis mirrors
///   zlibrary.html  -> Z-Library mirrors
///   other.html     -> WeLib and friends
///
/// Each page lists `<div class="card" id="service.host">` blocks with a
/// `card-title` link (the URL), a `status-badge <status>` and - for
/// gated mirrors - a "Protected Site" block naming the vendor
/// (Cloudflare / DiamWall / DDoS-Guard).
///
/// Everything is cached in memory for [ttl] and persisted, so a cold
/// start with SLUM unreachable still knows the last known mirrors. When
/// SLUM cannot be reached *and* nothing is cached the list is empty -
/// the app then reports "no mirrors" instead of guessing a URL.
class SlumCatalogue {
  SlumCatalogue({Dio? dio, PreferenceStore? store, String? baseUrl})
      : _dio = dio ??
            createDioWithLogging(
                options: BaseOptions(
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 20),
              headers: const {
                'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
                    'AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0 '
                    'Safari/537.36',
              },
            )),
        _store = store,
        _baseUrl = baseUrl ?? defaultBaseUrl;

  final Dio _dio;
  final PreferenceStore? _store;
  final String _baseUrl;

  /// The one URL the app is allowed to hardcode: the monitor itself.
  static const String defaultBaseUrl = 'https://open-slum.org';

  /// Kept as `baseUrl` for callers that only ever read it.
  static const String baseUrl = defaultBaseUrl;

  /// Page per service. `welib` lives on SLUM's "other" page.
  static const Map<MirrorService, String> pages = {
    MirrorService.annasArchive: 'annas.html',
    MirrorService.libgen: 'libgen.html',
    MirrorService.zlibrary: 'zlibrary.html',
    MirrorService.welib: 'other.html',
  };

  /// Hosts on the "other" page that are not WeLib. Kept explicit so a
  /// new entrant on that page does not silently become a provider.
  static const Set<String> _otherPageSkipHosts = {
    'libstc.nexus',
    'liber3.eth.limo',
    'library.memoryoftheworld.org',
  };

  /// How long a fetched catalogue stays fresh.
  static const Duration ttl = Duration(minutes: 10);

  static const String _cacheKey = 'slum_catalogue_cache';

  Map<MirrorService, List<SlumSite>> _cache = {};
  DateTime? _fetchedAt;

  /// When the last fetch attempt started. Used to throttle retries after
  /// a fetch that produced nothing at all.
  DateTime? _lastAttemptAt;

  /// True when the most recent fetch got at least one mirror (from SLUM
  /// or carried over from cache). The Mirrors page uses it to tell
  /// "nothing changed" apart from "SLUM was unreachable".
  bool get lastFetchSucceeded => _lastFetchSucceeded;
  bool _lastFetchSucceeded = true;

  /// How long to wait before trying SLUM again after a fetch yielded
  /// nothing. Long enough that an outage does not turn every provider
  /// call into four requests, short enough that the user does not stare
  /// at an empty list for the whole [ttl].
  static const Duration _retryAfterFailedFetch = Duration(seconds: 30);

  bool get _isFresh =>
      _fetchedAt != null && DateTime.now().difference(_fetchedAt!) < ttl;

  /// The mirrors of one service, in SLUM's page order. Ordering (see
  /// [SlumCatalogue.sortAuto]) is applied by [InstanceManager.instances].
  /// Returns an empty list when SLUM is unreachable and nothing is cached.
  Future<List<SlumSite>> sites(MirrorService service,
      {bool force = false}) async {
    final all = await fetchAll(force: force);
    return all[service] ?? const [];
  }

  /// Every service's mirrors, fetched in parallel. Cached for [ttl].
  ///
  /// A fetch that gets nothing at all (SLUM unreachable, cold start) is
  /// deliberately NOT counted as fresh: freshness would otherwise freeze
  /// the empty list for the whole [ttl]. Retries are throttled by
  /// [_retryAfterFailedFetch] instead, and a "Try Again"/refresh passes
  /// `force: true`.
  Future<Map<MirrorService, List<SlumSite>>> fetchAll(
      {bool force = false}) async {
    if (!force && _isFresh) return _cache;

    final nothingKnown = _cache.values.every((sites) => sites.isEmpty);
    if (!force &&
        nothingKnown &&
        _lastAttemptAt != null &&
        DateTime.now().difference(_lastAttemptAt!) < _retryAfterFailedFetch) {
      return _cache;
    }
    _lastAttemptAt = DateTime.now();

    final results = await Future.wait([
      for (final service in MirrorService.values) _fetchOne(service),
    ]);

    final merged = <MirrorService, List<SlumSite>>{};
    for (var i = 0; i < MirrorService.values.length; i++) {
      final service = MirrorService.values[i];
      final sites = results[i];
      // Keep the previous list for a service SLUM failed on; an empty
      // fetch must not wipe mirrors we already know.
      if (sites.isNotEmpty || !_cache.containsKey(service)) {
        merged[service] = sites;
      } else {
        merged[service] = _cache[service]!;
      }
    }

    _cache = merged;
    final gotAnything = merged.values.any((sites) => sites.isNotEmpty);
    _lastFetchSucceeded = gotAnything;
    _fetchedAt = gotAnything ? DateTime.now() : null;
    await _persist(merged);
    return _cache;
  }

  /// Fetches and parses one service page. Empty on any failure or when
  /// the page parses to nothing - the caller decides whether to keep
  /// the previous list.
  Future<List<SlumSite>> _fetchOne(MirrorService service) async {
    final page = pages[service];
    if (page == null) return const [];
    try {
      final response = await _dio.get<String>('$_baseUrl/$page');
      if (response.statusCode != 200 || response.data == null) {
        AppLogger().warning('open-slum page answered a non-200',
            tag: 'SlumCatalogue',
            metadata: {'service': service.name, 'status': response.statusCode});
        return const [];
      }
      final sites = parsePage(response.data!, service);
      AppLogger().info('open-slum: ${sites.length} ${service.name} mirrors',
          tag: 'SlumCatalogue');
      return sites;
    } catch (e) {
      AppLogger().warning('open-slum page unreachable, using cache',
          tag: 'SlumCatalogue', error: e, metadata: {'service': service.name});
      return const [];
    }
  }

  /// Parses one SLUM service page. Public so tests (and the persisted
  /// cache) can feed captured HTML without network.
  @visibleForTesting
  List<SlumSite> parsePage(String html, MirrorService service) {
    return parseSlumPage(html,
        service: service, skipHosts: _otherPageSkipHosts);
  }

  /// Auto order: never-down mirrors first by protection difficulty
  /// (unprotected -> DiamWall -> DDoS-Guard/Cloudflare -> unknown), then
  /// by SLUM status, then by latency. Mirrors SLUM reports DOWN sort
  /// last whatever their protection - they are never attempted - and
  /// callers that must not touch them filter with [SlumSite.isDown].
  static List<SlumSite> sortAuto(Iterable<SlumSite> sites) =>
      sortSlumSites(sites);

  // ------------------------------------------------------------------
  // Persistence: the last good catalogue survives restarts and lets a
  // cold start with SLUM unreachable still find mirrors.
  // ------------------------------------------------------------------

  Future<void> _persist(Map<MirrorService, List<SlumSite>> all) async {
    final store = _store;
    if (store == null) return;
    try {
      final json = {
        for (final entry in all.entries)
          entry.key.name: [for (final site in entry.value) _siteToJson(site)],
      };
      await store.write(_cacheKey, jsonEncode(json));
    } catch (_) {
      // Persistence is best-effort; the in-memory cache already has it.
    }
  }

  /// Loads the persisted catalogue into the cache. Called once at
  /// startup so the first search does not depend on SLUM being up.
  Future<void> restore() async {
    final store = _store;
    if (store == null) return;
    try {
      final raw = await store.read(_cacheKey);
      if (raw is! String || raw.isEmpty) return;
      final decoded = jsonDecode(raw) as Map<String, dynamic>;

      final restored = <MirrorService, List<SlumSite>>{};
      for (final service in MirrorService.values) {
        final list = decoded[service.name];
        if (list is! List) continue;
        restored[service] = [
          for (final item in list)
            if (item is Map<String, dynamic>) _siteFromJson(item, service),
        ];
      }
      if (restored.isNotEmpty && _cache.isEmpty) {
        _cache = restored;
        // Deliberately leave _fetchedAt null: persisted data is a
        // fallback, not a fresh reading, so the next fetch still runs.
      }
    } catch (_) {
      // A corrupt cache is simply ignored.
    }
  }

  Map<String, dynamic> _siteToJson(SlumSite site) => {
        'url': site.url,
        'host': site.host,
        'status': site.status.name,
        'protection': site.protection.name,
        'httpStatus': site.httpStatus,
        'latencyMs': site.latencyMs,
      };

  SlumSite _siteFromJson(Map<String, dynamic> json, MirrorService service) {
    SlumStatus status = SlumStatus.unknown;
    Protection protection = Protection.unknown;
    for (final value in SlumStatus.values) {
      if (value.name == json['status']) status = value;
    }
    for (final value in Protection.values) {
      if (value.name == json['protection']) protection = value;
    }
    final url = json['url'] as String? ?? '';
    return SlumSite(
      service: service,
      url: url,
      host: json['host'] as String? ?? Uri.tryParse(url)?.host ?? '',
      status: status,
      protection: protection,
      httpStatus: json['httpStatus'] as int?,
      latencyMs: json['latencyMs'] as int?,
    );
  }
}
