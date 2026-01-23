// Dart imports:
import 'dart:io';

// Package imports:
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';

// Project imports:
import 'package:openlib/services/database.dart' show MyLibraryDb;
import 'package:openlib/services/files.dart' show generateBookFileName;
import 'package:openlib/services/logger.dart';

MyLibraryDb dataBase = MyLibraryDb.instance;
final AppLogger _logger = AppLogger();

Future<String> _getFilePath(String fileName) async {
  String bookStorageDirectory =
      await dataBase.getPreference('bookStorageDirectory');
  return '$bookStorageDirectory/$fileName';
}

List<String> _reorderMirrors(List<String> mirrors) {
  List<String> ipfsMirrors = [];
  List<String> httpsMirrors = [];

  for (var element in mirrors) {
    if (element.contains('ipfs') == true) {
      ipfsMirrors.add(element);
    } else {
      if (element.startsWith('https://annas-archive.org') != true &&
          element.startsWith('https://1lib.sk') != true) {
        httpsMirrors.add(element);
      }
    }
  }
  return [...ipfsMirrors, ...httpsMirrors];
}

Future<String?> _getAliveMirror(List<String> mirrors) async {
  Dio dio = Dio();
  const timeOut = 15;
  if (mirrors.length == 1) {
    await Future.delayed(const Duration(seconds: 2));
    return mirrors[0];
  }
  for (var url in mirrors) {
    try {
      final response = await dio.head(url,
          options: Options(receiveTimeout: const Duration(seconds: timeOut)));
      if (response.statusCode == 200) {
        dio.close();
        return url;
      }
    } catch (_) {}
  }
  return null;
}

Future<void> downloadFile(
    {required List<String> mirrors,
    required String md5,
    required String format,
    required String title,
    String? author,
    String? info,
    required Function onStart,
    required Function onProgress,
    required Function cancelDownlaod,
    required Function mirrorStatus,
    required Function(String) onFileName,
    required Function onDownlaodFailed}) async {
  if (mirrors.isEmpty) {
    _logger.warning('Download failed - no mirrors available', tag: 'Download');
    onDownlaodFailed(
        'No mirrors available! The book may have been removed or is temporarily unavailable.');
  } else {
    Dio dio = Dio();

    // Generate proper filename: title_author_info.extension
    String bookFileName = generateBookFileName(
      title: title,
      author: author,
      info: info,
      format: format,
      md5: md5,
    );
    String path = await _getFilePath(bookFileName);
    List<String> orderedMirrors = _reorderMirrors(mirrors);

    _logger.debug('Attempting download with ${orderedMirrors.length} mirrors',
        tag: 'Download', metadata: {'fileName': bookFileName});

    String? workingMirror = await _getAliveMirror(orderedMirrors);

    if (workingMirror != null) {
      _logger.info('Found working mirror',
          tag: 'Download', metadata: {'mirror': workingMirror});
      onStart();
      onFileName(bookFileName);
      try {
        CancelToken cancelToken = CancelToken();
        dio.download(
          workingMirror,
          path,
          options: Options(headers: {
            'Connection': 'Keep-Alive',
            'User-Agent':
                'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/75.0.3770.100 Safari/537.36'
          }),
          onReceiveProgress: (rcv, total) {
            if (!(rcv.isNaN || rcv.isInfinite) &&
                !(total.isNaN || total.isInfinite)) {
              onProgress(rcv, total);
            }
          },
          deleteOnError: true,
          cancelToken: cancelToken,
        ).catchError((err) {
          if (err.type != DioExceptionType.cancel) {
            _logger.error('Download failed',
                tag: 'Download', error: err.toString());
            onDownlaodFailed(
                'Download failed! Check your internet connection and try again.');
          }
          throw err;
        });

        mirrorStatus(true);

        cancelDownlaod(cancelToken);
      } catch (e) {
        _logger.error('Download exception', tag: 'Download', error: e);
        onDownlaodFailed(
            'Download failed! Check your internet connection and try again.');
      }
    } else {
      _logger.warning('No working mirrors found',
          tag: 'Download', metadata: {'mirrorCount': orderedMirrors.length});
      onDownlaodFailed(
          'No working mirrors available. The download servers may be temporarily down. Try again later or use a VPN.');
    }
  }
}

Future<bool> verifyFileCheckSum(
    {required String md5Hash, required String fileName}) async {
  try {
    final bookStorageDirectory =
        await dataBase.getPreference('bookStorageDirectory');
    final filePath = '$bookStorageDirectory/$fileName';
    final file = File(filePath);
    final stream = file.openRead();
    final hash = await md5.bind(stream).first;
    if (md5Hash == hash.toString()) {
      return true;
    }
    return false;
  } catch (_) {
    return false;
  }
}
