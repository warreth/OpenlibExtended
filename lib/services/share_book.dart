// Dart imports:
import 'dart:async';
import 'dart:io';
import 'dart:ui';

// Flutter imports:
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

// Package imports:
import 'package:cached_network_image/cached_network_image.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

// Project imports:
import 'package:openlib/services/files.dart' show getFilePath;

/// Shares a book. When the book file is on disk, the actual .epub/.pdf is
/// attached; otherwise the message carries the title and a link to the
/// book page so the recipient can find it.
Future<void> shareBook(
  String title,
  String link,
  String thumbnailPath, {
  String? fileName,
  String? format,
}) async {
  try {
    final message = 'Discover this amazing book: "$title"\nRead more : $link';

    // Prefer the real file when the book is downloaded.
    if (fileName != null || format != null) {
      final bookFile = await _findBookFile(fileName, format);
      if (bookFile != null) {
        await SharePlus.instance
            .share(ShareParams(files: [XFile(bookFile.path)], text: message));
        return;
      }
    }

    // Not downloaded (or the file vanished): share the cover and link.
    final imagePath = await saveAndGetImagePath(thumbnailPath);
    if (imagePath.isNotEmpty) {
      await SharePlus.instance
          .share(ShareParams(files: [XFile(imagePath)], text: message));
    } else {
      await SharePlus.instance.share(ShareParams(text: message));
    }
  } catch (e) {
    debugPrint('Error sharing the book: $e');
  }
}

/// Resolves the book file from its stored name without throwing when it
/// is missing (not downloaded yet, or the storage preference is gone).
@visibleForTesting
Future<File?> findBookFileForTesting(String? fileName, String? format) =>
    _findBookFile(fileName, format);

Future<File?> _findBookFile(String? fileName, String? format) async {
  try {
    if (fileName != null && fileName.isNotEmpty) {
      final path = await getFilePath(fileName);
      if (await File(path).exists()) return File(path);
    }
  } catch (_) {
    // getFilePath throws when the preference is missing - not an error
    // for sharing; fall through to the link-only share.
  }
  return null;
}

Future<String> saveAndGetImagePath(String url) async {
  if (url.isNotEmpty) {
    try {
      final imageProvider = CachedNetworkImageProvider(url);
      final imageStream = imageProvider.resolve(const ImageConfiguration());
      String? localFilePath;

      final Completer<ByteData> completer = Completer();

      imageStream.addListener(
        ImageStreamListener(
          (info, bool _) async {
            try {
              final ByteData? byteData =
                  await info.image.toByteData(format: ImageByteFormat.png);
              if (byteData != null) {
                final Uint8List imageBytes = byteData.buffer.asUint8List();
                final Directory tempDir = await getTemporaryDirectory();
                final File imageFile = File('${tempDir.path}/image.jpg');

                await imageFile.writeAsBytes(imageBytes);
                localFilePath = imageFile.path;
                completer.complete(byteData);
              } else {
                completer.completeError('Failed to get image bytes');
              }
            } catch (e) {
              completer.completeError(e);
            }
          },
          onError: (exception, stackTrace) {
            completer.completeError('Failed to get image bytes');
          },
        ),
      );
      await completer.future;
      return localFilePath ?? "";
    } catch (e) {
      return "";
    }
  } else {
    return "";
  }
}
