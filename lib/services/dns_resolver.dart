// Dart imports:
import 'dart:io';

// Package imports:
import 'package:dio/dio.dart';
import 'package:dio/io.dart';

// Project imports:
import 'package:openlib/services/logger.dart';

/// DNS-over-HTTPS provider configuration
class DnsProvider {
  final String name;
  final String url;
  final bool isCustom;

  const DnsProvider({
    required this.name,
    required this.url,
    this.isCustom = false,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'url': url,
        'isCustom': isCustom,
      };

  factory DnsProvider.fromJson(Map<String, dynamic> json) => DnsProvider(
        name: json['name'],
        url: json['url'],
        isCustom: json['isCustom'] ?? false,
      );
}

/// Popular DNS-over-HTTPS providers
class DnsProviders {
  static const List<DnsProvider> builtIn = [
    DnsProvider(
      name: 'Cloudflare',
      url: 'https://cloudflare-dns.com/dns-query',
    ),
    DnsProvider(
      name: 'Google',
      url: 'https://dns.google/dns-query',
    ),
    DnsProvider(
      name: 'Quad9',
      url: 'https://dns.quad9.net/dns-query',
    ),
    DnsProvider(
      name: 'AdGuard',
      url: 'https://dns.adguard.com/dns-query',
    ),
    DnsProvider(
      name: 'OpenDNS',
      url: 'https://doh.opendns.com/dns-query',
    ),
  ];

  static DnsProvider get defaultProvider => builtIn[0]; // Cloudflare
}

/// DNS-over-HTTPS resolver service
class DnsResolverService {
  static final DnsResolverService _instance = DnsResolverService._internal();
  factory DnsResolverService() => _instance;
  DnsResolverService._internal() {
    // Configure the internal Dio instance to NOT use DoH (to avoid circular dependency)
    // This Dio instance is only used to query DoH servers and should use system DNS
    _dio.options.receiveTimeout = const Duration(seconds: 5);
    _dio.options.sendTimeout = const Duration(seconds: 5);
    _dio.options.connectTimeout = const Duration(seconds: 5);
  }

  final AppLogger _logger = AppLogger();
  final Dio _dio = Dio(); // This Dio MUST use system DNS to reach DoH servers
  
  DnsProvider _currentProvider = DnsProviders.defaultProvider;
  int _currentProviderIndex = 0;
  final List<DnsProvider> _availableProviders = List.from(DnsProviders.builtIn);
  bool _dohEnabled = true; // Flag to track if DoH should be used
  
  // Track consecutive failures to disable DoH if all providers fail
  int _consecutiveFailures = 0;
  static const int _maxConsecutiveFailures = 10; // Disable DoH after this many failures

  /// Get current DNS provider
  DnsProvider get currentProvider => _currentProvider;

  /// Get all available providers (built-in + custom)
  List<DnsProvider> get availableProviders => List.unmodifiable(_availableProviders);

  /// Check if DoH is currently enabled
  bool get isDohEnabled => _dohEnabled;

  /// Enable or disable DoH
  void setDohEnabled(bool enabled) {
    _dohEnabled = enabled;
    _logger.info('DoH ${enabled ? "enabled" : "disabled"}', tag: 'DnsResolver');
  }

  /// Set current DNS provider
  void setProvider(DnsProvider provider) {
    _logger.info('Switching DNS provider', tag: 'DnsResolver', metadata: {
      'from': _currentProvider.name,
      'to': provider.name,
    });
    _currentProvider = provider;
    _currentProviderIndex = _availableProviders.indexOf(provider);
  }

  /// Add a custom DNS provider
  void addCustomProvider(String name, String url) {
    final customProvider = DnsProvider(
      name: name,
      url: url,
      isCustom: true,
    );
    _availableProviders.add(customProvider);
    _logger.info('Added custom DNS provider', tag: 'DnsResolver', metadata: {
      'name': name,
      'url': url,
    });
  }

  /// Remove a custom DNS provider
  void removeCustomProvider(DnsProvider provider) {
    if (provider.isCustom) {
      _availableProviders.remove(provider);
      _logger.info('Removed custom DNS provider', tag: 'DnsResolver', metadata: {
        'name': provider.name,
      });
      
      // If the removed provider was current, switch to default
      if (_currentProvider == provider) {
        setProvider(DnsProviders.defaultProvider);
      }
    }
  }

  /// Cycle to the next DNS provider (useful for fallback)
  void cycleToNextProvider() {
    _currentProviderIndex = (_currentProviderIndex + 1) % _availableProviders.length;
    _currentProvider = _availableProviders[_currentProviderIndex];
    _consecutiveFailures++;
    
    _logger.info('Cycled to next DNS provider', tag: 'DnsResolver', metadata: {
      'provider': _currentProvider.name,
      'consecutiveFailures': _consecutiveFailures,
    });
    
    // If we've cycled through all providers multiple times, disable DoH
    if (_consecutiveFailures >= _maxConsecutiveFailures) {
      _logger.warning('Too many consecutive DoH failures, disabling DoH', tag: 'DnsResolver', metadata: {
        'failures': _consecutiveFailures,
      });
      _dohEnabled = false;
      _consecutiveFailures = 0; // Reset counter
    }
  }

  /// Resolve domain using DNS-over-HTTPS
  Future<List<String>> resolveDomain(String domain) async {
    // If DoH is disabled, return empty to force system DNS fallback
    if (!_dohEnabled) {
      return [];
    }

    _logger.debug('Resolving domain', tag: 'DnsResolver', metadata: {
      'domain': domain,
      'provider': _currentProvider.name,
    });

    try {
      final response = await _dio.get(
        _currentProvider.url,
        queryParameters: {
          'name': domain,
          'type': 'A', // IPv4 addresses
        },
        options: Options(
          headers: {
            'Accept': 'application/dns-json',
          },
          receiveTimeout: const Duration(seconds: 5),
          sendTimeout: const Duration(seconds: 5),
          validateStatus: (status) {
            // Accept 200 OK responses, treat everything else as an error
            return status == 200;
          },
        ),
      );

      if (response.statusCode == 200 && response.data != null) {
        final answers = response.data['Answer'] as List<dynamic>?;
        if (answers != null && answers.isNotEmpty) {
          final ipAddresses = answers
              .where((answer) => answer['type'] == 1) // Type A records
              .map((answer) => answer['data'] as String)
              .toList();

          _logger.info('Domain resolved successfully', tag: 'DnsResolver', metadata: {
            'domain': domain,
            'ips': ipAddresses.length,
            'provider': _currentProvider.name,
          });

          // Reset consecutive failures on success
          _consecutiveFailures = 0;

          return ipAddresses;
        }
      }

      _logger.warning('No DNS records found', tag: 'DnsResolver', metadata: {
        'domain': domain,
      });
      return [];
    } on DioException catch (e, stackTrace) {
      // Log the specific error type
      if (e.response?.statusCode == 400) {
        _logger.warning('DoH provider returned 400 Bad Request - provider may not support the request format', 
          tag: 'DnsResolver', metadata: {
          'domain': domain,
          'provider': _currentProvider.name,
          'statusCode': e.response?.statusCode,
        });
      } else {
        _logger.error('DNS resolution failed', tag: 'DnsResolver', error: e, stackTrace: stackTrace, metadata: {
          'domain': domain,
          'provider': _currentProvider.name,
          'errorType': e.type.toString(),
        });
      }
      
      // Try cycling to next provider on failure
      cycleToNextProvider();
      return [];
    } catch (e, stackTrace) {
      _logger.error('DNS resolution failed', tag: 'DnsResolver', error: e, stackTrace: stackTrace, metadata: {
        'domain': domain,
        'provider': _currentProvider.name,
      });
      
      // Try cycling to next provider on failure
      cycleToNextProvider();
      return [];
    }
  }

  /// Configure a Dio instance to use DNS-over-HTTPS
  void configureDio(Dio dio) {
    if (dio.httpClientAdapter is IOHttpClientAdapter) {
      final adapter = dio.httpClientAdapter as IOHttpClientAdapter;
      
      adapter.createHttpClient = () {
        final client = HttpClient();
        
        // Only use custom DNS resolution if DoH is enabled
        client.connectionFactory = (Uri uri, String? proxyHost, int? proxyPort) async {
          // Skip DoH for localhost and IP addresses
          if (uri.host == 'localhost' || 
              uri.host == '127.0.0.1' ||
              RegExp(r'^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$').hasMatch(uri.host)) {
            return Socket.startConnect(uri.host, uri.port);
          }
          
          final addresses = await resolveDomain(uri.host);
          
          if (addresses.isEmpty) {
            // Fallback to system DNS if DoH fails or is disabled
            if (!_dohEnabled) {
              _logger.debug('DoH disabled, using system DNS', tag: 'DnsResolver', metadata: {
                'host': uri.host,
              });
            } else {
              _logger.warning('DoH failed, falling back to system DNS', tag: 'DnsResolver', metadata: {
                'host': uri.host,
              });
            }
            return Socket.startConnect(uri.host, uri.port);
          }
          
          // Try each resolved IP address
          for (final address in addresses) {
            try {
              _logger.debug('Connecting to resolved IP', tag: 'DnsResolver', metadata: {
                'host': uri.host,
                'ip': address,
                'port': uri.port,
              });
              
              return Socket.startConnect(
                address,
                uri.port,
              );
            } catch (e) {
              _logger.warning('Failed to connect to IP', tag: 'DnsResolver', metadata: {
                'ip': address,
                'error': e.toString(),
              });
              continue;
            }
          }
          
          // If all resolved IPs fail, fallback to system DNS as last resort
          _logger.warning('All resolved IPs failed, trying system DNS', tag: 'DnsResolver', metadata: {
            'host': uri.host,
          });
          return Socket.startConnect(uri.host, uri.port);
        };
        
        return client;
      };
      
      _logger.info('Dio configured with DNS-over-HTTPS', tag: 'DnsResolver', metadata: {
        'provider': _currentProvider.name,
        'enabled': _dohEnabled,
      });
    }
  }
}
