// Dart imports:
import 'dart:convert';
import 'dart:io';

// Flutter imports:
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// Package imports:
import 'package:android_package_installer/android_package_installer.dart';
import 'package:apk_sideload/install_apk.dart';
import 'package:dio/dio.dart';
import 'package:http/http.dart' as http;
import 'package:open_file/open_file.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
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
          name.endsWith(".msix") ||
          (name.endsWith(".zip") &&
              (name.contains("win") || name.contains("x64")))) {
        downloadUrls["windows"] = url;
      } else if (name.contains("linux") ||
          name.endsWith(".AppImage") ||
          name.endsWith(".flatpak")) {
        if (name.endsWith(".AppImage")) {
          downloadUrls["linux-appimage"] = url;
        } else if (name.endsWith(".flatpak")) {
          downloadUrls["linux-flatpak"] = url;
        } else if (name.endsWith(".tar.gz")) {
          downloadUrls["linux-tar"] = url;
        } else if (name.endsWith(".deb")) {
          downloadUrls["linux-deb"] = url;
        } else if (name.endsWith(".rpm")) {
          downloadUrls["linux-rpm"] = url;
        } else {
          downloadUrls["linux"] = url;
        }
      } else if (name.endsWith(".dmg") ||
          name.contains("macos") ||
          name.contains("darwin")) {
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

      // Find the latest release that is newer than the current version
      ReleaseInfo? latestNewerRelease;
      for (final release in filteredReleases) {
        if (_isNewerVersion(currentVersion, release.version)) {
          latestNewerRelease = release;
          break;
        }
      }

      if (latestNewerRelease == null) {
        return UpdateCheckResult(
          updateAvailable: false,
          currentVersion: currentVersion,
        );
      }

      _logger.info("Update check completed", tag: "UpdateChecker", metadata: {
        "latestVersion": latestNewerRelease.version,
        "updateAvailable": true,
      });

      return UpdateCheckResult(
        updateAvailable: true,
        latestRelease: latestNewerRelease,
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
      "User-Agent": "OpenlibExtended-App",
    });

    if (response.statusCode != 200) {
      throw Exception("Failed to fetch releases: ${response.statusCode}");
    }

    final List<dynamic> data = json.decode(response.body);
    return data.map((json) => ReleaseInfo.fromJson(json)).toList();
  }

  // Compare two semantic versions
  // Compare two semantic versions, including pre-release tags
  bool _isNewerVersion(String current, String latest) {
    try {
      // Split out pre-release tags
      final currentMain = current.split('-')[0];
      final latestMain = latest.split('-')[0];
      final currentParts = currentMain.split('.').map(int.parse).toList();
      final latestParts = latestMain.split('.').map(int.parse).toList();

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

      // If main versions are equal, handle pre-release tags
      final currentIsPre = current.contains('-');
      final latestIsPre = latest.contains('-');
      if (!currentIsPre && latestIsPre) {
        // Current is stable, latest is pre-release: not newer
        return false;
      } else if (currentIsPre && !latestIsPre) {
        // Current is pre-release, latest is stable: newer
        return true;
      } else if (currentIsPre && latestIsPre) {
        // Both are pre-releases: compare tags lexically
        final currentTag =
            current.split('-').length > 1 ? current.split('-')[1] : '';
        final latestTag =
            latest.split('-').length > 1 ? latest.split('-')[1] : '';
        return latestTag.compareTo(currentTag) > 0;
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
          release.downloadUrls["linux-deb"] ??
          release.downloadUrls["linux-flatpak"] ??
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
    // Use temp directory for all platforms - this works better with FileProvider on Android
    return await getTemporaryDirectory();
  }

  // Check and request install packages permission on Android
  Future<bool> _checkAndRequestInstallPermission(BuildContext context) async {
    if (!Platform.isAndroid) return true;

    // Check if permission is already granted
    final status = await Permission.requestInstallPackages.status;
    if (status.isGranted) return true;

    // Show explanation dialog and request permission
    if (!context.mounted) return false;

    final shouldRequest = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: Row(
            children: [
              Icon(Icons.security,
                  color: Theme.of(dialogContext).colorScheme.secondary),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  "Permission Required",
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          content: const Text(
            "To install app updates, OpenlibExtended needs permission to install packages.\n\n"
            "This allows the app to automatically install new versions with bug fixes and new features.\n\n"
            "You will be taken to Settings to enable this permission.",
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(
                "Cancel",
                style: TextStyle(
                  color: Theme.of(dialogContext)
                      .colorScheme
                      .tertiary
                      .withValues(alpha: 0.7),
                ),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(
                "Open Settings",
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Theme.of(dialogContext).colorScheme.secondary,
                ),
              ),
            ),
          ],
        );
      },
    );

    if (shouldRequest != true) return false;

    // Request permission - this will open settings on Android 8+
    final result = await Permission.requestInstallPackages.request();
    return result.isGranted;
  }

  // Download update file with progress tracking and move to install dir (Linux/Windows)
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
      final tempFileName = "openlib_update_temp.$fileExtension";
      final tempFilePath = "${downloadsDir.path}/$tempFileName";

      _logger.info("Starting update download", tag: "UpdateChecker", metadata: {
        "url": downloadUrl,
        "destination": tempFilePath,
      });

      // Delete existing temp file if present
      final existingFile = File(tempFilePath);
      if (await existingFile.exists()) {
        await existingFile.delete();
      }

      await dio.download(
        downloadUrl,
        tempFilePath,
        cancelToken: cancelToken,
        options: Options(
          headers: {
            "User-Agent": "OpenlibExtended-App",
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

      // Determine install directory and target filename
      String installDirPath;
      String targetFileName;
      if (Platform.isWindows) {
        // Use the directory of the running executable
        installDirPath = File(Platform.resolvedExecutable).parent.path;
        targetFileName = "openlib.exe";
      } else if (Platform.isLinux) {
        installDirPath = File(Platform.resolvedExecutable).parent.path;
        targetFileName = "openlib.AppImage";
      } else {
        // For other platforms, just return the temp file path
        if (Platform.isMacOS || Platform.isIOS || Platform.isAndroid) {
          // No special move needed
          if (Platform.isLinux) {
            await Process.run("chmod", ["+x", tempFilePath]);
          }
          return tempFilePath;
        }
        return tempFilePath;
      }

      final targetFilePath = "$installDirPath/$targetFileName";

      // Remove old versioned executables in the install dir
      final dir = Directory(installDirPath);
      final files = dir.listSync();
      for (final f in files) {
        if (f is File) {
          final name = f.path.split(Platform.pathSeparator).last;
          if ((Platform.isWindows &&
                  name.startsWith("openlib_") &&
                  name.endsWith(".exe")) ||
              (Platform.isLinux &&
                  name.startsWith("openlib_") &&
                  name.endsWith(".AppImage"))) {
            try {
              await f.delete();
            } catch (_) {}
          }
        }
      }

      // Move the downloaded file to the install directory, overwrite if exists
      final tempFile = File(tempFilePath);
      final targetFile = File(targetFilePath);
      if (await targetFile.exists()) {
        await targetFile.delete();
      }
      try {
        await tempFile.rename(targetFilePath);
      } on FileSystemException catch (e) {
        // errno=18 is EXDEV (cross-device link)
        if (e.osError != null && e.osError!.errorCode == 18) {
          // Fallback: copy then delete
          await tempFile.copy(targetFilePath);
          await tempFile.delete();
        } else {
          rethrow;
        }
      }

      // Make file executable on Linux
      if (Platform.isLinux) {
        await Process.run("chmod", ["+x", targetFilePath]);
      }

      _logger.info("Update moved to install directory",
          tag: "UpdateChecker",
          metadata: {
            "path": targetFilePath,
          });

      return targetFilePath;
    } catch (e, stackTrace) {
      if (e is DioException && e.type == DioExceptionType.cancel) {
        _logger.info("Update download cancelled", tag: "UpdateChecker");
        return null;
      }
      _logger.error("Failed to download/move update",
          tag: "UpdateChecker", error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  // Open/Install the downloaded update file with fallback mechanisms
  Future<bool> openUpdateFile(String filePath, BuildContext context,
      {ReleaseInfo? release}) async {
    _logger.info("Opening update file", tag: "UpdateChecker", metadata: {
      "path": filePath,
    });

    // Verify file exists and has content
    final file = File(filePath);
    if (!await file.exists()) {
      _logger.error("Update file does not exist", tag: "UpdateChecker");
      if (context.mounted) {
        _showInstallErrorDialog(context, filePath, "Downloaded file not found",
            release: release);
      }
      return false;
    }

    final fileSize = await file.length();
    if (fileSize < 10240) {
      _logger.error("Update file is too small, likely corrupted",
          tag: "UpdateChecker", metadata: {"size": fileSize});
      if (context.mounted) {
        _showInstallErrorDialog(context, filePath,
            "Downloaded file appears to be corrupted (only ${_formatBytes(fileSize)})",
            release: release);
      }
      return false;
    }

    _logger.info("File verified", tag: "UpdateChecker", metadata: {
      "size": fileSize,
    });

    if (Platform.isAndroid) {
      if (!context.mounted) return false;
      return await _installApkWithFallbacks(filePath, context,
          release: release);
    } else if (Platform.isWindows || Platform.isLinux) {
      // Always use the non-versioned filename in the install dir
      String installDirPath = File(Platform.resolvedExecutable).parent.path;
      String targetFileName =
          Platform.isWindows ? "openlib.exe" : "openlib.AppImage";
      String targetFilePath = "$installDirPath/$targetFileName";
      // Launch the new executable
      await Process.start(targetFilePath, [], mode: ProcessStartMode.detached);
      return true;
    } else if (Platform.isMacOS) {
      await OpenFile.open(filePath, type: "application/x-apple-diskimage");
      return true;
    } else if (Platform.isIOS) {
      await OpenFile.open(filePath);
      return true;
    }
    return false;
  }

  // Install APK on Android with multiple fallback methods
  Future<bool> _installApkWithFallbacks(String filePath, BuildContext context,
      {ReleaseInfo? release}) async {
    // Track errors from each method for user display
    List<String> attemptedMethods = [];
    List<String> errorMessages = [];

    // Check and request install permission first
    final hasPermission = await _checkAndRequestInstallPermission(context);
    if (!hasPermission) {
      _logger.warning("Install permission denied", tag: "UpdateChecker");
      if (context.mounted) {
        _showInstallErrorDialog(context, filePath,
            "Permission to install apps was denied. You can still install manually.",
            release: release);
      }
      return false;
    }

    // Warn about debug builds
    if (kDebugMode && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "Debug Build Detected: Update may fail with 'App not installed' due to signature mismatch. Uninstall this app first.",
          ),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 10),
        ),
      );
    }

    // Method 1: Try open_file (Most standard method)
    attemptedMethods.add("Open File");
    try {
      _logger.info("Attempting installation with open_file",
          tag: "UpdateChecker");
      final result = await OpenFile.open(filePath,
          type: "application/vnd.android.package-archive");
      if (result.type == ResultType.done) {
        _logger.info("open_file installation initiated", tag: "UpdateChecker");
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text(
                  "Opening installer... If nothing happens, the install failed."),
              duration: const Duration(seconds: 5),
              action: SnackBarAction(
                label: "Manual Install",
                onPressed: () {
                  if (context.mounted) {
                    _showInstallFallbackDialog(
                        context,
                        filePath,
                        attemptedMethods,
                        ["May have failed silently"],
                        release);
                  }
                },
              ),
            ),
          );
        }
        return true;
      }
      final errorMsg =
          "Result type: ${result.type.name}, message: ${result.message}";
      errorMessages.add(errorMsg);
      _logger.warning("open_file failed",
          tag: "UpdateChecker", metadata: {"result": result.type.name});
    } catch (e) {
      final errorMsg = e.toString();
      errorMessages.add(errorMsg);
      _logger.warning("open_file failed",
          tag: "UpdateChecker", metadata: {"error": e.toString()});
    }

    // Method 2: Try apk_sideload
    attemptedMethods.add("APK Sideload");
    try {
      _logger.info("Attempting installation with apk_sideload",
          tag: "UpdateChecker");
      await InstallApk().installApk(filePath);
      _logger.info("apk_sideload installation initiated", tag: "UpdateChecker");

      // Show user that installer was opened
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
                "Opening installer... If nothing happens, the install failed."),
            duration: const Duration(seconds: 5),
            action: SnackBarAction(
              label: "Manual Install",
              onPressed: () {
                if (context.mounted) {
                  _showInstallFallbackDialog(context, filePath,
                      attemptedMethods, ["May have failed silently"], release);
                }
              },
            ),
          ),
        );
      }
      return true;
    } on PlatformException catch (e) {
      final errorMsg = "PlatformException: ${e.message ?? "Unknown error"}";
      errorMessages.add(errorMsg);
      _logger.warning("apk_sideload failed",
          tag: "UpdateChecker", metadata: {"error": e.message});
    } catch (e) {
      final errorMsg = e.toString();
      errorMessages.add(errorMsg);
      _logger.warning("apk_sideload failed",
          tag: "UpdateChecker", metadata: {"error": e.toString()});
    }

    // Method 3: Try android_package_installer
    attemptedMethods.add("Package Installer");
    try {
      _logger.info("Attempting installation with android_package_installer",
          tag: "UpdateChecker");
      final statusCode = await AndroidPackageInstaller.installApk(
        apkFilePath: filePath,
      );
      if (statusCode != null) {
        final status = PackageInstallerStatus.byCode(statusCode);
        _logger.info("android_package_installer result",
            tag: "UpdateChecker",
            metadata: {"status": status.name, "code": statusCode});
        if (status == PackageInstallerStatus.success) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text(
                    "Opening installer... If nothing happens, the install failed."),
                duration: const Duration(seconds: 5),
                action: SnackBarAction(
                  label: "Manual Install",
                  onPressed: () {
                    if (context.mounted) {
                      _showInstallFallbackDialog(
                          context,
                          filePath,
                          attemptedMethods,
                          ["May have failed silently"],
                          release);
                    }
                  },
                ),
              ),
            );
          }
          return true;
        } else {
          final errorMsg = "Status: ${status.name} (code: $statusCode)";
          errorMessages.add(errorMsg);
        }
      } else {
        errorMessages.add("Returned null status code");
      }
    } catch (e) {
      final errorMsg = e.toString();
      errorMessages.add(errorMsg);
      _logger.warning("android_package_installer failed",
          tag: "UpdateChecker", metadata: {"error": e.toString()});
    }

    // All automatic methods failed - show fallback dialog with error details
    _logger.error("All installation methods failed",
        tag: "UpdateChecker",
        metadata: {
          "attemptedMethods": attemptedMethods,
          "errors": errorMessages,
        });

    if (context.mounted) {
      await _showInstallFallbackDialog(
          context, filePath, attemptedMethods, errorMessages, release);
    }
    return false;
  }

  // Show fallback dialog with manual options when automatic installation fails
  Future<void> _showInstallFallbackDialog(BuildContext context, String filePath,
      [List<String>? attemptedMethods,
      List<String>? errorMessages,
      ReleaseInfo? release]) async {
    final fileName = filePath.split("/").last;
    final hasErrors = errorMessages != null && errorMessages.isNotEmpty;
    final hasMethods = attemptedMethods != null && attemptedMethods.isNotEmpty;

    await showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 28),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  "Installation Issue",
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "The automatic installer couldn't open the APK. This can happen on some Android versions.\n\n"
                  "You can install manually using one of these options:",
                ),
                const SizedBox(height: 16),
                Text(
                  "File: $fileName",
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(dialogContext)
                        .colorScheme
                        .tertiary
                        .withValues(alpha: 0.7),
                  ),
                ),
                // Show attempted methods and errors for debugging
                if (hasMethods || hasErrors) ...[
                  const SizedBox(height: 16),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Theme.of(dialogContext)
                          .colorScheme
                          .errorContainer
                          .withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: Theme.of(dialogContext)
                            .colorScheme
                            .error
                            .withValues(alpha: 0.3),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "Installation Failed",
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: Theme.of(dialogContext).colorScheme.error,
                          ),
                        ),
                        const SizedBox(height: 8),
                        if (hasMethods) ...[
                          Text(
                            "Methods tried:",
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Theme.of(dialogContext)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 4),
                          ...attemptedMethods.map((method) => Text(
                                "• $method",
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Theme.of(dialogContext)
                                      .colorScheme
                                      .onSurfaceVariant,
                                ),
                              )),
                        ],
                        if (hasErrors) ...[
                          const SizedBox(height: 8),
                          Text(
                            "Errors encountered:",
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Theme.of(dialogContext).colorScheme.error,
                            ),
                          ),
                          const SizedBox(height: 4),
                          ...errorMessages.asMap().entries.map((entry) {
                            final index = entry.key;
                            final error = entry.value;
                            final methodName =
                                hasMethods && index < attemptedMethods.length
                                    ? attemptedMethods[index]
                                    : "Method ${index + 1}";
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: SelectableText(
                                "$methodName: $error",
                                style: TextStyle(
                                  fontSize: 11,
                                  fontFamily: "monospace",
                                  color:
                                      Theme.of(dialogContext).colorScheme.error,
                                ),
                              ),
                            );
                          }),
                        ],
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(
                "Cancel",
                style: TextStyle(
                  color: Theme.of(dialogContext)
                      .colorScheme
                      .tertiary
                      .withValues(alpha: 0.7),
                ),
              ),
            ),
            if (release != null)
              TextButton(
                onPressed: () async {
                  Navigator.of(dialogContext).pop();
                  final url = getDownloadUrlForPlatform(release);
                  final targetUrl = url ?? release.htmlUrl;
                  final uri = Uri.parse(targetUrl);
                  if (await canLaunchUrl(uri)) {
                    await launchUrl(uri, mode: LaunchMode.externalApplication);
                  }
                },
                child: Text(
                  "Download via Browser",
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Theme.of(dialogContext).colorScheme.secondary,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  // Show error dialog with fallback options
  Future<void> _showInstallErrorDialog(
      BuildContext context, String filePath, String errorMessage,
      {ReleaseInfo? release}) async {
    await showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.error_outline, color: Colors.red, size: 28),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  "Installation Error",
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          content: Text(errorMessage),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(
                "OK",
                style: TextStyle(
                  color: Theme.of(dialogContext).colorScheme.secondary,
                ),
              ),
            ),
            if (File(filePath).existsSync())
              TextButton(
                onPressed: () async {
                  Navigator.of(dialogContext).pop();
                  await _showInstallFallbackDialog(
                      context, filePath, null, null, release);
                },
                child: Text(
                  "Try Manual Install",
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Theme.of(dialogContext).colorScheme.secondary,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return "$bytes B";
    if (bytes < 1024 * 1024) return "${(bytes / 1024).toStringAsFixed(1)} KB";
    return "${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB";
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
    if (downloadedFilePath != null && context.mounted) {
      try {
        await openUpdateFile(downloadedFilePath!, context, release: release);
      } catch (e) {
        // Show error to user
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text("Failed to install update: $e"),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
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
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: Row(
            children: [
              Icon(Icons.system_update,
                  color: Theme.of(dialogContext).colorScheme.secondary),
              const SizedBox(width: 10),
              Text(
                "Update Available",
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Theme.of(dialogContext).colorScheme.secondary,
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
                    color: Theme.of(dialogContext).colorScheme.tertiary,
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
                      color: Theme.of(dialogContext).colorScheme.tertiary,
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
                          color: Theme.of(dialogContext)
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
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(
                "Later",
                style: TextStyle(
                  color: Theme.of(dialogContext)
                      .colorScheme
                      .tertiary
                      .withValues(alpha: 0.7),
                ),
              ),
            ),
            // Show download button for mobile when URL exists
            if (downloadUrl != null && (Platform.isAndroid || Platform.isIOS))
              TextButton(
                onPressed: () async {
                  Navigator.of(dialogContext).pop();
                  if (context.mounted) {
                    await _showUpdateDownloadDialog(context, release);
                  }
                },
                child: Text(
                  "Download & Install",
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Theme.of(dialogContext).colorScheme.secondary,
                  ),
                ),
              ),
            // Show download button for desktop (direct download or open GitHub)
            if (Platform.isWindows || Platform.isLinux || Platform.isMacOS)
              TextButton(
                onPressed: () async {
                  Navigator.of(dialogContext).pop();
                  if (downloadUrl != null && context.mounted) {
                    await _showUpdateDownloadDialog(context, release);
                  } else {
                    final uri = Uri.parse(release.htmlUrl);
                    if (await canLaunchUrl(uri)) {
                      await launchUrl(uri,
                          mode: LaunchMode.externalApplication);
                    }
                  }
                },
                child: Text(
                  downloadUrl != null
                      ? "Download & Install"
                      : "Download from GitHub",
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Theme.of(dialogContext).colorScheme.secondary,
                  ),
                ),
              ),
            // Fallback for mobile when no download URL
            if (downloadUrl == null && (Platform.isAndroid || Platform.isIOS))
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
