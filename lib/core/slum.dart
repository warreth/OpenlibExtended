// Pure-Dart SLUM (open-slum.org) model and parser shared by the app and CLI.
//
// Nothing in this file may import Flutter: the CLI runs in a plain `dart`
// process.

// Package imports:
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

/// The one host the app and CLI are allowed to hardcode: the monitor itself.
const String slumDefaultBaseUrl = 'https://open-slum.org';

/// Which shadow-library family a mirror belongs to.
enum MirrorService {
  annasArchive,
  libgen,
  zlibrary,

  /// WeLib (open-slum.org's "other" page). Its search sits behind
  /// Cloudflare, so it is the last-resort source.
  welib,
}

/// What open-slum.org last saw for a mirror.
enum SlumStatus { up, protected, degraded, down, unknown }

/// The bot-protection gate a mirror sits behind, ordered from easiest to
/// hardest to pass without a browser.
enum Protection { none, diamwall, ddosGuard, cloudflare, unknown }

extension ProtectionRank on Protection {
  /// Lower is tried first. Exposed so ordering lives in one place.
  int get rank => switch (this) {
        Protection.none => 0,
        Protection.diamwall => 1,
        Protection.ddosGuard => 2,
        Protection.cloudflare => 3,
        Protection.unknown => 4,
      };

  /// Label for the settings UI.
  String get label => switch (this) {
        Protection.none => 'Unprotected',
        Protection.diamwall => 'DiamWall',
        Protection.ddosGuard => 'DDoS-Guard',
        Protection.cloudflare => 'Cloudflare',
        Protection.unknown => 'Unknown',
      };

  /// True when a plain Dio client has any chance without a browser.
  bool get solvableHeadless =>
      this == Protection.none || this == Protection.diamwall;
}

/// One mirror as open-slum.org reports it.
class SlumSite {
  final MirrorService service;
  final String url;

  /// Bare host, e.g. `z-lib.gd`. The stable key for user preferences.
  final String host;

  final SlumStatus status;
  final Protection protection;

  /// HTTP status SLUM's last check received (null when it could not
  /// connect at all).
  final int? httpStatus;

  /// SLUM's measured latency in milliseconds.
  final int? latencyMs;

  const SlumSite({
    required this.service,
    required this.url,
    required this.host,
    required this.status,
    required this.protection,
    this.httpStatus,
    this.latencyMs,
  });

  /// SLUM says it is down: never search or download on it.
  bool get isDown => status == SlumStatus.down;

  /// A mirror we may attempt: not down. `unknown` is attempted last -
  /// SLUM simply has no reading, which is not the same as down.
  bool get isAttemptable => !isDown;

  /// Sort key inside auto mode. Down mirrors sort last so a stable
  /// order still exists when a caller asks for "everything".
  int get statusTier => switch (status) {
        SlumStatus.up => 0,
        SlumStatus.degraded => 1,
        SlumStatus.protected => 2,
        SlumStatus.unknown => 3,
        SlumStatus.down => 9,
      };

  @override
  String toString() => 'SlumSite($host, ${status.name}, ${protection.name})';
}

/// Adds the scheme when missing and strips the trailing slash, so callers
/// can join paths directly.
String normalizeSlumUrl(String href) {
  var url = href.trim();
  if (!url.startsWith('http://') && !url.startsWith('https://')) {
    url = 'https://$url';
  }
  while (url.endsWith('/')) {
    url = url.substring(0, url.length - 1);
  }
  return url;
}

/// Parses one SLUM service page.
///
/// Each page lists `<div class="card" id="service.host">` blocks with a
/// `card-title` link, a `status-badge <status>` and - for gated mirrors - a
/// "Protected Site" block naming the vendor.
List<SlumSite> parseSlumPage(
  String html, {
  required MirrorService service,
  Set<String> skipHosts = const {},
}) {
  final document = html_parser.parse(html);
  final sites = <SlumSite>[];

  for (final card in document.querySelectorAll('div.card[id]')) {
    final link = card.querySelector('a.card-title');
    final href = link?.attributes['href'];
    if (href == null || href.isEmpty) continue;

    final uri = Uri.tryParse(href);
    final host = uri?.host;
    if (host == null || host.isEmpty) continue;

    // The "other" page mixes WeLib with unrelated libraries; only the
    // service's own hosts become mirrors.
    if (service == MirrorService.welib) {
      if (!host.contains('welib') || skipHosts.contains(host)) continue;
    }

    final status = _parseStatus(card);
    final protection = _parseProtection(card, status);

    sites.add(SlumSite(
      service: service,
      url: normalizeSlumUrl(href),
      host: host,
      status: status,
      protection: protection,
      httpStatus: _parseIntAfterLabel(card, 'Status:'),
      latencyMs: _parseIntAfterLabel(card, 'Latency:'),
    ));
  }

  return sites;
}

/// The badge class carries the current status (`status-badge down`).
/// Falls back to the last timeline reading when the badge is absent.
SlumStatus _parseStatus(dom.Element card) {
  final badge = card.querySelector('.status-badge');
  final raw = badge?.attributes['class'] ?? '';
  final match =
      RegExp(r'\b(up|protected|degraded|down|unknown)\b', caseSensitive: false)
          .firstMatch(raw);
  final fromBadge = _statusFromWord(match?.group(1));
  if (fromBadge != null) return fromBadge;

  // Timeline readings are oldest first; the last one is the newest.
  final readings = card
      .querySelectorAll('[data-status]')
      .map((e) => e.attributes['data-status']);
  for (final value in readings.toList().reversed) {
    final parsed = _statusFromWord(value);
    if (parsed != null) return parsed;
  }
  return SlumStatus.unknown;
}

SlumStatus? _statusFromWord(String? word) => switch (word?.toLowerCase()) {
      'up' => SlumStatus.up,
      'protected' => SlumStatus.protected,
      'degraded' => SlumStatus.degraded,
      'down' => SlumStatus.down,
      'unknown' => SlumStatus.unknown,
      _ => null,
    };

/// The "Protected Site" block names the vendor. A protected mirror without a
/// vendor is [Protection.unknown]; an UP mirror has no gate.
Protection _parseProtection(dom.Element card, SlumStatus status) {
  final vendor = _vendorName(card);
  if (vendor != null) {
    final lower = vendor.toLowerCase();
    if (lower.contains('diamwall')) return Protection.diamwall;
    if (lower.contains('ddos')) return Protection.ddosGuard;
    if (lower.contains('cloudflare')) return Protection.cloudflare;
    return Protection.unknown;
  }
  // No vendor label: only claim "none" when SLUM saw it plain.
  return status == SlumStatus.up ? Protection.none : Protection.unknown;
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

/// Auto order: never-down mirrors first by protection difficulty
/// (unprotected -> DiamWall -> DDoS-Guard/Cloudflare -> unknown), then by
/// SLUM status, then by latency. Mirrors SLUM reports DOWN sort last
/// whatever their protection.
List<SlumSite> sortSlumSites(Iterable<SlumSite> sites) {
  final list = sites.toList();
  list.sort((a, b) {
    if (a.isDown != b.isDown) return a.isDown ? 1 : -1;
    final byProtection = a.protection.rank.compareTo(b.protection.rank);
    if (byProtection != 0) return byProtection;
    final byStatus = a.statusTier.compareTo(b.statusTier);
    if (byStatus != 0) return byStatus;
    final byLatency =
        (a.latencyMs ?? 1 << 30).compareTo(b.latencyMs ?? 1 << 30);
    if (byLatency != 0) return byLatency;
    return a.host.compareTo(b.host);
  });
  return list;
}
