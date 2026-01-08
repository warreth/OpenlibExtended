// Dart imports:
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

// Flutter imports:
import 'package:flutter/foundation.dart';

// Package imports:
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Log entry class to store individual log messages
class LogEntry {
  final DateTime timestamp;
  final String level;
  final String message;
  final String? tag;
  final dynamic error;
  final StackTrace? stackTrace;
  final Map<String, dynamic>? metadata;

  LogEntry({
    required this.timestamp,
    required this.level,
    required this.message,
    this.tag,
    this.error,
    this.stackTrace,
    this.metadata,
  });

  @override
  String toString() {
    final buffer = StringBuffer();
    buffer.write('[${_formatTimestamp(timestamp)}] ');
    buffer.write('[${level.padRight(7)}] ');
    if (tag != null) {
      buffer.write('[${tag!.padRight(20)}] ');
    }
    buffer.write(message);
    
    if (metadata != null && metadata!.isNotEmpty) {
      buffer.write('\n  Metadata: ${_formatJson(metadata!)}');
    }
    
    if (error != null) {
      buffer.write('\n  Error: $error');
    }
    
    if (stackTrace != null) {
      final stackLines = stackTrace.toString().split('\n').take(5).join('\n  ');
      buffer.write('\n  Stack trace:\n  $stackLines');
    }
    
    return buffer.toString();
  }

  String _formatTimestamp(DateTime dt) {
    return '${dt.hour.toString().padLeft(2, '0')}:'
           '${dt.minute.toString().padLeft(2, '0')}:'
           '${dt.second.toString().padLeft(2, '0')}.'
           '${dt.millisecond.toString().padLeft(3, '0')}';
  }

  String _formatJson(Map<String, dynamic> json) {
    try {
      return const JsonEncoder.withIndent('  ').convert(json);
    } catch (_) {
      return json.toString();
    }
  }
}

/// Logger service to capture and export app logs
class AppLogger {
  static final AppLogger _instance = AppLogger._internal();
  factory AppLogger() => _instance;
  AppLogger._internal();

  // Store logs for the past 5 minutes
  final Queue<LogEntry> _logs = Queue<LogEntry>();
  static const Duration _logRetentionDuration = Duration(minutes: 5);
  static const int _maxLogEntries = 1000; // Limit to prevent memory issues

  /// Add a log entry
  void _addLog(String level, String message, {String? tag, dynamic error, StackTrace? stackTrace, Map<String, dynamic>? metadata}) {
    final entry = LogEntry(
      timestamp: DateTime.now(),
      level: level,
      message: message,
      tag: tag,
      error: error,
      stackTrace: stackTrace,
      metadata: metadata,
    );

    _logs.addLast(entry);
    
    // Also print to console in debug mode
    if (kDebugMode) {
      debugPrint(entry.toString());
    }

    // Remove old logs
    _cleanOldLogs();
    
    // Limit log size
    while (_logs.length > _maxLogEntries) {
      _logs.removeFirst();
    }
  }

  /// Remove logs older than 5 minutes
  void _cleanOldLogs() {
    final cutoffTime = DateTime.now().subtract(_logRetentionDuration);
    while (_logs.isNotEmpty && _logs.first.timestamp.isBefore(cutoffTime)) {
      _logs.removeFirst();
    }
  }

  /// Log debug message
  void debug(String message, {String? tag, Map<String, dynamic>? metadata}) {
    _addLog('DEBUG', message, tag: tag, metadata: metadata);
  }

  /// Log info message
  void info(String message, {String? tag, Map<String, dynamic>? metadata}) {
    _addLog('INFO', message, tag: tag, metadata: metadata);
  }

  /// Log warning message
  void warning(String message, {String? tag, dynamic error, Map<String, dynamic>? metadata}) {
    _addLog('WARNING', message, tag: tag, error: error, metadata: metadata);
  }

  /// Log error message
  void error(String message, {String? tag, dynamic error, StackTrace? stackTrace, Map<String, dynamic>? metadata}) {
    _addLog('ERROR', message, tag: tag, error: error, stackTrace: stackTrace, metadata: metadata);
  }

  /// Log network request
  void networkRequest(String method, String url, {Map<String, dynamic>? headers, dynamic data}) {
    final metadata = <String, dynamic>{
      'method': method,
      'url': url,
    };
    
    if (headers != null && headers.isNotEmpty) {
      // Filter sensitive headers
      final safeHeaders = Map<String, dynamic>.from(headers);
      safeHeaders.removeWhere((key, value) => 
        key.toLowerCase().contains('authorization') || 
        key.toLowerCase().contains('cookie') ||
        key.toLowerCase().contains('token')
      );
      if (safeHeaders.isNotEmpty) {
        metadata['headers'] = safeHeaders;
      }
    }
    
    if (data != null) {
      metadata['body'] = _truncateData(data);
    }
    
    _addLog('NETWORK', 'Request: $method $url', tag: 'HTTP', metadata: metadata);
  }

  /// Log network response
  void networkResponse(String method, String url, int statusCode, {dynamic data, Duration? duration}) {
    final metadata = <String, dynamic>{
      'method': method,
      'url': url,
      'status': statusCode,
    };
    
    if (duration != null) {
      metadata['duration'] = '${duration.inMilliseconds}ms';
    }
    
    if (data != null) {
      metadata['response'] = _truncateData(data);
    }
    
    final level = statusCode >= 400 ? 'WARNING' : 'NETWORK';
    _addLog(level, 'Response: $method $url [$statusCode]', tag: 'HTTP', metadata: metadata);
  }

  /// Log network error
  void networkError(String method, String url, dynamic error, {StackTrace? stackTrace}) {
    final metadata = <String, dynamic>{
      'method': method,
      'url': url,
    };
    
    _addLog('ERROR', 'Network Error: $method $url', tag: 'HTTP', error: error, stackTrace: stackTrace, metadata: metadata);
  }

  /// Truncate large data for logging
  dynamic _truncateData(dynamic data, {int maxLength = 500}) {
    if (data == null) return null;
    
    final dataStr = data.toString();
    if (dataStr.length <= maxLength) {
      return data;
    }
    
    return '${dataStr.substring(0, maxLength)}... (truncated, ${dataStr.length} chars total)';
  }

  /// Get all logs as a formatted string
  String getAllLogs() {
    _cleanOldLogs();
    
    final buffer = StringBuffer();
    buffer.writeln('╔═══════════════════════════════════════════════════════════════╗');
    buffer.writeln('║              Openlib App Diagnostic Logs                     ║');
    buffer.writeln('╚═══════════════════════════════════════════════════════════════╝');
    buffer.writeln('');
    buffer.writeln('Generated: ${DateTime.now().toIso8601String()}');
    buffer.writeln('Log retention: Last ${_logRetentionDuration.inMinutes} minutes');
    buffer.writeln('Total entries: ${_logs.length}');
    buffer.writeln('');
    buffer.writeln('─────────────────────────────────────────────────────────────────');
    buffer.writeln('System Information');
    buffer.writeln('─────────────────────────────────────────────────────────────────');
    buffer.writeln('Platform: ${Platform.operatingSystem} ${Platform.operatingSystemVersion}');
    buffer.writeln('Dart version: ${Platform.version}');
    buffer.writeln('');
    buffer.writeln('─────────────────────────────────────────────────────────────────');
    buffer.writeln('Log Entries');
    buffer.writeln('─────────────────────────────────────────────────────────────────');
    buffer.writeln('');
    
    for (final log in _logs) {
      buffer.writeln(log.toString());
      buffer.writeln('');
    }
    
    buffer.writeln('─────────────────────────────────────────────────────────────────');
    buffer.writeln('End of Logs');
    buffer.writeln('─────────────────────────────────────────────────────────────────');
    
    return buffer.toString();
  }

  /// Export logs to a file and share
  Future<void> exportLogs() async {
    try {
      final logsContent = getAllLogs();
      
      // Get temporary directory
      final tempDir = await getTemporaryDirectory();
      final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-').replaceAll('.', '-');
      final file = File('${tempDir.path}/openlib_logs_$timestamp.txt');
      
      // Write logs to file
      await file.writeAsString(logsContent);
      
      // Share the file
      await Share.shareXFiles(
        [XFile(file.path)],
        subject: 'Openlib App Logs - $timestamp',
        text: 'Openlib app logs for the past ${_logRetentionDuration.inMinutes} minutes',
      );
      
      info('Logs exported successfully', tag: 'AppLogger');
    } catch (e, stackTrace) {
      error('Failed to export logs', tag: 'AppLogger', error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  /// Clear all logs
  void clearLogs() {
    _logs.clear();
    info('Logs cleared', tag: 'AppLogger');
  }

  /// Get log count
  int get logCount {
    _cleanOldLogs();
    return _logs.length;
  }
}

/// Dio interceptor for automatic network request/response logging
class LoggingInterceptor extends Interceptor {
  final AppLogger _logger = AppLogger();

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    _logger.networkRequest(
      options.method,
      options.uri.toString(),
      headers: options.headers,
      data: options.data,
    );
    super.onRequest(options, handler);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    final duration = DateTime.now().difference(
      response.requestOptions.extra['request_time'] ?? DateTime.now(),
    );
    
    _logger.networkResponse(
      response.requestOptions.method,
      response.requestOptions.uri.toString(),
      response.statusCode ?? 0,
      data: response.data,
      duration: duration,
    );
    super.onResponse(response, handler);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    _logger.networkError(
      err.requestOptions.method,
      err.requestOptions.uri.toString(),
      err.message ?? err.error,
      stackTrace: err.stackTrace,
    );
    super.onError(err, handler);
  }
}

/// Helper to create a Dio instance with logging enabled
Dio createDioWithLogging({BaseOptions? options}) {
  final dio = Dio(options);
  dio.interceptors.add(LoggingInterceptor());
  
  // Add request time tracking
  dio.interceptors.add(InterceptorsWrapper(
    onRequest: (options, handler) {
      options.extra['request_time'] = DateTime.now();
      handler.next(options);
    },
  ));
  
  return dio;
}
