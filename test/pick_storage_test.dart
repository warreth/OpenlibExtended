// Real tests for the storage-folder picking behavior: a working picker
// returns the picked path, a cancelled pick returns null, and on iOS a
// picker that throws (the greyed-out Open button case) falls back to
// the app Documents directory instead of stranding the user.

// Flutter imports:
import 'package:flutter_test/flutter_test.dart';

// Package imports:
import 'package:file_picker_platform_interface/file_picker_platform_interface.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

// Project imports:
import 'package:openlib/services/files.dart';

class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.documentsPath);

  final String documentsPath;

  @override
  Future<String?> getApplicationDocumentsPath() async => documentsPath;
}

class _FakePicker extends FilePickerPlatform {
  _FakePicker({this.result, this.error});

  final String? result;
  final Object? error;

  @override
  Future<String?> getDirectoryPath({
    String? dialogTitle,
    String? initialDirectory,
    AndroidOptions? androidOptions,
    LinuxOptions? linuxOptions,
    WebOptions? webOptions,
    WindowsOptions? windowsOptions,
  }) async {
    if (error != null) throw error!;
    return result;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final originalPicker = FilePickerPlatform.instance;
  final originalPath = PathProviderPlatform.instance;

  tearDown(() {
    FilePickerPlatform.instance = originalPicker;
    PathProviderPlatform.instance = originalPath;
  });

  test('a successful pick returns the picked directory', () async {
    FilePickerPlatform.instance = _FakePicker(result: '/mnt/picked-books');

    expect(await pickBookStorageDirectory(), '/mnt/picked-books');
  });

  test('a cancelled pick returns null and does not fall back', () async {
    FilePickerPlatform.instance = _FakePicker(result: null);

    expect(await pickBookStorageDirectory(), isNull);
  });

  test('iOS: broken picker falls back to the Documents directory', () async {
    // The documented iOS failure: the picker opens but Open stays
    // greyed out, and the plugin eventually throws.
    FilePickerPlatform.instance = _FakePicker(error: Exception('cancelled'));
    PathProviderPlatform.instance = _FakePathProvider('/ios/documents');

    final picked = await pickBookStorageDirectory(isIOS: true);
    expect(picked, '/ios/documents');
  });

  test('non-iOS: a broken picker rethrows instead of guessing a location',
      () async {
    FilePickerPlatform.instance = _FakePicker(error: Exception('boom'));

    expect(() => pickBookStorageDirectory(isIOS: false), throwsException);
  });
}
