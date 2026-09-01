import 'dart:io';

// Package imports:
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

// Project imports:
import 'package:openlib/services/database.dart';
import 'package:openlib/services/instance_manager.dart';

// Desktop test runner needs the sqlite plugin faked; the app itself uses the
// platform plugin. These tests exercise the real InstanceManager logic
// (defaults, cleanup, custom instances) against a real local database.
class _FakePathProvider extends PathProviderPlatform {
  Future<String> _dir(String name) async {
    final dir = Directory('/tmp/openlib_instance_test/$name');
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

  group('ArchiveInstance model', () {
    test('serialization round-trips all fields', () {
      final instance = ArchiveInstance(
        id: 'libgen_li',
        name: 'LibGen (.li)',
        baseUrl: 'https://libgen.li',
        service: MirrorService.libgen,
        priority: 1,
        enabled: true,
        isCustom: false,
      );

      final parsed = ArchiveInstance.fromJson(instance.toJson());
      expect(parsed.id, equals(instance.id));
      expect(parsed.name, equals(instance.name));
      expect(parsed.baseUrl, equals(instance.baseUrl));
      expect(parsed.service, equals(MirrorService.libgen));
      expect(parsed.priority, equals(instance.priority));
      expect(parsed.enabled, equals(instance.enabled));
      expect(parsed.isCustom, equals(instance.isCustom));
    });

    test('copyWith only changes the given fields', () {
      final instance = ArchiveInstance(
        id: 'annas_archive_gl',
        name: "Anna's Archive (.gl)",
        baseUrl: 'https://annas-archive.gl',
        service: MirrorService.annasArchive,
        priority: 2,
        enabled: true,
      );

      final modified = instance.copyWith(priority: 5, enabled: false);
      expect(modified.id, equals('annas_archive_gl'));
      expect(modified.name, equals(instance.name));
      expect(modified.baseUrl, equals(instance.baseUrl));
      expect(modified.priority, equals(5));
      expect(modified.enabled, isFalse);
    });
  });

  group('InstanceManager persistence (real local database)', () {
    test('getInstances initializes with the current default mirrors', () async {
      final manager = InstanceManager();
      final instances = await manager.getInstances();

      // The defaults are the mirrors the app actually ships with today.
      final ids = instances.map((i) => i.id).toSet();
      expect(
          ids,
          containsAll(
              ['annas_archive_gl', 'annas_archive_pk', 'annas_archive_gd']));
      expect(instances.every((i) => i.baseUrl.startsWith('https://')), isTrue);
    });

    test('custom instances persist and defaults cannot be removed', () async {
      final manager = InstanceManager();

      await manager.addInstance('My Mirror', 'https://my-mirror.example/');
      var instances = await manager.getInstances();

      final custom =
          instances.firstWhere((i) => i.isCustom && i.name == 'My Mirror');
      expect(custom.baseUrl, equals('https://my-mirror.example'));

      // Removing a default mirror is refused...
      final removedDefault = await manager.removeInstance('annas_archive_gl');
      expect(removedDefault, isFalse);

      // ...removing the custom one works and it stays gone.
      expect(await manager.removeInstance(custom.id), isTrue);
      instances = await manager.getInstances();
      expect(instances.where((i) => i.id == custom.id), isEmpty);
    });

    test('dead mirrors are cleaned up on load', () async {
      final manager = InstanceManager();
      final instances = await manager.getInstances();

      // Mirrors known to be dead/suspended must never come back, even if
      // an old database still holds them.
      final deadIds = [
        'welib_org',
        'annas_archive_li',
        'annas_archive_pm',
        'annas_archive_in',
        'annas_archive_se',
        'annas_archive_vg',
        'annas_archive_org'
      ];
      expect(instances.where((i) => deadIds.contains(i.id) && !i.isCustom),
          isEmpty);
    });

    test('enabled filter and selected instance are honored', () async {
      final manager = InstanceManager();
      final instances = await manager.getInstances();
      if (instances.isEmpty) return;

      await manager.toggleInstance(instances.first.id, false);
      final enabled = await manager.getEnabledInstances();
      expect(enabled.map((i) => i.id), isNot(contains(instances.first.id)));

      // Selection falls back to the first enabled instance when unset.
      final current = await manager.getCurrentInstance();
      expect(current.enabled, isTrue);

      await manager.toggleInstance(instances.first.id, true);
    });
  });

  group('service-scoped mirrors', () {
    test('defaults cover annas, libgen and zlibrary', () async {
      final manager = InstanceManager();
      await manager.resetToDefaults();

      final annas =
          await manager.getInstancesByService(MirrorService.annasArchive);
      final libgen = await manager.getInstancesByService(MirrorService.libgen);
      final zlib = await manager.getInstancesByService(MirrorService.zlibrary);

      expect(annas.length, 3);
      expect(libgen.length, 4);
      expect(zlib.length, 5);
      expect(
          libgen.map((i) => i.baseUrl).toList(),
          containsAll([
            'https://libgen.li',
            'https://libgen.gl',
            'https://libgen.bz',
            'https://libgen.vg',
          ]));
      expect(
          zlib.map((i) => i.baseUrl).toList(),
          containsAll([
            'https://z-lib.gd',
            'https://z-library.sk',
            'https://1lib.sk',
            'https://z-lib.fm',
            'https://articles.sk',
          ]));
    });

    test('getEnabledUrls respects toggles and priority order', () async {
      final manager = InstanceManager();
      await manager.resetToDefaults();

      // Disable the first libgen mirror (highest priority).
      final libgenMirrors =
          await manager.getInstancesByService(MirrorService.libgen);
      await manager.toggleInstance(libgenMirrors.first.id, false);

      final urls = await manager.getEnabledUrls(MirrorService.libgen);
      expect(urls, isNot(contains(libgenMirrors.first.baseUrl)));
      expect(urls.length, 3);
      // Remaining urls stay priority-ordered.
      expect(urls, equals(libgenMirrors.skip(1).map((i) => i.baseUrl)));
    });

    test('custom mirrors belong to their service', () async {
      final manager = InstanceManager();
      await manager.addInstance('My mirror', 'https://mirror.example/',
          service: MirrorService.zlibrary);

      final zlib = await manager.getInstancesByService(MirrorService.zlibrary);
      final custom = zlib.where((i) => i.isCustom).single;
      expect(custom.baseUrl, 'https://mirror.example');
      expect(custom.service, MirrorService.zlibrary);
    });

    test('stored mirrors without service tag default to annas', () async {
      // Pre-service mirrors (from an older install) must keep working.
      await MyLibraryDb.instance.savePreference(
          'archive_instances',
          '[{"id":"old_mirror","name":"Old","baseUrl":"https://old.example",'
              '"priority":1,"enabled":true,"isCustom":true}]');

      final manager = InstanceManager();
      final annas =
          await manager.getInstancesByService(MirrorService.annasArchive);
      expect(annas.any((i) => i.id == 'old_mirror'), isTrue);
      expect(annas.firstWhere((i) => i.id == 'old_mirror').service,
          MirrorService.annasArchive);
    });
  });
}
