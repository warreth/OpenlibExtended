// Dart imports:
import 'dart:async';
import 'dart:io';

// Package imports:
import 'package:dio/dio.dart';
import 'package:crypto/crypto.dart';

// Project imports:
import 'package:openlib/services/database.dart' show MyLibraryDb, MyBook;
import 'package:openlib/services/download_notification.dart';
import 'package:openlib/services/files.dart' show generateBookFileName;
import 'package:openlib/services/logger.dart';
import 'package:openlib/services/mirror_fetcher.dart';

enum DownloadStatus {
  queued,
  fetchingMirrors,
  downloadingMirrors,
  downloading,
  paused,
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

  // Constants for download completion timing
  // Tasks are removed 30 seconds after completion: 3s for notification clear, then 27s additional delay
  static const Duration _notificationClearDelay = Duration(seconds: 3);
  static const Duration _totalCompletionTime = Duration(seconds: 30);
  static final Duration _taskRemovalDelay =
      _totalCompletionTime - _notificationClearDelay;

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
            options: Options(receiveTimeout: const Duration(seconds: timeOut)));
        if (response.statusCode == 200) {
          dio.close();
          return url;
        }
      } catch (_) {}
    }
    return null;
  }

  Future<bool> _verifyFileCheckSum(
      {required String md5Hash, required String fileName}) async {
    try {
      final bookStorageDirectory =
          await _database.getPreference('bookStorageDirectory');
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

  Future<void> addDownload(DownloadTask task) async {
    if (_activeDownloads.containsKey(task.id)) {
      _logger.warning('Download already exists: ${task.title}',
          tag: 'DownloadManager');
      return;
    }

    _logger.info('Adding download: ${task.title} (${task.format})',
        tag: 'DownloadManager');
    _activeDownloads[task.id] = task;
    _notifyListeners();

    await _notificationService.showDownloadNotification(
      id: task.id.hashCode,
      title: 'Queued: ${task.title}',
      progress: 0,
    );

    // Start download in background (fire-and-forget)
    _startDownload(task);
  }

  Future<void> addDownloadWithMirrorUrl(
      DownloadTask task, String mirrorUrl) async {
    if (_activeDownloads.containsKey(task.id)) {
      _logger.warning('Download already exists: ${task.title}',
          tag: 'DownloadManager');
      return;
    }

    _logger.info(
        'Adding download with mirror URL: ${task.title} (${task.format})',
        tag: 'DownloadManager');

    // Store the mirror URL in the task for potential retry
    final taskWithMirrorUrl = task.copyWith(mirrorUrl: mirrorUrl);
    _activeDownloads[task.id] = taskWithMirrorUrl;
    _notifyListeners();

    await _notificationService.showDownloadNotification(
      id: task.id.hashCode,
      title: 'Queued: ${task.title}',
      progress: 0,
    );

    // Start download in background (fire-and-forget)
    _startDownloadWithMirrorUrl(taskWithMirrorUrl, mirrorUrl);
  }

  Future<void> pauseDownload(String taskId) async {
    if (_activeDownloads.containsKey(taskId)) {
      final task = _activeDownloads[taskId]!;
      if (task.status == DownloadStatus.downloading ||
          task.status == DownloadStatus.downloadingMirrors ||
          task.status == DownloadStatus.queued ||
          task.status == DownloadStatus.fetchingMirrors) {
        task.cancelToken?.cancel();
        _updateTaskStatus(taskId, DownloadStatus.paused);
        await _notificationService.showDownloadNotification(
          id: task.id.hashCode,
          title: task.title,
          body: 'Paused',
          progress: (task.progress * 100).toInt(),
        );
      }
    }
  }

  Future<void> resumeDownload(String taskId) async {
    if (_activeDownloads.containsKey(taskId)) {
      final task = _activeDownloads[taskId]!;
      if (task.status == DownloadStatus.paused ||
          task.status == DownloadStatus.failed) {
        final newToken = CancelToken();
        _activeDownloads[taskId] = task.copyWith(
          status: DownloadStatus.queued,
          cancelToken: newToken,
          errorMessage: null,
        );
        _notifyListeners();

        if (task.mirrors.isNotEmpty) {
          _startDownload(task);
        } else if (task.mirrorUrl != null) {
          _startDownloadWithMirrorUrl(
              _activeDownloads[taskId]!, task.mirrorUrl!);
        } else {
          _startDownload(task);
        }
      }
    }
  }

  Future<void> retryDownload(String taskId) async {
    await resumeDownload(taskId);
  }

  Future<void> _startDownload(DownloadTask task) async {
    _logger.info('Starting download for: ${task.title} (${task.format})',
        tag: 'DownloadManager',
        metadata: {
          'taskId': task.id,
          'md5': task.md5,
          'mirrors': task.mirrors.length,
        });

    if (task.mirrors.isEmpty) {
      if (task.mirrorUrl != null) {
        _logger.info('No mirrors, using mirrorUrl: ${task.mirrorUrl}',
            tag: 'DownloadManager');
        await _startDownloadWithMirrorUrl(task, task.mirrorUrl!);
        return;
      }
      _logger.warning('No mirrors available for: ${task.title}',
          tag: 'DownloadManager');
      _updateTaskStatus(task.id, DownloadStatus.failed,
          errorMessage: 'No mirrors available!');
      return;
    }

    String bookFileName = generateBookFileName(
      title: task.title,
      author: task.author,
      info: task.info,
      format: task.format,
      md5: task.md5,
    );
    String path = await _getFilePath(bookFileName);
    List<String> orderedMirrors = _reorderMirrors(task.mirrors);

    _logger.debug('Reordered mirrors for: ${task.title}',
        tag: 'DownloadManager',
        metadata: {
          'ipfs_count': orderedMirrors.where((m) => m.contains('ipfs')).length,
          'https_count':
              orderedMirrors.where((m) => !m.contains('ipfs')).length,
        });

    await _executeDownloadLoop(task.id, orderedMirrors, path, bookFileName);
  }

  Future<void> _startDownloadWithMirrorUrl(
      DownloadTask task, String mirrorUrl) async {
    try {
      _logger.info('Starting download with mirror URL for: ${task.title}',
          tag: 'DownloadManager');

      _updateTaskStatus(task.id, DownloadStatus.fetchingMirrors);
      await _notificationService.showDownloadNotification(
        id: task.id.hashCode,
        title: task.title,
        body: 'Getting mirrors...',
        progress: 0,
      );

      final mirrorFetcher = MirrorFetcherService();
      // Ensure we check for cancellation
      if (!_activeDownloads.containsKey(task.id) ||
          _activeDownloads[task.id]?.status == DownloadStatus.cancelled) {
        return;
      }

      List<String> fetchedMirrors = [];
      try {
        fetchedMirrors = await mirrorFetcher.fetchMirrors(mirrorUrl);
      } catch (e) {
        _logger.error('Mirror fetching threw error: $e',
            tag: 'DownloadManager');
      }

      if (!_activeDownloads.containsKey(task.id)) {
        _logger.warning('Task cancelled while fetching mirrors: ${task.title}',
            tag: 'DownloadManager');
        return;
      }

      final currentTask = _activeDownloads[task.id]!;
      if (currentTask.status == DownloadStatus.paused ||
          currentTask.status == DownloadStatus.cancelled) {
        return;
      }

      if (fetchedMirrors.isEmpty) {
        _logger.error('Background mirror fetching failed for: ${task.title}',
            tag: 'DownloadManager');
        _updateTaskStatus(task.id, DownloadStatus.failed,
            errorMessage: 'Manual verification required');
        await _notificationService.showDownloadNotification(
          id: task.id.hashCode,
          title: task.title,
          body: 'Manual verification needed',
          progress: -1,
        );
        await Future.delayed(_notificationClearDelay);
        await _notificationService.cancelNotification(task.id.hashCode);
        return;
      }

      _logger.info(
          'Successfully fetched ${fetchedMirrors.length} mirrors for: ${task.title}',
          tag: 'DownloadManager');

      final updatedTask =
          _activeDownloads[task.id]!.copyWith(mirrors: fetchedMirrors);
      _activeDownloads[task.id] = updatedTask;

      // Proceed to download loop

      String bookFileName = generateBookFileName(
        title: updatedTask.title,
        author: updatedTask.author,
        info: updatedTask.info,
        format: updatedTask.format,
        md5: updatedTask.md5,
      );
      String path = await _getFilePath(bookFileName);
      List<String> orderedMirrors = _reorderMirrors(fetchedMirrors);

      await _executeDownloadLoop(
          updatedTask.id, orderedMirrors, path, bookFileName);
    } catch (e) {
      _logger.error('Error in startDownloadWithMirrorUrl',
          tag: 'DownloadManager', error: e);
      _handleDownloadFailure(task.id, 'Error getting mirrors');
    }
  }

  Future<void> _executeDownloadLoop(String taskId, List<String> mirrors,
      String filePath, String fileName) async {
    DownloadTask? task = _activeDownloads[taskId];
    if (task == null) return;

    // Create a NEW cancel token for this loop if one doesn't exist or is cancelled
    if (task.cancelToken == null || task.cancelToken!.isCancelled) {
      CancelToken token = CancelToken();
      _activeDownloads[taskId] = task.copyWith(cancelToken: token);
      task = _activeDownloads[taskId]!;
    }

    _updateTaskStatus(taskId, DownloadStatus.downloadingMirrors);
    await _notificationService.showDownloadNotification(
      id: task.id.hashCode,
      title: task.title,
      body: 'Finding available mirror...',
      progress: (task.progress * 100).toInt(),
    );

    String? workingMirror = await _getAliveMirror(mirrors);

    if (workingMirror == null && mirrors.isNotEmpty) {
      // If probing failed, fallback to just trying them sequentially
      workingMirror = mirrors.first;
    }

    if (workingMirror == null) {
      _handleDownloadFailure(taskId, 'No working mirrors available!');
      return;
    }

    // Sort mirrors putting the working one first
    List<String> sortedMirrors = List.from(mirrors);
    sortedMirrors.remove(workingMirror);
    sortedMirrors.insert(0, workingMirror);

    bool downloadSuccessful = false;
    int mirrorIndex = 0;

    while (mirrorIndex < sortedMirrors.length && !downloadSuccessful) {
      task = _activeDownloads[taskId];
      if (task == null ||
          task.status == DownloadStatus.paused ||
          task.status == DownloadStatus.cancelled) {
        return;
      }

      String currentMirror = sortedMirrors[mirrorIndex];
      _logger.info('Attempting download from: $currentMirror',
          tag: 'DownloadManager');

      try {
        _updateTaskStatus(taskId, DownloadStatus.downloading);
        await _notificationService.showDownloadNotification(
          id: task.id.hashCode,
          title: task.title,
          body: 'Downloading...',
          progress: (task.progress * 100).toInt(),
        );

        bool completed = await _downloadFileWithResume(
          url: currentMirror,
          savePath: filePath,
          taskId: taskId,
          cancelToken: task.cancelToken!,
        );

        if (completed) {
          downloadSuccessful = true;
        }
      } catch (e) {
        if (e is DioException && e.type == DioExceptionType.cancel) {
          return;
        }
        _logger.warning('Download from mirror failed',
            tag: 'DownloadManager', error: e);
      }

      if (!downloadSuccessful) {
        mirrorIndex++;
        if (mirrorIndex < sortedMirrors.length) {
          await Future.delayed(const Duration(seconds: 1));
        }
      }
    }

    if (downloadSuccessful) {
      await _finalizeDownload(taskId, filePath, fileName);
    } else {
      // If we are here, all mirrors failed
      task = _activeDownloads[taskId];
      // Only mark failed if we are not paused/cancelled
      if (task != null &&
          task.status != DownloadStatus.paused &&
          task.status != DownloadStatus.cancelled) {
        _handleDownloadFailure(taskId, 'All mirrors failed!');
      }
    }
  }

  Future<bool> _downloadFileWithResume({
    required String url,
    required String savePath,
    required String taskId,
    required CancelToken cancelToken,
  }) async {
    Dio dio = Dio();
    // Increase timeout for large files
    dio.options.connectTimeout = const Duration(seconds: 30);
    dio.options.receiveTimeout = const Duration(minutes: 60);

    try {
      File file = File(savePath);
      int received = 0;
      if (await file.exists()) {
        received = await file.length();
      }

      Options options = Options(
        responseType: ResponseType.stream,
        headers: {
          'Connection': 'Keep-Alive',
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/75.0.3770.100 Safari/537.36',
        },
      );

      if (received > 0) {
        options.headers!['Range'] = 'bytes=$received-';
        _logger.info('Resuming download from byte $received',
            tag: 'DownloadManager');
      }

      Response response = await dio.get(
        url,
        options: options,
        cancelToken: cancelToken,
      );

      int contentLength = 0;
      if (response.headers.value('content-length') != null) {
        contentLength =
            int.parse(response.headers.value('content-length')!);
      }

      int total = received + contentLength;

      // If server ignores range request (returns 200 instead of 206), we must reset received
      if (received > 0 && response.statusCode == 200) {
        _logger.info('Server does not support range, starting from scratch',
            tag: 'DownloadManager');
        received = 0;
        total = contentLength;
        await file.writeAsBytes([]); // Truncate
      }

      IOSink sink = file.openWrite(mode: FileMode.append);

      await response.data.stream.listen(
        (data) {
          sink.add(data);
          received += data.length as int;

          double progress = total > 0 ? received / total : 0;
          _updateTaskProgress(taskId, progress, received, total);

          if (received % (1024 * 1024) == 0) {
            // Update notification roughly every 1MB
            _notificationService.showDownloadNotification(
              id: taskId.hashCode,
              title: _activeDownloads[taskId]?.title ?? 'Downloading',
              body: 'Downloading...',
              progress: (progress * 100).toInt(),
            );
          }
        },
        onDone: () async {
          // Sink will be closed in finally or subsequent logic
        },
        cancelOnError: true,
      ).asFuture();

      await sink.flush();
      await sink.close();

      return true;
    } catch (e) {
      if (e is DioException && e.type == DioExceptionType.cancel) {
        rethrow;
      }
      _logger.error('Download stream error',
          tag: 'DownloadManager', error: e);
      return false;
    } finally {
      dio.close();
    }
  }

  Future<void> _handleDownloadFailure(String taskId, String message) async {
    _updateTaskStatus(taskId, DownloadStatus.failed, errorMessage: message);
    await _notificationService.showDownloadNotification(
      id: taskId.hashCode,
      title: _activeDownloads[taskId]?.title ?? 'Download',
      body: 'Failed: $message',
      progress: -1,
    );
  }

  Future<void> _finalizeDownload(
      String taskId, String filePath, String fileName) async {
    DownloadTask? task = _activeDownloads[taskId];
    if (task == null) return;

    _updateTaskStatus(task.id, DownloadStatus.verifying);
    await _notificationService.showDownloadNotification(
      id: task.id.hashCode,
      title: task.title,
      body: 'Verifying file...',
      progress: 100,
    );

    bool checkSumValid =
        await _verifyFileCheckSum(md5Hash: task.md5, fileName: fileName);

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
      fileName: fileName,
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

    await Future.delayed(_notificationClearDelay);
    await _notificationService.cancelNotification(task.id.hashCode);

    await Future.delayed(_taskRemovalDelay);
    removeDownload(task.id);
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
