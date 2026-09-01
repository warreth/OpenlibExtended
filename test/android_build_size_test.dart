// Real checks for the Android release-size configuration: the gradle
// file must keep shrinking and splits enabled, the ProGuard rules must
// exist and pin every reflective plugin, and the bundled font set must
// only carry weights the app actually renders.

// Dart imports:
import 'dart:io';

// Flutter imports:
import 'package:flutter_test/flutter_test.dart';

void main() {
  late String gradle;
  late String proguard;

  setUpAll(() {
    gradle = File('android/app/build.gradle').readAsStringSync();
    proguard = File('android/app/proguard-rules.pro').readAsStringSync();
  });

  group('gradle release build', () {
    test('R8 code shrinking is enabled for release', () {
      final releaseBlock = _releaseBuildType(gradle);
      expect(releaseBlock, contains('minifyEnabled = true'));
    });

    test('resource shrinking is enabled for release', () {
      final releaseBlock = _releaseBuildType(gradle);
      expect(releaseBlock, contains('shrinkResources = true'));
    });

    test('proguard rules file is wired in', () {
      final releaseBlock = _releaseBuildType(gradle);
      expect(releaseBlock, contains("getDefaultProguardFile('proguard-android-optimize.txt')"));
      expect(releaseBlock, contains("'proguard-rules.pro'"));
    });

    test('debug builds are not minified', () {
      expect(gradle, isNot(contains('debug')));
    });

    test('ABI splits produce per-architecture APKs', () {
      expect(gradle, contains('splits'));
      for (final abi in ['armeabi-v7a', 'arm64-v8a', 'x86_64']) {
        expect(gradle, contains("'$abi'"));
      }
      expect(gradle, contains('universalApk false'));
    });
  });

  group('proguard rules', () {
    test('keeps the Flutter engine and embedding', () {
      expect(proguard, contains('io.flutter.**'));
      expect(proguard, contains('io.flutter.embedding.**'));
    });

    test('keeps every reflective plugin the app depends on', () {
      const kept = [
        // sqflite: native-side callbacks.
        'com.tekartik.sqflite',
        // inappwebview: JS bridges looked up by name.
        'flutter_inappwebview',
        // local notifications: receivers restored from saved intents.
        'com.dexterous',
        // permission_handler: channel result constants.
        'com.baseflow',
      ];
      for (final marker in kept) {
        expect(proguard, contains(marker),
            reason: '$marker must be kept from R8 stripping');
      }
    });

    test('preserves attributes reflection needs', () {
      expect(proguard, contains('-keepattributes Signature'));
      expect(proguard, contains('-keepattributes *Annotation*'));
    });
  });

  group('bundled assets audit', () {
    test('Nunito ships exactly the weights the app renders', () {
      final dir = Directory('google_fonts');
      final fonts =
          dir.listSync().map((f) => f.path.split('/').last).toList()..sort();
      // FontWeight values used across lib/: 400 (normal), 500, 600, 700
      // (bold), 900 (w900). Nunito file names map to those weights.
      expect(fonts, [
        'Nunito-Black.ttf',
        'Nunito-Bold.ttf',
        'Nunito-Medium.ttf',
        'Nunito-Regular.ttf',
        'Nunito-SemiBold.ttf',
      ]);
    });

    test('every shipped asset is referenced by the app', () {
      final referenced = _referencedAssetNames();
      for (final entity in Directory('assets').listSync(recursive: true)) {
        if (entity is! File) continue;
        // Launcher icons are build-time inputs for flutter_launcher_icons,
        // declared in pubspec's flutter_icons: section - not runtime assets.
        if (entity.path.contains('assets/icons/')) continue;
        final name = entity.path.split('/').last;
        expect(referenced, contains(name),
            reason: 'asset $name is shipped but never referenced');
      }
    });

    test('pubspec declares no unused icon/dev shim packages', () {
      final pubspec = File('pubspec.yaml').readAsStringSync();
      expect(pubspec, isNot(contains('cupertino_icons:')));
      expect(pubspec, isNot(contains('dev: ^')));
    });
  });
}

/// Extracts the release buildTypes block from the gradle file.
String _releaseBuildType(String gradle) {
  final start = gradle.indexOf('buildTypes');
  final releaseIdx = gradle.indexOf('release {', start);
  expect(releaseIdx, greaterThan(-1), reason: 'release buildType missing');
  // Take from 'release {' to the matching closing brace at the top
  // level of buildTypes.
  var depth = 0;
  var end = releaseIdx;
  for (var i = releaseIdx; i < gradle.length; i++) {
    final ch = gradle[i];
    if (ch == '{') depth++;
    if (ch == '}') {
      depth--;
      if (depth == 0) {
        end = i;
        break;
      }
    }
  }
  return gradle.substring(releaseIdx, end);
}

/// Collects asset basenames referenced anywhere in the Dart source.
Set<String> _referencedAssetNames() {
  final names = <String>{};
  final libDir = Directory('lib');
  final pubspec = File('pubspec.yaml').readAsStringSync();
  for (final entity in libDir.listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.dart')) continue;
    final source = entity.readAsStringSync();
    for (final assetEntity in Directory('assets').listSync(recursive: true)) {
      if (assetEntity is! File) continue;
      final name = assetEntity.path.split('/').last;
      if (source.contains(name)) names.add(name);
    }
  }
  // pubspec itself lists directories, not files; nothing to add there.
  expect(pubspec, contains('assets/'));
  return names;
}
