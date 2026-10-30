// Dart imports:
import 'dart:async';

// Package imports:
import 'package:dio/dio.dart';

// Project imports:
import 'package:openlib/core/slum.dart';

/// Reads the Anna's Archive mirror list from open-slum.org.
///
/// Parsing and ordering come from [parseSlumPage] / [sortSlumSites] in the
/// shared core, so the CLI sees exactly the same mirrors and order as the app.
/// The app rule is "mirror URLs come only from open-slum.org - nothing
/// hardcodes a provider host"; this class keeps that rule for the CLI.
class CliSlumCatalogue {
  CliSlumCatalogue({Dio? dio, String? baseUrl})
      : _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 20),
              headers: const {
                'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
                    'AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0 '
                    'Safari/537.36',
              },
            )),
        _baseUrl = baseUrl ?? defaultBaseUrl;

  final Dio _dio;
  final String _baseUrl;

  /// The one host the CLI is allowed to hardcode: the monitor itself.
  static const String defaultBaseUrl = slumDefaultBaseUrl;

  /// SLUM's Anna's Archive page.
  static const String annasPage = 'annas.html';

  /// Fetches every Anna's Archive mirror SLUM reports, including down ones.
  /// Callers that want to attempt requests filter with [SlumSite.isDown].
  Future<List<SlumSite>> fetchAnnasMirrors() async {
    try {
      final response = await _dio.get<String>('$_baseUrl/$annasPage');
      if (response.statusCode != 200 || response.data == null) {
        return const [];
      }
      return parsePage(response.data!);
    } catch (_) {
      return const [];
    }
  }

  /// Parses one SLUM service page. Mirrors the app-side parser through the
  /// shared core.
  List<SlumSite> parsePage(String html) =>
      parseSlumPage(html, service: MirrorService.annasArchive);

  /// Adds the scheme when missing and strips the trailing slash, so
  /// callers can join paths directly.
  static String normalizeUrl(String href) => normalizeSlumUrl(href);
}
