// The SLUM health parser: open-slum.org is the only reliable way to
// know whether Cloudflare-protected mirrors are alive, so the parser
// must survive real-world markup. Fixture captured from the live page.

// Dart imports:
import 'dart:io';

// Flutter imports:
import 'package:flutter_test/flutter_test.dart';

// Project imports:
import 'package:openlib/services/slum_health_service.dart';

void main() {
  late String fixture;

  setUpAll(() {
    fixture = File('test/fixtures/slum_front_page.html').readAsStringSync();
  });

  test('parses statuses and hosts from the captured front page', () {
    final health = SlumHealthService().parseFrontPage(fixture);

    expect(health, isNotEmpty);

    // Known entries from the capture:
    expect(health['libgen.bz']!.status, SlumStatus.up);
    expect(health['libgen.vg']!.status, SlumStatus.up);
    expect(health['libgen.li']!.status, SlumStatus.degraded);
    expect(health['z-library.sk']!.status, SlumStatus.protected);
    expect(health['annas-archive.gl']!.status, SlumStatus.protected);
  });

  test('PROTECTED counts as reachable (Cloudflare-gated but alive)', () async {
    final health = SlumHealthService().parseFrontPage(fixture);
    final annas = health['annas-archive.gl']!;
    expect(annas.isReachable, isTrue,
        reason: 'a Cloudflare-gated mirror is up for real browsers');
  });

  test('unknown or foreign markup yields an empty map, not a crash', () {
    final health = SlumHealthService()
        .parseFrontPage('<html><body><p>maintenance</p></body></html>');
    expect(health, isEmpty);

    // A different site structure must not invent statuses.
    final partial = SlumHealthService().parseFrontPage(
        '<li class="domain-item-dense"><a href="https://x.example">'
        'x.example</a></li>');
    expect(partial, isEmpty,
        reason: 'entries without a status badge are ignored');
  });
}
