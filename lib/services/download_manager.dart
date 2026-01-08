// Dart imports:
import 'dart:async';
import 'dart:io';

// Package imports:
import 'package:dio/dio.dart';
import 'package:crypto/crypto.dart';

// Project imports:
import 'package:openlib/services/database.dart' show MyLibraryDb, MyBook;
import 'package:openlib/services/download_notification.dart';
import 'package:openlib/services/logger.dart';
import 'package:openlib/services/mirror_fetcher.dart';

enum DownloadStatus {
  queued,
  fetchingMirrors,
  downloadingMirrors,
  downloading,
  verifying,
  completed,
  failed,
  cancelled
}

class DownloadTask {
  final String id;
  final String md5;
  final String title;
  final String? author;
  final String? thumbnail;
  final String? publisher;
  final String? info;
  final String format;
  final String? description;
  final String link;
  final List<String> mirrors;
  final String? mirrorUrl; // URL to fetch mirrors from (for retry)

  DownloadStatus status;
  double progress;
  int downloadedBytes;
  int totalBytes;
  String? errorMessage;
  CancelToken? cancelToken;

  DownloadTask({
    required this.id,
    required this.md5,
    required this.title,
    required this.mirrors,
    required this.format,
    this.author,
    this.thumbnail,
    this.publisher,
    this.info,
    this.description,
    required this.link,
    this.mirrorUrl,
    this.status = DownloadStatus.queued,
    this.progress = 0.0,
    this.downloadedBytes = 0,
    this.totalBytes = 0,
    this.errorMessage,
    this.cancelToken,
  });

  DownloadTask copyWith({
    DownloadStatus? status,
    double? progress,
    int? downloadedBytes,
    int? totalBytes,
    String? errorMessage,
    CancelToken? cancelToken,
    List<String>? mirrors,
    String? mirrorUrl,
  }) {
    return DownloadTask(
      id: id,
      md5: md5,
      title: title,
      mirrors: mirrors ?? this.mirrors,
      format: format,
      author: author,
      thumbnail: thumbnail,
      publisher: publisher,
      info: info,
      description: description,
      link: link,
      mirrorUrl: mirrorUrl ?? this.mirrorUrl,
      status: status ?? this.status,
      progress: progress ?? this.progress,
      downloadedBytes: downloadedBytes ?? this.downloadedBytes,
      totalBytes: totalBytes ?? this.totalBytes,
      errorMessage: errorMessage ?? this.errorMessage,
      cancelToken: cancelToken ?? this.cancelToken,
    );
  }
}

class DownloadManager {
  static final DownloadManager _instance = DownloadManager._internal();
  factory DownloadManager() => _instance;
  DownloadManager._internal();

  final MyLibraryDb _database = MyLibraryDb.instance;
  final DownloadNotificationService _notificationService =
      DownloadNotificationService();
  final AppLogger _logger = AppLogger();

  final Map<String, DownloadTask> _activeDownloads = {};
  final StreamController<Map<String, DownloadTask>> _downloadsController =
      StreamController<Map<String, DownloadTask>>.broadcast();

  Stream<Map<String, DownloadTask>> get downloadsStream =>
      _downloadsController.stream;

  Map<String, DownloadTask> get activeDownloads => Map.from(_activeDownloads);

  Future<void> initialize() async {
    await _notificationService.initialize();
    _logger.info('DownloadManager initialized', tag: 'DownloadManager');
  }

  Future<String> _getFilePath(String fileName) async {
    String bookStorageDirectory =
        await _database.getPreference('bookStorageDirectory');
    return '$bookStorageDirectory/$fileName';
  }

  List<String> _reorderMirrors(List<String> mirrors) {
    List<String> ipfsMirrors = [];
    List<String> httpsMirrors = [];

    for (var element in mirrors) {
      if (element.contains('ipfs')) {
        ipfsMirrors.add(element);
      } else {
        if (!element.startsWith('https://annas-archive.org') &&
            !element.startsWith('https://1lib.sk')) {
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
      // Single mirror available, add small delay to avoid rate limiting
      await Future.delayed(const Duration(seconds: 2));
      return mirrors[0];
    }
    for (var url in mirrors) {
      try {
        final response = await dio.head(url,
            options:
                Options(receiveTimeout: const Duration(seconds: timeOut)));
        if (response.statusCode == 200) {
          dio.close();
          return url;
        }
      } catch (_) {}
    }
    return null;
  }

  Future<bool> _verifyFileCheckSum(
      {required String md5Hash, required String format}) async {
    try {
      final bookStorageDirectory =
          await _database.getPreference('bookStorageDirectory');
      final filePath = '$bookStorageDirectory/$md5Hash.$format';
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

  Future<void> addDownload(DownloadTask task) async {
    if (_activeDownloads.containsKey(task.id)) {
      _logger.warning('Download already exists: ${task.title}', tag: 'DownloadManager');
      return;
    }

    _logger.info('Adding download: ${task.title} (${task.format})', tag: 'DownloadManager');
    _activeDownloads[task.id] = task;
    _notifyListeners();

    await _notificationService.showDownloadNotification(
      id: task.id.hashCode,
      title: 'Queued: ${task.title}',
      progress: 0,
    );

    await _startDownload(task);
  }

  Future<void> addDownloadWithMirrorUrl(DownloadTask task, String mirrorUrl) async {
    if (_activeDownloads.containsKey(task.id)) {
      _logger.warning('Download already exists: ${task.title}', tag: 'DownloadManager');
      return;
    }

    _logger.info('Adding download with mirror URL: ${task.title} (${task.format})', tag: 'DownloadManager');
    
    // Store the mirror URL in the task for potential retry
    final taskWithMirrorUrl = task.copyWith(mirrorUrl: mirrorUrl);
    _activeDownloads[task.id] = taskWithMirrorUrl;
    _notifyListeners();

    await _notificationService.showDownloadNotification(
      id: task.id.hashCode,
      title: 'Queued: ${task.title}',
      progress: 0,
    );

    await _startDownloadWithMirrorUrl(taskWithMirrorUrl, mirrorUrl);
  }

  Future<void> _startDownload(DownloadTask task) async {
    Dio? dio;
    try {
      _logger.info('Starting download for: ${task.title} (${task.format})', tag: 'DownloadManager', metadata: {
        'taskId': task.id,
        'md5': task.md5,
        'mirrors': task.mirrors.length,
      });
      
      if (task.mirrors.isEmpty) {
        _logger.warning('No mirrors available for: ${task.title}', tag: 'DownloadManager');
        _updateTaskStatus(task.id, DownloadStatus.failed,
            errorMessage: 'No mirrors available!');
        return;
      }

      dio = Dio();
      
      String path = await _getFilePath('${task.md5}.${task.format}');
      List<String> orderedMirrors = _reorderMirrors(task.mirrors);
      
      _logger.debug('Reordered mirrors for: ${task.title}', tag: 'DownloadManager', metadata: {
        'ipfs_count': orderedMirrors.where((m) => m.contains('ipfs')).length,
        'https_count': orderedMirrors.where((m) => !m.contains('ipfs')).length,
      });

      _updateTaskStatus(task.id, DownloadStatus.downloadingMirrors);
      await _notificationService.showDownloadNotification(
        id: task.id.hashCode,
        title: task.title,
        body: 'Finding available mirror...',
        progress: 0,
      );

      String? workingMirror = await _getAliveMirror(orderedMirrors);

      if (workingMirror == null) {
        _logger.error('No working mirrors found for: ${task.title}', tag: 'DownloadManager', metadata: {
          'checked_mirrors': orderedMirrors.length,
        });
        _updateTaskStatus(task.id, DownloadStatus.failed,
            errorMessage: 'No working mirrors available!');
        await _notificationService.showDownloadNotification(
          id: task.id.hashCode,
          title: task.title,
          body: 'Failed: No working mirrors',
          progress: -1,
        );
        return;
      }
      
      _logger.info('Found working mirror for: ${task.title}', tag: 'DownloadManager', metadata: {
        'mirror': workingMirror,
      });

      // Try to download from each mirror until successful
      bool downloadSuccessful = false;
      int mirrorIndex = orderedMirrors.indexOf(workingMirror);
      
      // Create a single cancel token for the entire mirror retry sequence
      CancelToken cancelToken = CancelToken();
      _activeDownloads[task.id] =
          _activeDownloads[task.id]!.copyWith(cancelToken: cancelToken);
      
      while (mirrorIndex < orderedMirrors.length && !downloadSuccessful) {
        final currentMirror = orderedMirrors[mirrorIndex];
        
        try {
          _updateTaskStatus(task.id, DownloadStatus.downloading);

          await dio.download(
            currentMirror,
            path,
            options: Options(headers: {
              'Connection': 'Keep-Alive',
              'User-Agent':
                  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/75.0.3770.100 Safari/537.36'
            }),
            onReceiveProgress: (rcv, total) {
              if (!(rcv.isNaN || rcv.isInfinite) &&
                  !(total.isNaN || total.isInfinite)) {
                double progress = rcv / total;
                _updateTaskProgress(task.id, progress, rcv, total);

                _notificationService.showDownloadNotification(
                  id: task.id.hashCode,
                  title: task.title,
                  body: 'Downloading...',
                  progress: (progress * 100).toInt(),
                );
              }
            },
            deleteOnError: true,
            cancelToken: cancelToken,
          );

          // Download completed successfully
          downloadSuccessful = true;
          
        } on DioException catch (e) {
          if (e.type == DioExceptionType.cancel) {
            _updateTaskStatus(task.id, DownloadStatus.cancelled);
            await _notificationService.cancelNotification(task.id.hashCode);
            return;
          }
          
          // Try next mirror if available
          mirrorIndex++;
          if (mirrorIndex < orderedMirrors.length) {
            _updateTaskStatus(task.id, DownloadStatus.downloadingMirrors);
            await _notificationService.showDownloadNotification(
              id: task.id.hashCode,
              title: task.title,
              body: 'Retrying with alternate mirror...',
              progress: 0,
            );
            
            // Wait up to 2 seconds before retrying, but check for cancellation
            const totalDelay = Duration(seconds: 2);
            const stepDelay = Duration(milliseconds: 100);
            var elapsed = Duration.zero;
            while (elapsed < totalDelay) {
              await Future.delayed(stepDelay);
              elapsed += stepDelay;

              // Check if task was cancelled during the delay
              if (!_activeDownloads.containsKey(task.id) || 
                  _activeDownloads[task.id]?.cancelToken?.isCancelled == true) {
                _updateTaskStatus(task.id, DownloadStatus.cancelled);
                await _notificationService.cancelNotification(task.id.hashCode);
                return;
              }
            }
          } else {
            // No more mirrors to try; mark task as failed before re-throwing
            _updateTaskStatus(task.id, DownloadStatus.failed,
                errorMessage: 'All mirrors failed!');
            await _notificationService.showDownloadNotification(
              id: task.id.hashCode,
              title: task.title,
              body: 'Download failed: All mirrors exhausted',
              progress: -1,
            );
            rethrow;
          }
        }
      }

      if (!_activeDownloads.containsKey(task.id)) {
        return;
      }

      _updateTaskStatus(task.id, DownloadStatus.verifying);
      await _notificationService.showDownloadNotification(
        id: task.id.hashCode,
        title: task.title,
        body: 'Verifying file...',
        progress: 100,
      );

      bool checkSumValid =
          await _verifyFileCheckSum(md5Hash: task.md5, format: task.format);

      await _database.insert(MyBook(
        id: task.md5,
        title: task.title,
        author: task.author,
        thumbnail: task.thumbnail,
        link: task.link,
        publisher: task.publisher,
        info: task.info,
        format: task.format,
        description: task.description,
      ));

      _updateTaskStatus(task.id, DownloadStatus.completed);

      await _notificationService.showDownloadNotification(
        id: task.id.hashCode,
        title: task.title,
        body: checkSumValid
            ? 'Download completed!'
            : 'Download completed (checksum failed)',
        progress: -1,
      );

      // Clear notification after 3 seconds
      await Future.delayed(const Duration(seconds: 3));
      await _notificationService.cancelNotification(task.id.hashCode);

      // Auto-remove from download list after 30 seconds
      await Future.delayed(const Duration(seconds: 27));
      removeDownload(task.id);
    } on DioException catch (e) {
      if (e.type == DioExceptionType.cancel) {
        _updateTaskStatus(task.id, DownloadStatus.cancelled);
        await _notificationService.cancelNotification(task.id.hashCode);
      } else {
        _updateTaskStatus(task.id, DownloadStatus.failed,
            errorMessage: 'Download failed! Try again...');
        await _notificationService.showDownloadNotification(
          id: task.id.hashCode,
          title: task.title,
          body: 'Download failed',
          progress: -1,
        );
        // Auto-remove failed downloads after 60 seconds
        await Future.delayed(const Duration(seconds: 60));
        removeDownload(task.id);
      }
    } catch (e) {
      _updateTaskStatus(task.id, DownloadStatus.failed,
          errorMessage: 'Download failed! Try again...');
      await _notificationService.showDownloadNotification(
        id: task.id.hashCode,
        title: task.title,
        body: 'Download failed',
        progress: -1,
      );
      // Auto-remove failed downloads after 60 seconds
      await Future.delayed(const Duration(seconds: 60));
      removeDownload(task.id);
    } finally {
      // Always close the Dio instance to prevent resource leaks
      dio?.close();
    }
  }

  Future<void> _startDownloadWithMirrorUrl(DownloadTask task, String mirrorUrl) async {
    Dio? dio;
    try {
      _logger.info('Starting download with mirror URL for: ${task.title}', tag: 'DownloadManager');
      
      // Update status to fetching mirrors
      _updateTaskStatus(task.id, DownloadStatus.fetchingMirrors);
      await _notificationService.showDownloadNotification(
        id: task.id.hashCode,
        title: task.title,
        body: 'Getting mirrors...',
        progress: 0,
      );

      // Fetch mirrors in background using headless webview
      final mirrorFetcher = MirrorFetcherService();
      List<String> fetchedMirrors = await mirrorFetcher.fetchMirrors(mirrorUrl);

      if (!_activeDownloads.containsKey(task.id)) {
        _logger.warning('Task cancelled while fetching mirrors: ${task.title}', tag: 'DownloadManager');
        return; // Task was cancelled while fetching mirrors
      }

      if (fetchedMirrors.isEmpty) {
        _logger.error('Background mirror fetching failed for: ${task.title}', tag: 'DownloadManager');
        // Background fetching failed - keep task for manual retry
        _updateTaskStatus(task.id, DownloadStatus.failed,
            errorMessage: 'Manual verification required');
        await _notificationService.showDownloadNotification(
          id: task.id.hashCode,
          title: task.title,
          body: 'Manual verification needed',
          progress: -1,
        );
        
        // Clear notification after 3 seconds but keep task in UI for manual retry
        await Future.delayed(const Duration(seconds: 3));
        await _notificationService.cancelNotification(task.id.hashCode);
        
        return;
      }

      _logger.info('Successfully fetched ${fetchedMirrors.length} mirrors for: ${task.title}', tag: 'DownloadManager');

      // Update task with fetched mirrors
      final updatedTask = task.copyWith(mirrors: fetchedMirrors);
      _activeDownloads[task.id] = updatedTask;

      // Now proceed with the regular download flow
      dio = Dio();
      
      String path = await _getFilePath('${updatedTask.md5}.${updatedTask.format}');
      List<String> orderedMirrors = _reorderMirrors(updatedTask.mirrors);

      _updateTaskStatus(updatedTask.id, DownloadStatus.downloadingMirrors);
      await _notificationService.showDownloadNotification(
        id: updatedTask.id.hashCode,
        title: updatedTask.title,
        body: 'Finding available mirror...',
        progress: 0,
      );

      String? workingMirror = await _getAliveMirror(orderedMirrors);

      if (workingMirror == null) {
        _updateTaskStatus(updatedTask.id, DownloadStatus.failed,
            errorMessage: 'No working mirrors available!');
        await _notificationService.showDownloadNotification(
          id: updatedTask.id.hashCode,
          title: updatedTask.title,
          body: 'Failed: No working mirrors',
          progress: -1,
        );
        return;
      }

      // Try to download from each mirror until successful
      bool downloadSuccessful = false;
      int mirrorIndex = orderedMirrors.indexOf(workingMirror);
      
      // Create a single cancel token for the entire mirror retry sequence
      CancelToken cancelToken = CancelToken();
      _activeDownloads[updatedTask.id] =
          _activeDownloads[updatedTask.id]!.copyWith(cancelToken: cancelToken);
      
      while (mirrorIndex < orderedMirrors.length && !downloadSuccessful) {
        final currentMirror = orderedMirrors[mirrorIndex];
        
        try {
          _updateTaskStatus(updatedTask.id, DownloadStatus.downloading);

          await dio.download(
            currentMirror,
            path,
            options: Options(headers: {
              'Connection': 'Keep-Alive',
              'User-Agent':
                  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/75.0.3770.100 Safari/537.36'
            }),
            onReceiveProgress: (rcv, total) {
              if (!(rcv.isNaN || rcv.isInfinite) &&
                  !(total.isNaN || total.isInfinite)) {
                double progress = rcv / total;
                _updateTaskProgress(updatedTask.id, progress, rcv, total);

                _notificationService.showDownloadNotification(
                  id: updatedTask.id.hashCode,
                  title: updatedTask.title,
                  body: 'Downloading...',
                  progress: (progress * 100).toInt(),
                );
              }
            },
            deleteOnError: true,
            cancelToken: cancelToken,
          );

          // Download completed successfully
          downloadSuccessful = true;
          
        } on DioException catch (e) {
          if (e.type == DioExceptionType.cancel) {
            _updateTaskStatus(updatedTask.id, DownloadStatus.cancelled);
            await _notificationService.cancelNotification(updatedTask.id.hashCode);
            return;
          }
          
          // Try next mirror if available
          mirrorIndex++;
          if (mirrorIndex < orderedMirrors.length) {
            _updateTaskStatus(updatedTask.id, DownloadStatus.downloadingMirrors);
            await _notificationService.showDownloadNotification(
              id: updatedTask.id.hashCode,
              title: updatedTask.title,
              body: 'Retrying with alternate mirror...',
              progress: 0,
            );
            
            // Wait up to 2 seconds before retrying, but check for cancellation
            const totalDelay = Duration(seconds: 2);
            const stepDelay = Duration(milliseconds: 100);
            var elapsed = Duration.zero;
            while (elapsed < totalDelay) {
              await Future.delayed(stepDelay);
              elapsed += stepDelay;

              // Check if task was cancelled during the delay
              if (!_activeDownloads.containsKey(updatedTask.id) || 
                  _activeDownloads[updatedTask.id]?.cancelToken?.isCancelled == true) {
                _updateTaskStatus(updatedTask.id, DownloadStatus.cancelled);
                await _notificationService.cancelNotification(updatedTask.id.hashCode);
                return;
              }
            }
          } else {
            // No more mirrors to try; mark task as failed before re-throwing
            _updateTaskStatus(updatedTask.id, DownloadStatus.failed,
                errorMessage: 'All mirrors failed!');
            await _notificationService.showDownloadNotification(
              id: updatedTask.id.hashCode,
              title: updatedTask.title,
              body: 'Download failed: All mirrors exhausted',
              progress: -1,
            );
            rethrow;
          }
        }
      }

      if (!_activeDownloads.containsKey(updatedTask.id)) {
        return;
      }

      _updateTaskStatus(updatedTask.id, DownloadStatus.verifying);
      await _notificationService.showDownloadNotification(
        id: updatedTask.id.hashCode,
        title: updatedTask.title,
        body: 'Verifying file...',
        progress: 100,
      );

      bool checkSumValid =
          await _verifyFileCheckSum(md5Hash: updatedTask.md5, format: updatedTask.format);

      await _database.insert(MyBook(
        id: updatedTask.md5,
        title: updatedTask.title,
        author: updatedTask.author,
        thumbnail: updatedTask.thumbnail,
        link: updatedTask.link,
        publisher: updatedTask.publisher,
        info: updatedTask.info,
        format: updatedTask.format,
        description: updatedTask.description,
      ));

      _updateTaskStatus(updatedTask.id, DownloadStatus.completed);

      await _notificationService.showDownloadNotification(
        id: updatedTask.id.hashCode,
        title: updatedTask.title,
        body: checkSumValid
            ? 'Download completed!'
            : 'Download completed (checksum failed)',
        progress: -1,
      );

      // Clear notification after 3 seconds
      await Future.delayed(const Duration(seconds: 3));
      await _notificationService.cancelNotification(updatedTask.id.hashCode);

      // Auto-remove from download list after 30 seconds
      await Future.delayed(const Duration(seconds: 27));
      removeDownload(updatedTask.id);
    } on DioException catch (e) {
      if (e.type == DioExceptionType.cancel) {
        _updateTaskStatus(task.id, DownloadStatus.cancelled);
        await _notificationService.cancelNotification(task.id.hashCode);
      } else {
        _updateTaskStatus(task.id, DownloadStatus.failed,
            errorMessage: 'Download failed! Try again...');
        await _notificationService.showDownloadNotification(
          id: task.id.hashCode,
          title: task.title,
          body: 'Download failed',
          progress: -1,
        );
        // Auto-remove failed downloads after 60 seconds
        await Future.delayed(const Duration(seconds: 60));
        removeDownload(task.id);
      }
    } catch (e) {
      _updateTaskStatus(task.id, DownloadStatus.failed,
          errorMessage: 'Download failed! Try again...');
      await _notificationService.showDownloadNotification(
        id: task.id.hashCode,
        title: task.title,
        body: 'Download failed',
        progress: -1,
      );
      // Auto-remove failed downloads after 60 seconds
      await Future.delayed(const Duration(seconds: 60));
      removeDownload(task.id);
    } finally {
      // Always close the Dio instance to prevent resource leaks
      dio?.close();
    }
  }

  void _updateTaskStatus(String taskId, DownloadStatus status,
      {String? errorMessage}) {
    if (_activeDownloads.containsKey(taskId)) {
      _activeDownloads[taskId] = _activeDownloads[taskId]!.copyWith(
        status: status,
        errorMessage: errorMessage,
      );
      _notifyListeners();
    }
  }

  void _updateTaskProgress(
      String taskId, double progress, int downloaded, int total) {
    if (_activeDownloads.containsKey(taskId)) {
      _activeDownloads[taskId] = _activeDownloads[taskId]!.copyWith(
        progress: progress,
        downloadedBytes: downloaded,
        totalBytes: total,
      );
      _notifyListeners();
    }
  }

  void cancelDownload(String taskId) {
    if (_activeDownloads.containsKey(taskId)) {
      _activeDownloads[taskId]?.cancelToken?.cancel();
      removeDownload(taskId);
    }
  }

  Future<void> retryManualDownload(String taskId) async {
    final task = _activeDownloads[taskId];
    if (task == null || task.mirrorUrl == null) {
      _logger.warning('Cannot retry: task not found or no mirror URL', tag: 'DownloadManager');
      return;
    }

    _logger.info('Retrying manual download for: ${task.title}', tag: 'DownloadManager');
    
    // Reset task status to queued
    _updateTaskStatus(taskId, DownloadStatus.queued, errorMessage: null);
    
    // Restart download process
    await _startDownloadWithMirrorUrl(task, task.mirrorUrl!);
  }

  void removeDownload(String taskId) {
    _activeDownloads.remove(taskId);
    _notifyListeners();
  }

  void _notifyListeners() {
    if (!_downloadsController.isClosed) {
      _downloadsController.add(Map.from(_activeDownloads));
    }
  }

  void dispose() {
    _downloadsController.close();
  }
}
