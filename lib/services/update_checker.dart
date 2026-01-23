// Dart imports:
import 'dart:convert';
import 'dart:io';

// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:dio/dio.dart';
import 'package:http/http.dart' as http;
import 'package:open_file/open_file.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

// Project imports:
import 'package:openlib/services/database.dart';
import 'package:openlib/services/logger.dart';

// Release information from GitHub
class ReleaseInfo {
  final String version;
  final String tagName;
  final String name;
  final String body;
  final String htmlUrl;
  final bool isPrerelease;
  final DateTime publishedAt;
  final Map<String, String> downloadUrls;

  ReleaseInfo({
    required this.version,
    required this.tagName,
    required this.name,
    required this.body,
    required this.htmlUrl,
    required this.isPrerelease,
    required this.publishedAt,
    required this.downloadUrls,
  });

  factory ReleaseInfo.fromJson(Map<String, dynamic> json) {
    final tagName = json["tag_name"] as String;
    final version = tagName.startsWith("v") ? tagName.substring(1) : tagName;

    // Parse download URLs from assets
    final assets = json["assets"] as List<dynamic>? ?? [];
    final downloadUrls = <String, String>{};

    for (final asset in assets) {
      final name = asset["name"] as String;
      final url = asset["browser_download_url"] as String;

      // Categorize by platform
      if (name.contains("android") || name.endsWith(".apk")) {
        if (name.contains("arm64")) {
          downloadUrls["android-arm64"] = url;
        } else if (name.contains("armeabi") || name.contains("arm-v7a")) {
          downloadUrls["android-arm32"] = url;
        } else if (name.contains("x86_64")) {
          downloadUrls["android-x64"] = url;
        } else if (name.contains("universal")) {
          downloadUrls["android-universal"] = url;
        } else {
          downloadUrls["android"] = url;
        }
      } else if (name.endsWith(".ipa")) {
        downloadUrls["ios"] = url;
      } else if (name.contains("windows") ||
          name.endsWith(".exe") ||
          name.endsWith("-windows-x64.zip")) {
        downloadUrls["windows"] = url;
      } else if (name.contains("linux")) {
        if (name.endsWith(".AppImage")) {
          downloadUrls["linux-appimage"] = url;
        } else if (name.endsWith(".flatpak")) {
          downloadUrls["linux-flatpak"] = url;
        } else if (name.endsWith(".tar.gz")) {
          downloadUrls["linux-tar"] = url;
        } else {
          downloadUrls["linux"] = url;
        }
      } else if (name.endsWith(".dmg") || name.contains("macos")) {
        downloadUrls["macos"] = url;
      }
    }

    return ReleaseInfo(
      version: version,
      tagName: tagName,
      name: json["name"] as String? ?? tagName,
      body: json["body"] as String? ?? "",
      htmlUrl: json["html_url"] as String,
      isPrerelease: json["prerelease"] as bool? ?? false,
      publishedAt: DateTime.parse(json["published_at"] as String),
      downloadUrls: downloadUrls,
    );
  }
}

// Update check result
class UpdateCheckResult {
  final bool updateAvailable;
  final ReleaseInfo? latestRelease;
  final String currentVersion;

  UpdateCheckResult({
    required this.updateAvailable,
    this.latestRelease,
    required this.currentVersion,
  });
}

// GitHub Update Checker Service
class UpdateCheckerService {
  static final UpdateCheckerService _instance =
      UpdateCheckerService._internal();
  factory UpdateCheckerService() => _instance;
  UpdateCheckerService._internal();

  final AppLogger _logger = AppLogger();
  final MyLibraryDb _database = MyLibraryDb.instance;

  // GitHub repository information - update these for your repo
  static const String _owner = "warreth";
  static const String _repo = "OpenlibExtended";
  static const String _apiUrl = "https://api.github.com/repos";

  // Check for updates
  Future<UpdateCheckResult> checkForUpdates(
      {bool includePrereleases = false}) async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version;

      _logger.info("Checking for updates", tag: "UpdateChecker", metadata: {
        "currentVersion": currentVersion,
        "includePrereleases": includePrereleases,
      });

      // Fetch releases from GitHub API
      final releases = await _fetchReleases();

      if (releases.isEmpty) {
        _logger.info("No releases found", tag: "UpdateChecker");
        return UpdateCheckResult(
          updateAvailable: false,
          currentVersion: currentVersion,
        );
      }

      // Filter releases based on prerelease preference
      final filteredReleases = includePrereleases
          ? releases
          : releases.where((r) => !r.isPrerelease).toList();

      if (filteredReleases.isEmpty) {
        return UpdateCheckResult(
          updateAvailable: false,
          currentVersion: currentVersion,
        );
      }

      // Get the latest release
      final latestRelease = filteredReleases.first;

      // Compare versions
      final isNewer = _isNewerVersion(currentVersion, latestRelease.version);

      _logger.info("Update check completed", tag: "UpdateChecker", metadata: {
        "latestVersion": latestRelease.version,
        "updateAvailable": isNewer,
      });

      return UpdateCheckResult(
        updateAvailable: isNewer,
        latestRelease: isNewer ? latestRelease : null,
        currentVersion: currentVersion,
      );
    } catch (e, stackTrace) {
      _logger.error("Failed to check for updates",
          tag: "UpdateChecker", error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  // Fetch releases from GitHub API
  Future<List<ReleaseInfo>> _fetchReleases() async {
    final url = Uri.parse("$_apiUrl/$_owner/$_repo/releases");

    final response = await http.get(url, headers: {
      "Accept": "application/vnd.github.v3+json",
      "User-Agent": "Openlib-App",
    });

    if (response.statusCode != 200) {
      throw Exception("Failed to fetch releases: ${response.statusCode}");
    }

    final List<dynamic> data = json.decode(response.body);
    return data.map((json) => ReleaseInfo.fromJson(json)).toList();
  }

  // Compare two semantic versions
  bool _isNewerVersion(String current, String latest) {
    try {
      final currentParts = current.split(".").map(int.parse).toList();
      final latestParts = latest.split(".").map(int.parse).toList();

      // Pad with zeros if needed
      while (currentParts.length < 3) {
        currentParts.add(0);
      }
      while (latestParts.length < 3) {
        latestParts.add(0);
      }

      for (int i = 0; i < 3; i++) {
        if (latestParts[i] > currentParts[i]) return true;
        if (latestParts[i] < currentParts[i]) return false;
      }
      return false;
    } catch (e) {
      _logger
          .warning("Failed to parse version", tag: "UpdateChecker", metadata: {
        "current": current,
        "latest": latest,
      });
      return false;
    }
  }

  // Get the download URL for the current platform
  String? getDownloadUrlForPlatform(ReleaseInfo release) {
    if (Platform.isAndroid) {
      // Prefer arm64 for modern devices
      return release.downloadUrls["android-arm64"] ??
          release.downloadUrls["android-universal"] ??
          release.downloadUrls["android"];
    } else if (Platform.isIOS) {
      return release.downloadUrls["ios"];
    } else if (Platform.isWindows) {
      return release.downloadUrls["windows"];
    } else if (Platform.isLinux) {
      return release.downloadUrls["linux-appimage"] ??
          release.downloadUrls["linux-tar"] ??
          release.downloadUrls["linux"];
    } else if (Platform.isMacOS) {
      return release.downloadUrls["macos"];
    }
    return null;
  }

  // Get file extension for download based on platform
  String _getFileExtension() {
    if (Platform.isAndroid) {
      return "apk";
    } else if (Platform.isIOS) {
      return "ipa";
    } else if (Platform.isWindows) {
      return "exe";
    } else if (Platform.isLinux) {
      return "AppImage";
    } else if (Platform.isMacOS) {
      return "dmg";
    }
    return "bin";
  }

  // Get the downloads directory for storing the update file
  Future<Directory> _getDownloadsDirectory() async {
    if (Platform.isAndroid) {
      // Use external cache for Android
      final cacheDir = await getExternalStorageDirectory();
      if (cacheDir != null) {
        return cacheDir;
      }
    }
    // Fallback to temp directory
    return await getTemporaryDirectory();
  }

  // Download update file with progress tracking
  Future<String?> downloadUpdate({
    required ReleaseInfo release,
    required Function(double progress, int downloaded, int total) onProgress,
    CancelToken? cancelToken,
  }) async {
    final downloadUrl = getDownloadUrlForPlatform(release);
    if (downloadUrl == null) {
      _logger.warning("No download URL available for platform",
          tag: "UpdateChecker");
      return null;
    }

    try {
      final dio = Dio();
      final downloadsDir = await _getDownloadsDirectory();
      final fileExtension = _getFileExtension();
      final fileName = "openlib_${release.version}.$fileExtension";
      final filePath = "${downloadsDir.path}/$fileName";

      _logger.info("Starting update download", tag: "UpdateChecker", metadata: {
        "url": downloadUrl,
        "destination": filePath,
      });

      // Delete existing file if present
      final existingFile = File(filePath);
      if (await existingFile.exists()) {
        await existingFile.delete();
      }

      await dio.download(
        downloadUrl,
        filePath,
        cancelToken: cancelToken,
        options: Options(
          headers: {
            "User-Agent": "Openlib-App",
          },
        ),
        onReceiveProgress: (received, total) {
          if (total > 0) {
            final progress = received / total;
            onProgress(progress, received, total);
          }
        },
      );

      dio.close();

      // Make file executable on Linux
      if (Platform.isLinux) {
        await Process.run("chmod", ["+x", filePath]);
      }

      _logger.info("Update downloaded successfully",
          tag: "UpdateChecker",
          metadata: {
            "path": filePath,
          });

      return filePath;
    } catch (e, stackTrace) {
      if (e is DioException && e.type == DioExceptionType.cancel) {
        _logger.info("Update download cancelled", tag: "UpdateChecker");
        return null;
      }
      _logger.error("Failed to download update",
          tag: "UpdateChecker", error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  // Open/Install the downloaded update file
  Future<void> openUpdateFile(String filePath) async {
    try {
      _logger.info("Opening update file", tag: "UpdateChecker", metadata: {
        "path": filePath,
      });

      if (Platform.isAndroid) {
        // Open APK for installation
        await OpenFile.open(filePath,
            type: "application/vnd.android.package-archive");
      } else if (Platform.isWindows) {
        // Run the exe installer
        await Process.start(filePath, [], mode: ProcessStartMode.detached);
      } else if (Platform.isLinux) {
        // Run the AppImage
        await Process.start(filePath, [], mode: ProcessStartMode.detached);
      } else if (Platform.isMacOS) {
        // Open the DMG
        await OpenFile.open(filePath, type: "application/x-apple-diskimage");
      } else if (Platform.isIOS) {
        // iOS requires special handling via MDM or TestFlight
        await OpenFile.open(filePath);
      }
    } catch (e, stackTrace) {
      _logger.error("Failed to open update file",
          tag: "UpdateChecker", error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  // Show update download dialog with progress
  Future<void> _showUpdateDownloadDialog(
    BuildContext context,
    ReleaseInfo release,
  ) async {
    String? downloadedFilePath;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return _UpdateDownloadDialog(
          release: release,
          updateChecker: this,
          onComplete: (filePath) {
            downloadedFilePath = filePath;
            Navigator.of(dialogContext).pop();
          },
          onCancel: () {
            Navigator.of(dialogContext).pop();
          },
        );
      },
    );

    // Open the downloaded file if successful
    if (downloadedFilePath != null) {
      await openUpdateFile(downloadedFilePath!);
    }
  }

  // Get user preference for prerelease updates
  Future<bool> getIncludePrereleases() async {
    try {
      final value = await _database.getPreference("includePrereleaseUpdates");
      return value == 1;
    } catch (e) {
      return false;
    }
  }

  // Set user preference for prerelease updates
  Future<void> setIncludePrereleases(bool value) async {
    await _database.savePreference("includePrereleaseUpdates", value);
  }

  // Show update dialog
  Future<void> showUpdateDialog(
      BuildContext context, ReleaseInfo release) async {
    final downloadUrl = getDownloadUrlForPlatform(release);

    return showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Row(
            children: [
              Icon(Icons.system_update,
                  color: Theme.of(context).colorScheme.secondary),
              const SizedBox(width: 10),
              Text(
                "Update Available",
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.secondary,
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  "Version ${release.version} is available!",
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.tertiary,
                  ),
                ),
                if (release.isPrerelease)
                  Container(
                    margin: const EdgeInsets.only(top: 8),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.orange.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      "Pre-release",
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.orange,
                      ),
                    ),
                  ),
                const SizedBox(height: 12),
                if (release.body.isNotEmpty) ...[
                  Text(
                    "What's new:",
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.tertiary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    constraints: const BoxConstraints(maxHeight: 200),
                    child: SingleChildScrollView(
                      child: Text(
                        release.body,
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context)
                              .colorScheme
                              .tertiary
                              .withValues(alpha: 0.8),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(
                "Later",
                style: TextStyle(
                  color: Theme.of(context)
                      .colorScheme
                      .tertiary
                      .withValues(alpha: 0.7),
                ),
              ),
            ),
            if (downloadUrl != null)
              TextButton(
                onPressed: () async {
                  Navigator.of(context).pop();
                  // Show download progress dialog
                  if (context.mounted) {
                    await _showUpdateDownloadDialog(context, release);
                  }
                },
                child: Text(
                  "Download & Install",
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.secondary,
                  ),
                ),
              ),
            if (downloadUrl == null)
              TextButton(
                onPressed: () async {
                  Navigator.of(context).pop();
                  final uri = Uri.parse(release.htmlUrl);
                  if (await canLaunchUrl(uri)) {
                    await launchUrl(uri, mode: LaunchMode.externalApplication);
                  }
                },
                child: Text(
                  "View on GitHub",
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.secondary,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  // Check for updates and show dialog if available
  Future<void> checkAndShowUpdateDialog(BuildContext context) async {
    try {
      final includePrereleases = await getIncludePrereleases();
      final result =
          await checkForUpdates(includePrereleases: includePrereleases);

      if (result.updateAvailable &&
          result.latestRelease != null &&
          context.mounted) {
        await showUpdateDialog(context, result.latestRelease!);
      }
    } catch (e) {
      _logger.error("Failed to check for updates",
          tag: "UpdateChecker", error: e);
      // Silently fail - don't show error to user for update checks
    }
  }
}

// Widget for displaying download progress dialog
class _UpdateDownloadDialog extends StatefulWidget {
  final ReleaseInfo release;
  final UpdateCheckerService updateChecker;
  final Function(String? filePath) onComplete;
  final VoidCallback onCancel;

  const _UpdateDownloadDialog({
    required this.release,
    required this.updateChecker,
    required this.onComplete,
    required this.onCancel,
  });

  @override
  State<_UpdateDownloadDialog> createState() => _UpdateDownloadDialogState();
}

class _UpdateDownloadDialogState extends State<_UpdateDownloadDialog> {
  double _progress = 0.0;
  int _downloadedBytes = 0;
  int _totalBytes = 0;
  bool _isDownloading = true;
  bool _downloadComplete = false;
  String? _errorMessage;
  CancelToken? _cancelToken;

  @override
  void initState() {
    super.initState();
    _startDownload();
  }

  Future<void> _startDownload() async {
    _cancelToken = CancelToken();

    try {
      final filePath = await widget.updateChecker.downloadUpdate(
        release: widget.release,
        onProgress: (progress, downloaded, total) {
          if (mounted) {
            setState(() {
              _progress = progress;
              _downloadedBytes = downloaded;
              _totalBytes = total;
            });
          }
        },
        cancelToken: _cancelToken,
      );

      if (mounted) {
        setState(() {
          _isDownloading = false;
          _downloadComplete = filePath != null;
        });

        if (filePath != null) {
          // Small delay to show completion state
          await Future.delayed(const Duration(milliseconds: 500));
          widget.onComplete(filePath);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isDownloading = false;
          _errorMessage = e.toString();
        });
      }
    }
  }

  void _cancelDownload() {
    _cancelToken?.cancel();
    widget.onCancel();
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return "$bytes B";
    if (bytes < 1024 * 1024) return "${(bytes / 1024).toStringAsFixed(1)} KB";
    return "${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB";
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          Icon(
            _downloadComplete
                ? Icons.check_circle
                : _errorMessage != null
                    ? Icons.error
                    : Icons.download,
            color: _downloadComplete
                ? Colors.green
                : _errorMessage != null
                    ? Colors.red
                    : Theme.of(context).colorScheme.secondary,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _downloadComplete
                  ? "Download Complete"
                  : _errorMessage != null
                      ? "Download Failed"
                      : "Downloading Update",
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: _downloadComplete
                    ? Colors.green
                    : _errorMessage != null
                        ? Colors.red
                        : Theme.of(context).colorScheme.secondary,
              ),
            ),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Version ${widget.release.version}",
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.tertiary,
            ),
          ),
          const SizedBox(height: 16),
          if (_errorMessage != null) ...[
            Text(
              _errorMessage!,
              style: const TextStyle(
                color: Colors.red,
                fontSize: 13,
              ),
            ),
          ] else if (_downloadComplete) ...[
            const Row(
              children: [
                Icon(Icons.check, color: Colors.green, size: 20),
                SizedBox(width: 8),
                Text(
                  "Opening installer...",
                  style: TextStyle(
                    color: Colors.green,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ] else ...[
            LinearProgressIndicator(
              value: _progress,
              backgroundColor:
                  Theme.of(context).colorScheme.tertiary.withValues(alpha: 0.2),
              valueColor: AlwaysStoppedAnimation<Color>(
                Theme.of(context).colorScheme.secondary,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  "${(_progress * 100).toStringAsFixed(0)}%",
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.tertiary,
                  ),
                ),
                Text(
                  _totalBytes > 0
                      ? "${_formatBytes(_downloadedBytes)} / ${_formatBytes(_totalBytes)}"
                      : "Connecting...",
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context)
                        .colorScheme
                        .tertiary
                        .withValues(alpha: 0.7),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
      actions: [
        if (_isDownloading)
          TextButton(
            onPressed: _cancelDownload,
            child: Text(
              "Cancel",
              style: TextStyle(
                color: Theme.of(context)
                    .colorScheme
                    .tertiary
                    .withValues(alpha: 0.7),
              ),
            ),
          ),
        if (_errorMessage != null)
          TextButton(
            onPressed: widget.onCancel,
            child: Text(
              "Close",
              style: TextStyle(
                color: Theme.of(context)
                    .colorScheme
                    .tertiary
                    .withValues(alpha: 0.7),
              ),
            ),
          ),
        if (_errorMessage != null)
          TextButton(
            onPressed: () {
              setState(() {
                _errorMessage = null;
                _isDownloading = true;
                _progress = 0.0;
                _downloadedBytes = 0;
                _totalBytes = 0;
              });
              _startDownload();
            },
            child: Text(
              "Retry",
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.secondary,
              ),
            ),
          ),
      ],
    );
  }
}
