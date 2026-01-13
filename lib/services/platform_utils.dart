// Dart imports:
import 'dart:io' show Platform;

// Platform utility functions for desktop support
class PlatformUtils {
  // Check if running on a mobile platform (Android or iOS)
  static bool get isMobile => Platform.isAndroid || Platform.isIOS;

  // Check if running on a desktop platform (Linux, Windows, or macOS)
  static bool get isDesktop =>
      Platform.isLinux || Platform.isWindows || Platform.isMacOS;

  // Check if WebView is supported on the current platform
  static bool get isWebViewSupported =>
      Platform.isAndroid ||
      Platform.isIOS ||
      Platform.isMacOS ||
      Platform.isWindows;

  // Check if in-app PDF viewing is supported
  static bool get isPdfViewerSupported => Platform.isAndroid || Platform.isIOS;

  // Check if notifications are fully supported
  static bool get isNotificationSupported => Platform.isAndroid;

  // Check if running on Linux (no WebView support)
  static bool get isLinux => Platform.isLinux;

  // Check if running on Windows
  static bool get isWindows => Platform.isWindows;

  // Check if running on Android
  static bool get isAndroid => Platform.isAndroid;

  // Check if running on macOS
  static bool get isMacOS => Platform.isMacOS;
}
