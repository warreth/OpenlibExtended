// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:flutter_riverpod/flutter_riverpod.dart';

// Project imports:
import 'package:openlib/services/download_manager.dart';
import 'package:openlib/state/state.dart';

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
      case DownloadStatus.downloadingMirrors:
        return 'Finding mirror...';
      case DownloadStatus.downloading:
        return 'Downloading';
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
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: Theme.of(context).colorScheme.outline.withAlpha(50),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(12.0),
                child: Row(
                  children: [
                    Icon(
                      Icons.download,
                      size: 16,
                      color: Theme.of(context).colorScheme.secondary,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Active Downloads (${downloads.length})',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.secondary,
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              SizedBox(
                height: downloads.length > 2 ? 200 : null,
                child: ListView.separated(
                  shrinkWrap: true,
                  physics: downloads.length > 2
                      ? const AlwaysScrollableScrollPhysics()
                      : const NeverScrollableScrollPhysics(),
                  itemCount: downloads.length,
                  separatorBuilder: (context, index) =>
                      const Divider(height: 1),
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

class _DownloadItem extends ConsumerWidget {
  final DownloadTask task;
  final String Function(int) bytesToFileSize;
  final String Function(DownloadStatus) getStatusText;

  const _DownloadItem({
    required this.task,
    required this.bytesToFileSize,
    required this.getStatusText,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final downloadManager = ref.read(downloadManagerProvider);

    return Padding(
      padding: const EdgeInsets.all(12.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      task.title,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.tertiary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      getStatusText(task.status),
                      style: TextStyle(
                        fontSize: 11,
                        color: Theme.of(context)
                            .colorScheme
                            .tertiary
                            .withAlpha(170),
                      ),
                    ),
                  ],
                ),
              ),
              if (task.status == DownloadStatus.downloading ||
                  task.status == DownloadStatus.downloadingMirrors ||
                  task.status == DownloadStatus.queued)
                IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () {
                    downloadManager.cancelDownload(task.id);
                  },
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (task.status == DownloadStatus.downloading) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: task.progress,
                minHeight: 4,
                backgroundColor:
                    Theme.of(context).colorScheme.tertiary.withAlpha(50),
                color: Theme.of(context).colorScheme.secondary,
              ),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${(task.progress * 100).toStringAsFixed(1)}%',
                  style: TextStyle(
                    fontSize: 10,
                    color: Theme.of(context).colorScheme.tertiary.withAlpha(140),
                  ),
                ),
                Text(
                  '${bytesToFileSize(task.downloadedBytes)} / ${bytesToFileSize(task.totalBytes)}',
                  style: TextStyle(
                    fontSize: 10,
                    color: Theme.of(context).colorScheme.tertiary.withAlpha(140),
                  ),
                ),
              ],
            ),
          ] else if (task.status == DownloadStatus.downloadingMirrors ||
              task.status == DownloadStatus.queued ||
              task.status == DownloadStatus.verifying) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                minHeight: 4,
                backgroundColor:
                    Theme.of(context).colorScheme.tertiary.withAlpha(50),
                color: Theme.of(context).colorScheme.secondary,
              ),
            ),
          ] else if (task.status == DownloadStatus.failed) ...[
            Text(
              task.errorMessage ?? 'Download failed',
              style: const TextStyle(
                fontSize: 10,
                color: Colors.red,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
