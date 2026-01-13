// Dart imports:
import 'dart:convert';
import 'dart:io';

// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

// Project imports:
import 'package:openlib/services/database.dart';
import 'package:openlib/services/logger.dart';
import 'package:openlib/services/platform_utils.dart';

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
      } else if (name.contains("windows") || name.endsWith(".exe") || name.endsWith("-windows-x64.zip")) {
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
  static final UpdateCheckerService _instance = UpdateCheckerService._internal();
  factory UpdateCheckerService() => _instance;
  UpdateCheckerService._internal();

  final AppLogger _logger = AppLogger();
  final MyLibraryDb _database = MyLibraryDb.instance;
  
  // GitHub repository information - update these for your repo
  static const String _owner = "warreth";
  static const String _repo = "OpenlibExtended";
  static const String _apiUrl = "https://api.github.com/repos";

  // Check for updates
  Future<UpdateCheckResult> checkForUpdates({bool includePrereleases = false}) async {
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
      _logger.error("Failed to check for updates", tag: "UpdateChecker", error: e, stackTrace: stackTrace);
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
      while (currentParts.length < 3) currentParts.add(0);
      while (latestParts.length < 3) latestParts.add(0);

      for (int i = 0; i < 3; i++) {
        if (latestParts[i] > currentParts[i]) return true;
        if (latestParts[i] < currentParts[i]) return false;
      }
      return false;
    } catch (e) {
      _logger.warning("Failed to parse version", tag: "UpdateChecker", metadata: {
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
  Future<void> showUpdateDialog(BuildContext context, ReleaseInfo release) async {
    final downloadUrl = getDownloadUrlForPlatform(release);
    
    return showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Row(
            children: [
              Icon(Icons.system_update, color: Theme.of(context).colorScheme.secondary),
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
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
                          color: Theme.of(context).colorScheme.tertiary.withValues(alpha: 0.8),
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
                  color: Theme.of(context).colorScheme.tertiary.withValues(alpha: 0.7),
                ),
              ),
            ),
            if (downloadUrl != null)
              TextButton(
                onPressed: () async {
                  Navigator.of(context).pop();
                  final uri = Uri.parse(downloadUrl);
                  if (await canLaunchUrl(uri)) {
                    await launchUrl(uri, mode: LaunchMode.externalApplication);
                  }
                },
                child: Text(
                  "Download",
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.secondary,
                  ),
                ),
              ),
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
      final result = await checkForUpdates(includePrereleases: includePrereleases);
      
      if (result.updateAvailable && result.latestRelease != null && context.mounted) {
        await showUpdateDialog(context, result.latestRelease!);
      }
    } catch (e) {
      _logger.error("Failed to check for updates", tag: "UpdateChecker", error: e);
      // Silently fail - don't show error to user for update checks
    }
  }
}
