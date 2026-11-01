import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:open_file/open_file.dart';
import 'package:openlib/services/database.dart';

class ReaderApp {
  const ReaderApp({required this.id, required this.label});
  final String id;
  final String label;
}

/// Persists per-format choices and migrates legacy external-reader switches.
class ReaderPreferences {
  ReaderPreferences({MyLibraryDb? database})
      : _database = database ?? MyLibraryDb.instance;
  final MyLibraryDb _database;

  Future<String> read(String format, {bool legacyExternal = false}) async {
    final normalized = format.toLowerCase();
    try {
      final saved = await _database.getPreference('${normalized}ReaderApp');
      if (saved is String && saved.isNotEmpty) return saved;
    } catch (_) {
      // Existing installations only have the external-reader switch.
    }
    try {
      final legacyKey = normalized == 'pdf'
          ? 'openPdfwithExternalApp'
          : 'openEpubwithExternalApp';
      final external = await _database.getPreference(legacyKey);
      return external == 1 || external == true || external == 'true'
          ? 'ask'
          : 'internal';
    } catch (_) {
      return legacyExternal ? 'ask' : 'internal';
    }
  }

  Future<void> save(String format, String reader) =>
      _database.savePreference('${format.toLowerCase()}ReaderApp', reader);
}

class ReaderApps {
  const ReaderApps();
  static const _channel = MethodChannel('openlib/readers');

  static bool get showsExternalChooser =>
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;

  static String mimeType(String format) => format.toLowerCase() == 'pdf'
      ? 'application/pdf'
      : 'application/epub+zip';

  Future<List<ReaderApp>> installedReaders(String format) async {
    try {
      final values = await _channel
          .invokeListMethod<dynamic>('readers', {'mimeType': mimeType(format)});
      return (values ?? [])
          .map((value) => ReaderApp(
                id: value['id'] as String,
                label: value['label'] as String,
              ))
          .toList();
    } on MissingPluginException {
      return [];
    }
  }

  Future<void> openBook(
      {required String path,
      required String format,
      required String reader}) async {
    try {
      await _channel.invokeMethod<void>('open', {
        'path': path,
        'mimeType': mimeType(format),
        'reader': reader,
      });
    } on MissingPluginException {
      final result = await OpenFile.open(path,
          type: mimeType(format),
          linuxByProcess: true,
          isIOSAppOpen: defaultTargetPlatform == TargetPlatform.iOS);
      if (result.type != ResultType.done) {
        throw PlatformException(
            code: 'reader_unavailable', message: result.message);
      }
    }
  }
}
