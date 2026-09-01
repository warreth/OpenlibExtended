// Real checks for the Scoop manifest: the file the release workflow
// keeps in sync must remain a valid Extras-bucket manifest. No fakes -
// these parse the actual checked-in JSON and verify its consistency.

// Dart imports:
import 'dart:convert';
import 'dart:io';

// Flutter imports:
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Map<String, dynamic> manifest;

  setUpAll(() {
    final raw = File('bucket/openlibextended.json').readAsStringSync();
    manifest = jsonDecode(raw) as Map<String, dynamic>;
  });

  test('is valid JSON with the standard Scoop fields', () {
    for (final field in [
      'version',
      'description',
      'homepage',
      'license',
      'architecture',
      'bin',
      'shortcuts',
      'checkver',
      'autoupdate',
    ]) {
      expect(manifest, contains(field), reason: 'missing field: $field');
    }
  });

  test('version is semver-ish', () {
    final version = manifest['version'] as String;
    expect(
      RegExp(r'^[0-9]+\.[0-9]+\.[0-9]+(-[a-zA-Z0-9]+)?$').hasMatch(version),
      isTrue,
      reason: 'unexpected version format: $version',
    );
  });

  test('64bit architecture has url, sha256 hash and installer', () {
    final arch = manifest['architecture'] as Map<String, dynamic>;
    expect(arch, contains('64bit'));

    final bits = arch['64bit'] as Map<String, dynamic>;
    expect(bits['url'] as String,
        startsWith('https://github.com/warreth/OpenlibExtended/releases/'));

    final hash = bits['hash'] as String;
    expect(RegExp(r'^[0-9a-f]{64}$').hasMatch(hash), isTrue,
        reason: 'hash must be a lowercase 64-char sha256: $hash');

    // The exe is an Inno Setup installer; Scoop extracts it with
    // innounp via this hint.
    final installer = bits['installer'] as Map<String, dynamic>;
    expect(installer['type'], 'innosetup');
  });

  test('url version matches the manifest version', () {
    final version = manifest['version'] as String;
    final url = (manifest['architecture']['64bit'] as Map<String, dynamic>)['url']
        as String;
    expect(url, contains('openlib-windows-x64-$version.exe'));
  });

  test('bin and shortcut point at the shipped exe', () {
    expect(manifest['bin'], 'OpenlibExtended.exe');
    final shortcuts = (manifest['shortcuts'] as List).cast<List>();
    expect(shortcuts.first.first, 'OpenlibExtended.exe');
    expect(shortcuts.first.last, 'OpenlibExtended');
  });

  test('checkver tracks the GitHub releases feed', () {
    final checkver = manifest['checkver'] as Map<String, dynamic>;
    expect(checkver['url'] as String,
        'https://github.com/warreth/OpenlibExtended/releases.atom');
    expect((checkver['regex'] as String).isNotEmpty, isTrue);
  });

  test('autoupdate template resolves to the real download host', () {
    final auto =
        manifest['autoupdate']['architecture']['64bit'] as Map<String, dynamic>;
    final template = auto['url'] as String;
    expect(template, contains('releases/download/v\$version/'));
    expect(template, contains('openlib-windows-x64-\$version.exe'));
  });
}
