// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:flutter_riverpod/flutter_riverpod.dart';

// Project imports:
import 'package:openlib/services/download_manager.dart';
import 'package:openlib/state/state.dart';
import 'package:openlib/ui/webview_page.dart';

class ActiveDownloadsWidget extends ConsumerWidget {
  const ActiveDownloadsWidget({super.key});

  String _bytesToFileSize(int bytes) {
    const int decimals = 1;
    const suffixes = ["B", "KB", "MB", "GB", "TB"];
    if (bytes == 0) return '0${suffixes[0]}';
    var i = 0;
    var size = bytes.toDouble();
    while (size >= 1024 && i < suffixes.length - 1) {
      size /= 1024;
      i++;
    }
    return '${size.toStringAsFixed(decimals)}${suffixes[i]}';
  }

  String _getStatusText(DownloadStatus status) {
    switch (status) {
      case DownloadStatus.queued:
        return 'Queued';
      case DownloadStatus.fetchingMirrors:
        return 'Getting mirrors...';
      case DownloadStatus.downloadingMirrors:
        return 'Finding mirror...';
      case DownloadStatus.downloading:
        return 'Downloading';
      case DownloadStatus.paused:
        return 'Paused';
      case DownloadStatus.verifying:
        return 'Verifying';
      case DownloadStatus.completed:
        return 'Completed';
      case DownloadStatus.failed:
        return 'Failed';
      case DownloadStatus.cancelled:
        return 'Cancelled';
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final downloadsAsync = ref.watch(activeDownloadsProvider);

    return downloadsAsync.when(
      data: (downloads) {
        if (downloads.isEmpty) {
          return const SizedBox.shrink();
        }

        return Container(
          margin: const EdgeInsets.only(left: 12, right: 12, bottom: 12),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color:
                  Theme.of(context).colorScheme.outline.withValues(alpha: 0.2),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: Theme.of(context)
                    .colorScheme
                    .shadow
                    .withValues(alpha: 0.08),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(14.0),
                decoration: BoxDecoration(
                  color: Theme.of(context)
                      .colorScheme
                      .secondary
                      .withValues(alpha: 0.1),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(12),
                    topRight: Radius.circular(12),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.download_rounded,
                      size: 18,
                      color: Theme.of(context).colorScheme.secondary,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'Downloads',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.secondary,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.secondary,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '${downloads.length}',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(
                height: downloads.length > 2 ? 220 : null,
                child: ListView.separated(
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  physics: downloads.length > 2
                      ? const AlwaysScrollableScrollPhysics()
                      : const NeverScrollableScrollPhysics(),
                  itemCount: downloads.length,
                  separatorBuilder: (context, index) => Divider(
                    height: 1,
                    thickness: 0.5,
                    color: Theme.of(context)
                        .colorScheme
                        .outline
                        .withValues(alpha: 0.2),
                  ),
                  itemBuilder: (context, index) {
                    final task = downloads.values.elementAt(index);
                    return _DownloadItem(
                      task: task,
                      bytesToFileSize: _bytesToFileSize,
                      getStatusText: _getStatusText,
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }
}

class _DownloadItem extends ConsumerStatefulWidget {
  final DownloadTask task;
  final String Function(int) bytesToFileSize;
  final String Function(DownloadStatus) getStatusText;

  const _DownloadItem({
    required this.task,
    required this.bytesToFileSize,
    required this.getStatusText,
  });

  @override
  ConsumerState<_DownloadItem> createState() => _DownloadItemState();
}

class _DownloadItemState extends ConsumerState<_DownloadItem> {
  // Track if auto-verification has been triggered
  bool _autoVerificationTriggered = false;
  bool _isVerifying = false;

  @override
  void initState() {
    super.initState();
    // Auto-trigger verification if manual verification is required
    _checkAndTriggerAutoVerification();
  }

  @override
  void didUpdateWidget(_DownloadItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Check again if task status changed
    if (oldWidget.task.status != widget.task.status) {
      _checkAndTriggerAutoVerification();
    }
  }

  // Automatically trigger verification when manual verification is required
  void _checkAndTriggerAutoVerification() {
    if (_autoVerificationTriggered || _isVerifying) return;

    final task = widget.task;
    if (task.status == DownloadStatus.failed &&
        task.errorMessage?.contains('Manual verification required') == true &&
        task.mirrorUrl != null) {
      _autoVerificationTriggered = true;
      // Use post-frame callback to ensure context is ready
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _triggerVerification();
        }
      });
    }
  }

  // Open webview for manual verification with visible countdown/CAPTCHA
  Future<void> _triggerVerification() async {
    final task = widget.task;
    if (task.mirrorUrl == null || _isVerifying) return;

    if (mounted) {
      setState(() {
        _isVerifying = true;
      });
    }

    final downloadManager = ref.read(downloadManagerProvider);

    final List<String>? mirrors = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (BuildContext context) => Webview(
          url: task.mirrorUrl!,
          showOverlay: false, // Show full page for CAPTCHA interaction
        ),
      ),
    );

    if (mirrors != null && mirrors.isNotEmpty && mounted) {
      await downloadManager.restartDownloadWithMirrors(task.id, mirrors);
    }

    if (mounted) {
      setState(() {
        _isVerifying = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final downloadManager = ref.read(downloadManagerProvider);
    final task = widget.task;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 12.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              // Status icon
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: _getStatusColor(task.status, context)
                      .withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Center(
                  child: _buildStatusIcon(task.status, context),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      task.title,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).colorScheme.tertiary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Text(
                          widget.getStatusText(task.status),
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: _getStatusColor(task.status, context),
                          ),
                        ),
                        if (task.author != null && task.author!.isNotEmpty) ...[
                          Text(
                            ' • ',
                            style: TextStyle(
                              fontSize: 11,
                              color: Theme.of(context)
                                  .colorScheme
                                  .tertiary
                                  .withAlpha(120),
                            ),
                          ),
                          Flexible(
                            child: Text(
                              task.author!,
                              style: TextStyle(
                                fontSize: 11,
                                color: Theme.of(context)
                                    .colorScheme
                                    .tertiary
                                    .withAlpha(170),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              if (task.status == DownloadStatus.downloading ||
                  task.status == DownloadStatus.downloadingMirrors ||
                  task.status == DownloadStatus.fetchingMirrors ||
                  task.status == DownloadStatus.queued) ...[
                IconButton(
                  icon: Icon(
                    Icons.pause_rounded,
                    size: 20,
                    color:
                        Theme.of(context).colorScheme.tertiary.withAlpha(170),
                  ),
                  onPressed: () {
                    downloadManager.pauseDownload(task.id);
                  },
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  tooltip: 'Pause download',
                ),
                const SizedBox(width: 8),
              ],
              if (task.status == DownloadStatus.paused) ...[
                IconButton(
                  icon: Icon(
                    Icons.play_arrow_rounded,
                    size: 20,
                    color:
                        Theme.of(context).colorScheme.tertiary.withAlpha(170),
                  ),
                  onPressed: () {
                    downloadManager.resumeDownload(task.id);
                  },
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  tooltip: 'Resume download',
                ),
                const SizedBox(width: 8),
              ],
              if (task.status != DownloadStatus.completed &&
                  task.status != DownloadStatus.failed)
                IconButton(
                  icon: Icon(
                    Icons.close_rounded,
                    size: 20,
                    color:
                        Theme.of(context).colorScheme.tertiary.withAlpha(170),
                  ),
                  onPressed: () {
                    downloadManager.cancelDownload(task.id);
                  },
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  tooltip: 'Cancel download',
                ),
            ],
          ),
          const SizedBox(height: 10),
          if (task.status == DownloadStatus.downloading ||
              task.status == DownloadStatus.paused) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: task.progress,
                minHeight: 6,
                backgroundColor:
                    Theme.of(context).colorScheme.tertiary.withAlpha(30),
                color: Theme.of(context).colorScheme.secondary,
              ),
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${(task.progress * 100).toStringAsFixed(0)}%',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.secondary,
                  ),
                ),
                Text(
                  '${widget.bytesToFileSize(task.downloadedBytes)} / ${widget.bytesToFileSize(task.totalBytes)}',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                    color:
                        Theme.of(context).colorScheme.tertiary.withAlpha(140),
                  ),
                ),
              ],
            ),
          ] else if (task.status == DownloadStatus.downloadingMirrors ||
              task.status == DownloadStatus.fetchingMirrors ||
              task.status == DownloadStatus.queued ||
              task.status == DownloadStatus.verifying) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                minHeight: 6,
                backgroundColor:
                    Theme.of(context).colorScheme.tertiary.withAlpha(30),
                color: Theme.of(context).colorScheme.secondary,
              ),
            ),
          ] else if (task.status == DownloadStatus.failed) ...[
            if (task.errorMessage?.contains('Manual verification required') ==
                true) ...[
              // Show "Verify" button for manual verification required error
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: Colors.orange.withValues(alpha: 0.3),
                    width: 1,
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.warning_amber_rounded,
                      size: 14,
                      color: Colors.orange,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        task.errorMessage ?? 'Manual verification required',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: Colors.orange,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: _isVerifying ? null : _triggerVerification,
                      style: TextButton.styleFrom(
                        backgroundColor: Colors.orange,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 4),
                        minimumSize: const Size(40, 24),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: _isVerifying
                          ? const SizedBox(
                              width: 12,
                              height: 12,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text(
                              'Verify',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                    ),
                  ],
                ),
              ),
            ] else ...[
              // Show regular error for other failures
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: Colors.red.withValues(alpha: 0.3),
                    width: 1,
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.error_outline,
                      size: 14,
                      color: Colors.red,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        task.errorMessage ?? 'Download failed',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: Colors.red,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: () {
                        downloadManager.retryDownload(task.id);
                      },
                      style: TextButton.styleFrom(
                        backgroundColor: Colors.red,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 4),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: const Text(
                        'Retry',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildStatusIcon(DownloadStatus status, BuildContext context) {
    switch (status) {
      case DownloadStatus.queued:
        return Icon(
          Icons.schedule_rounded,
          size: 18,
          color: _getStatusColor(status, context),
        );
      case DownloadStatus.fetchingMirrors:
        return SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: _getStatusColor(status, context),
          ),
        );
      case DownloadStatus.downloadingMirrors:
        return SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: _getStatusColor(status, context),
          ),
        );
      case DownloadStatus.downloading:
        return Icon(
          Icons.arrow_downward_rounded,
          size: 18,
          color: _getStatusColor(status, context),
        );
      case DownloadStatus.paused:
        return Icon(
          Icons.pause_rounded,
          size: 18,
          color: _getStatusColor(status, context),
        );
      case DownloadStatus.verifying:
        return SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: _getStatusColor(status, context),
          ),
        );
      case DownloadStatus.completed:
        return Icon(
          Icons.check_circle_rounded,
          size: 18,
          color: _getStatusColor(status, context),
        );
      case DownloadStatus.failed:
        return Icon(
          Icons.error_rounded,
          size: 18,
          color: _getStatusColor(status, context),
        );
      case DownloadStatus.cancelled:
        return Icon(
          Icons.cancel_rounded,
          size: 18,
          color: _getStatusColor(status, context),
        );
    }
  }

  Color _getStatusColor(DownloadStatus status, BuildContext context) {
    switch (status) {
      case DownloadStatus.queued:
        return Colors.orange;
      case DownloadStatus.fetchingMirrors:
      case DownloadStatus.downloadingMirrors:
      case DownloadStatus.downloading:
        return Theme.of(context).colorScheme.secondary;
      case DownloadStatus.paused:
        return Colors.amber;
      case DownloadStatus.verifying:
        return Colors.blue;
      case DownloadStatus.completed:
        return Colors.green;
      case DownloadStatus.failed:
        return Colors.red;
      case DownloadStatus.cancelled:
        return Colors.grey;
    }
  }
}
