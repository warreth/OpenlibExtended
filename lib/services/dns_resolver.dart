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
  DnsResolverService._internal();

  final AppLogger _logger = AppLogger();
  final Dio _dio = Dio();
  
  DnsProvider _currentProvider = DnsProviders.defaultProvider;
  int _currentProviderIndex = 0;
  final List<DnsProvider> _availableProviders = List.from(DnsProviders.builtIn);

  /// Get current DNS provider
  DnsProvider get currentProvider => _currentProvider;

  /// Get all available providers (built-in + custom)
  List<DnsProvider> get availableProviders => List.unmodifiable(_availableProviders);

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
    _logger.info('Cycled to next DNS provider', tag: 'DnsResolver', metadata: {
      'provider': _currentProvider.name,
    });
  }

  /// Resolve domain using DNS-over-HTTPS
  Future<List<String>> resolveDomain(String domain) async {
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

          return ipAddresses;
        }
      }

      _logger.warning('No DNS records found', tag: 'DnsResolver', metadata: {
        'domain': domain,
      });
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
        
        // Disable system DNS and use custom resolution
        client.connectionFactory = (Uri uri, String? proxyHost, int? proxyPort) async {
          final addresses = await resolveDomain(uri.host);
          
          if (addresses.isEmpty) {
            // Fallback to system DNS if DoH fails
            _logger.warning('DoH failed, falling back to system DNS', tag: 'DnsResolver', metadata: {
              'host': uri.host,
            });
            return Socket.connect(uri.host, uri.port);
          }
          
          // Try each resolved IP address
          for (final address in addresses) {
            try {
              _logger.debug('Connecting to resolved IP', tag: 'DnsResolver', metadata: {
                'host': uri.host,
                'ip': address,
                'port': uri.port,
              });
              
              return await Socket.connect(
                address,
                uri.port,
                timeout: const Duration(seconds: 10),
              ).then((socket) {
                // Set the original host for SNI (Server Name Indication)
                return socket;
              });
            } catch (e) {
              _logger.warning('Failed to connect to IP', tag: 'DnsResolver', metadata: {
                'ip': address,
                'error': e.toString(),
              });
              continue;
            }
          }
          
          // If all resolved IPs fail, throw error
          throw SocketException('Failed to connect to any resolved IP addresses for ${uri.host}');
        };
        
        return client;
      };
      
      _logger.info('Dio configured with DNS-over-HTTPS', tag: 'DnsResolver', metadata: {
        'provider': _currentProvider.name,
      });
    }
  }
}
