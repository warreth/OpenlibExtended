// User-friendly error display widget with solutions
// Handles network errors, Cloudflare blocks, connectivity issues

// Flutter imports:
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// Package imports:
import 'package:flutter_svg/svg.dart';

// Project imports:
import 'package:openlib/services/network_error.dart';
import 'package:openlib/services/logger.dart';

class CustomErrorWidget extends StatelessWidget {
  final Object error;
  final StackTrace stackTrace;
  final VoidCallback? onRefresh;

  CustomErrorWidget({
    super.key,
    required this.error,
    required this.stackTrace,
    this.onRefresh,
  }) {
    // Log the error for debugging
    final logger = AppLogger();
    logger.error(
      "Error displayed to user",
      tag: "ErrorWidget",
      error: error,
      stackTrace: stackTrace,
    );
  }

  @override
  Widget build(BuildContext context) {
    // Convert error to NetworkError for unified handling
    final networkError = _parseError(error);

    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 40),
            _buildErrorIcon(context, networkError.type),
            const SizedBox(height: 24),
            _buildErrorTitle(context, networkError),
            const SizedBox(height: 16),
            _buildSolutionCard(context, networkError),
            const SizedBox(height: 24),
            if (onRefresh != null) _buildRefreshButton(context),
            const SizedBox(height: 16),
            if (networkError.rawResponseBody != null)
              _buildShowDetailsButton(context, networkError),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  // Parse any error into a NetworkError
  NetworkError _parseError(Object error) {
    if (error is NetworkError) {
      return error;
    }

    // Check for legacy socket exception marker
    if (error.toString().contains("socketException")) {
      return NetworkError(
        type: NetworkErrorType.noInternet,
        userMessage: "Unable to access the internet",
        solution:
            "Check your internet connection. Make sure WiFi or mobile data is enabled.",
      );
    }

    // Convert to NetworkError
    return NetworkError.fromException(error);
  }

  // Build appropriate icon based on error type
  Widget _buildErrorIcon(BuildContext context, NetworkErrorType type) {
    String assetPath;
    Color? iconColor;

    switch (type) {
      case NetworkErrorType.noInternet:
      case NetworkErrorType.dnsError:
        assetPath = "assets/no_internet.svg";
        break;
      case NetworkErrorType.cloudflareBlock:
      case NetworkErrorType.forbidden:
        assetPath = "assets/error_fixing_bugs.svg";
        iconColor = Colors.orange;
        break;
      case NetworkErrorType.timeout:
      case NetworkErrorType.serverUnavailable:
        assetPath = "assets/error_fixing_bugs.svg";
        break;
      default:
        assetPath = "assets/error_fixing_bugs.svg";
    }

    return Center(
      child: SvgPicture.asset(
        assetPath,
        width: 180,
        height: 180,
        colorFilter: iconColor != null
            ? ColorFilter.mode(iconColor, BlendMode.srcIn)
            : null,
      ),
    );
  }

  // Build error title with icon indicator
  Widget _buildErrorTitle(BuildContext context, NetworkError networkError) {
    IconData iconData;
    Color iconColor;

    switch (networkError.type) {
      case NetworkErrorType.noInternet:
        iconData = Icons.wifi_off_rounded;
        iconColor = Colors.red;
        break;
      case NetworkErrorType.cloudflareBlock:
        iconData = Icons.shield_rounded;
        iconColor = Colors.orange;
        break;
      case NetworkErrorType.forbidden:
        iconData = Icons.block_rounded;
        iconColor = Colors.red;
        break;
      case NetworkErrorType.timeout:
        iconData = Icons.timer_off_rounded;
        iconColor = Colors.amber;
        break;
      case NetworkErrorType.serverUnavailable:
        iconData = Icons.cloud_off_rounded;
        iconColor = Colors.grey;
        break;
      case NetworkErrorType.rateLimited:
        iconData = Icons.speed_rounded;
        iconColor = Colors.orange;
        break;
      case NetworkErrorType.dnsError:
        iconData = Icons.dns_rounded;
        iconColor = Colors.purple;
        break;
      case NetworkErrorType.sslError:
        iconData = Icons.lock_open_rounded;
        iconColor = Colors.red;
        break;
      default:
        iconData = Icons.error_outline_rounded;
        iconColor = Colors.red;
    }

    return Column(
      children: [
        Icon(iconData, size: 48, color: iconColor),
        const SizedBox(height: 12),
        Text(
          networkError.userMessage,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
      ],
    );
  }

  // Build solution card with actionable advice
  Widget _buildSolutionCard(BuildContext context, NetworkError networkError) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.grey[850]
            : _getBackgroundColorForType(networkError.type),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _getBorderColorForType(networkError.type),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.lightbulb_outline_rounded,
                color: _getAccentColorForType(networkError.type),
                size: 24,
              ),
              const SizedBox(width: 8),
              Text(
                "What to do",
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: _getAccentColorForType(networkError.type),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            networkError.solution,
            style: TextStyle(
              fontSize: 15,
              height: 1.5,
              color: isDark ? Colors.grey[300] : Colors.grey[800],
            ),
          ),
          // Show VPN recommendation prominently for blocked content
          if (networkError.type == NetworkErrorType.cloudflareBlock ||
              networkError.type == NetworkErrorType.dnsError ||
              networkError.type == NetworkErrorType.forbidden) ...[
            const SizedBox(height: 16),
            _buildVpnRecommendation(context),
          ],
        ],
      ),
    );
  }

  // Build VPN recommendation banner
  Widget _buildVpnRecommendation(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.blue.withAlpha(30),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blue.withAlpha(80)),
      ),
      child: Row(
        children: [
          const Icon(Icons.vpn_key_rounded, color: Colors.blue, size: 32),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "Try using a VPN",
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: Colors.blue,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  "A VPN can help bypass regional blocks and access the content.",
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.blue[800],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Build refresh button
  Widget _buildRefreshButton(BuildContext context) {
    return Center(
      child: ElevatedButton.icon(
        onPressed: onRefresh,
        icon: const Icon(Icons.refresh_rounded),
        label: const Text("Try Again"),
        style: ElevatedButton.styleFrom(
          backgroundColor: Theme.of(context).colorScheme.secondary,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(25),
          ),
        ),
      ),
    );
  }

  // Build show details button for advanced users
  Widget _buildShowDetailsButton(
      BuildContext context, NetworkError networkError) {
    return Center(
      child: TextButton.icon(
        onPressed: () => _showDetailsDialog(context, networkError),
        icon: const Icon(Icons.info_outline_rounded, size: 18),
        label: const Text("Show blocked page content"),
        style: TextButton.styleFrom(
          foregroundColor: Colors.grey[600],
        ),
      ),
    );
  }

  // Show dialog with raw response for debugging
  void _showDetailsDialog(BuildContext context, NetworkError networkError) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.code_rounded, size: 24),
            SizedBox(width: 8),
            Text("Blocked Page Content"),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (networkError.technicalDetails != null) ...[
                  Text(
                    "Error: ${networkError.technicalDetails}",
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: SelectableText(
                    _formatResponseBody(
                        networkError.rawResponseBody ?? "No content available"),
                    style: const TextStyle(
                      fontFamily: "monospace",
                      fontSize: 11,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(
                text: networkError.rawResponseBody ?? "",
              ));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text("Copied to clipboard")),
              );
            },
            child: const Text("Copy"),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Close"),
          ),
        ],
      ),
    );
  }

  // Format response body for display
  String _formatResponseBody(String body) {
    // Limit length for display
    if (body.length > 3000) {
      return "${body.substring(0, 3000)}\n\n... (truncated, ${body.length} total characters)";
    }
    return body;
  }

  // Get background color based on error type
  Color _getBackgroundColorForType(NetworkErrorType type) {
    switch (type) {
      case NetworkErrorType.cloudflareBlock:
      case NetworkErrorType.forbidden:
        return Colors.orange.withAlpha(25);
      case NetworkErrorType.noInternet:
      case NetworkErrorType.dnsError:
        return Colors.red.withAlpha(20);
      case NetworkErrorType.timeout:
      case NetworkErrorType.rateLimited:
        return Colors.amber.withAlpha(25);
      case NetworkErrorType.serverUnavailable:
        return Colors.grey.withAlpha(30);
      default:
        return Colors.grey.withAlpha(25);
    }
  }

  // Get border color based on error type
  Color _getBorderColorForType(NetworkErrorType type) {
    switch (type) {
      case NetworkErrorType.cloudflareBlock:
      case NetworkErrorType.forbidden:
        return Colors.orange.withAlpha(60);
      case NetworkErrorType.noInternet:
      case NetworkErrorType.dnsError:
        return Colors.red.withAlpha(50);
      case NetworkErrorType.timeout:
      case NetworkErrorType.rateLimited:
        return Colors.amber.withAlpha(60);
      default:
        return Colors.grey.withAlpha(50);
    }
  }

  // Get accent color based on error type
  Color _getAccentColorForType(NetworkErrorType type) {
    switch (type) {
      case NetworkErrorType.cloudflareBlock:
      case NetworkErrorType.forbidden:
        return Colors.orange[700]!;
      case NetworkErrorType.noInternet:
      case NetworkErrorType.dnsError:
        return Colors.red[700]!;
      case NetworkErrorType.timeout:
      case NetworkErrorType.rateLimited:
        return Colors.amber[800]!;
      default:
        return Colors.grey[700]!;
    }
  }
}

// Simple error snackbar for quick inline errors
class ErrorSnackbar {
  static void show(BuildContext context, Object error,
      {VoidCallback? onRetry}) {
    final networkError =
        error is NetworkError ? error : NetworkError.fromException(error);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              networkError.userMessage,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              networkError.solution.split("\n").first,
              style: const TextStyle(fontSize: 12),
            ),
          ],
        ),
        action: onRetry != null
            ? SnackBarAction(
                label: "Retry",
                onPressed: onRetry,
              )
            : null,
        duration: const Duration(seconds: 5),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
