// Dart imports:
import 'dart:io';

// Package imports:
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

// Project imports:
import 'package:openlib/services/database.dart';
import 'package:openlib/services/upgrade_detector.dart';
import 'package:openlib/services/search_manager.dart';

class _FakePathProvider extends PathProviderPlatform {
  Future<String> _dir(String name) async {
    final dir = Directory('/tmp/openlib_upgrade_test/$name');
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
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      PathProviderPlatform.instance = _FakePathProvider();
    }
  });

  group('compareVersions', () {
    test('orders dot-separated versions numerically, not lexically', () {
      expect(UpgradeDetector.compareVersions('1.0.9', '1.0.10'), lessThan(0));
      expect(UpgradeDetector.compareVersions('1.2', '1.2.0'), 0);
      expect(UpgradeDetector.compareVersions('2.0', '1.9.9'), greaterThan(0));
      expect(UpgradeDetector.compareVersions('1.0.11', '1.0.11'), 0);
    });
  });

  group('checkAndRecord (real local database)', () {
    test('first install records the version but is not an upgrade', () async {
      final detector = UpgradeDetector(versionOf: () async => '1.0.11');

      final check = await detector.checkAndRecord();

      expect(check.isUpgrade, isFalse);
      expect(check.fromVersion, '');
      expect(check.toVersion, '1.0.11');

      // And the baseline is stored for the next launch.
      final stored =
          await MyLibraryDb.instance.getPreference('lastRunVersion');
      expect(stored, '1.0.11');
    });

    test('a stored older version counts as an upgrade and is re-recorded',
        () async {
      await MyLibraryDb.instance.savePreference('lastRunVersion', '1.0.9');
      final detector = UpgradeDetector(versionOf: () async => '1.0.11');

      final check = await detector.checkAndRecord();

      expect(check.isUpgrade, isTrue);
      expect(check.fromVersion, '1.0.9');
      expect(check.toVersion, '1.0.11');

      // Second launch on the same version is no longer an upgrade.
      final again = await UpgradeDetector(versionOf: () async => '1.0.11')
          .checkAndRecord();
      expect(again.isUpgrade, isFalse);
    });

    test('a downgrade is not an upgrade', () async {
      await MyLibraryDb.instance.savePreference('lastRunVersion', '2.0.0');
      final detector = UpgradeDetector(versionOf: () async => '1.0.11');

      expect((await detector.checkAndRecord()).isUpgrade, isFalse);
    });
  });

  group('SearchManager.enableAllProviders', () {
    test('turns every provider back on from a stale toggle list', () async {
      final manager = SearchManager();
      // Old install left only Anna's enabled.
      await MyLibraryDb.instance
          .savePreference('searchProviders', 'annasArchive');
      expect((await manager.enabledProviders()).length, 1);

      await manager.enableAllProviders();

      final enabled = await manager.enabledProviders();
      expect(enabled, containsAll(SearchProviderId.values));
    });
  });
}
