// Pins the download button's decision logic: a mirror's own refusal must
// reach the user instead of a download against the /dl/ hop it refused to
// resolve, and a fast link that bypasses that hop still wins.

// Flutter imports:
import 'package:flutter_test/flutter_test.dart';

// Project imports:
import 'package:openlib/services/download_target.dart';

void main() {
  group('chooseDownloadTarget', () {
    test('a refusal without any other route blocks the download', () {
      // The exact production shape: the result's /dl/<id> link is still
      // in hand, the mirror answered with its daily-limit page.
      final target = chooseDownloadTarget(
        url: 'https://z-lib.gd/dl/B39RQ6kmwG',
        fast: false,
        refusal: 'Daily download limit reached for this network.',
      );

      expect(target.hasUrl, isFalse,
          reason: 'a refused /dl/ hop must not be downloaded from');
      expect(target.url, isNull);
      expect(target.refusal, contains('Daily download limit'));
    });

    test('a re-resolved CDN link keeps the download going', () {
      final target = chooseDownloadTarget(
        url: 'https://dln1.ncdn.ec/general-files/xyz.pdf',
        fast: true,
      );

      expect(target.hasUrl, isTrue);
      expect(target.fast, isTrue);
      expect(target.refusal, isNull);
    });

    test('a donation-key fast link wins over a refusal', () {
      // The fast link goes around the mirror's own gate, so the refusal
      // is no longer the last word.
      final target = chooseDownloadTarget(
        url: 'https://annas-archive.gl/dyn/api/fast_download/xyz',
        fast: true,
        refusal: 'Daily download limit reached for this network.',
      );

      expect(target.hasUrl, isTrue);
      expect(target.url, contains('fast_download'));
      expect(target.refusal, isNull);
    });

    test('without a refusal the stored link is returned unchanged', () {
      // The resolution may also have failed for another reason (network
      // hiccup): the button keeps its old attempt-and-report behaviour.
      final target = chooseDownloadTarget(
        url: 'https://z-lib.gd/dl/m3EX0y8EgD',
        fast: false,
      );

      expect(target.url, 'https://z-lib.gd/dl/m3EX0y8EgD');
      expect(target.refusal, isNull);
    });

    test('nothing to download and nothing to explain', () {
      final target = chooseDownloadTarget(url: null, fast: false);
      expect(target.hasUrl, isFalse);
      expect(target.refusal, isNull,
          reason: 'the caller falls back to its generic message');
    });

    test('an empty url counts as no url', () {
      final target = chooseDownloadTarget(url: '', fast: false);
      expect(target.hasUrl, isFalse);
    });
  });

  group('isDirectFileUrl', () {
    test('libgen get.php is a file, not a page', () {
      // The exact shape the libgen book page hands the manual button.
      expect(
        isDirectFileUrl(
            'https://libgen.li/get.php?md5=7fa1933240367d50818e83f75867605e&key=HHTIQRL70FJI3D1U'),
        isTrue,
      );
    });

    test('pages a WebView can scrape are not direct files', () {
      expect(
        isDirectFileUrl('https://annas-archive.gl/slow_download/abc/0/0'),
        isFalse,
      );
      expect(isDirectFileUrl('https://z-lib.gd/dl/B39RQ6kmwG'), isFalse);
      expect(
        isDirectFileUrl(
            'https://libgen.li/ads.php?md5=7fa1933240367d50818e83f75867605e'),
        isFalse,
      );
    });

    test('get.php only counts as the path, not as a query value', () {
      expect(
        isDirectFileUrl('https://example.com/ads.php?next=/get.php'),
        isFalse,
      );
    });

    test('a get.php without an md5 is not a libgen download', () {
      expect(isDirectFileUrl('https://example.com/get.php'), isFalse);
      expect(isDirectFileUrl('https://example.com/get.php?key=abc'), isFalse);
    });

    test('null, empty and unparseable URLs are not direct files', () {
      expect(isDirectFileUrl(null), isFalse);
      expect(isDirectFileUrl(''), isFalse);
      expect(isDirectFileUrl('not a url'), isFalse);
    });
  });
}
