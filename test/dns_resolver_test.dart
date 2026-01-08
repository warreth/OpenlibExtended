// Flutter imports:
import 'package:flutter_test/flutter_test.dart';

// Project imports:
import 'package:openlib/services/dns_resolver.dart';

void main() {
  group('DnsResolverService', () {
    test('DNS provider configuration is correct', () {
      expect(DnsProviders.builtIn.length, greaterThan(0));
      expect(DnsProviders.defaultProvider, isNotNull);
      expect(DnsProviders.defaultProvider.name, equals('Cloudflare'));
    });

    test('DnsResolverService can be instantiated', () {
      final dnsResolver = DnsResolverService();
      expect(dnsResolver, isNotNull);
      expect(dnsResolver.currentProvider, isNotNull);
      expect(dnsResolver.isDohEnabled, isTrue);
    });

    test('Can set DNS provider', () {
      final dnsResolver = DnsResolverService();
      final googleProvider = DnsProviders.builtIn.firstWhere(
        (provider) => provider.name == 'Google',
      );
      
      dnsResolver.setProvider(googleProvider);
      expect(dnsResolver.currentProvider.name, equals('Google'));
    });

    test('Can enable/disable DoH', () {
      final dnsResolver = DnsResolverService();
      
      expect(dnsResolver.isDohEnabled, isTrue);
      
      dnsResolver.setDohEnabled(false);
      expect(dnsResolver.isDohEnabled, isFalse);
      
      dnsResolver.setDohEnabled(true);
      expect(dnsResolver.isDohEnabled, isTrue);
    });

    test('Available providers list is correct', () {
      final dnsResolver = DnsResolverService();
      final providers = dnsResolver.availableProviders;
      
      expect(providers, isNotEmpty);
      expect(providers.length, equals(DnsProviders.builtIn.length));
    });

    test('Cycling through providers works', () {
      final dnsResolver = DnsResolverService();
      final initialProvider = dnsResolver.currentProvider;
      
      dnsResolver.cycleToNextProvider();
      expect(dnsResolver.currentProvider, isNot(equals(initialProvider)));
    });
  });

  group('DnsProvider', () {
    test('Can create DnsProvider', () {
      const provider = DnsProvider(
        name: 'Test',
        url: 'https://test.com/dns-query',
      );
      
      expect(provider.name, equals('Test'));
      expect(provider.url, equals('https://test.com/dns-query'));
      expect(provider.isCustom, isFalse);
    });

    test('Can serialize/deserialize DnsProvider', () {
      const provider = DnsProvider(
        name: 'Custom',
        url: 'https://custom.com/dns-query',
        isCustom: true,
      );
      
      final json = provider.toJson();
      expect(json['name'], equals('Custom'));
      expect(json['url'], equals('https://custom.com/dns-query'));
      expect(json['isCustom'], isTrue);
      
      final restored = DnsProvider.fromJson(json);
      expect(restored.name, equals(provider.name));
      expect(restored.url, equals(provider.url));
      expect(restored.isCustom, equals(provider.isCustom));
    });
  });
}
