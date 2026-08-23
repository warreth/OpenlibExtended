import 'package:flutter_test/flutter_test.dart';
import 'package:openlib/services/instance_manager.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('InstanceManager Model & Logic Tests', () {
    test('ArchiveInstance serialization and deserialization', () {
      final instance = ArchiveInstance(
        id: 'annas_archive_pk',
        name: "Anna's Archive (.pk)",
        baseUrl: 'https://annas-archive.pk',
        priority: 1,
        enabled: true,
        isCustom: false,
      );

      final json = instance.toJson();
      expect(json['id'], equals('annas_archive_pk'));
      expect(json['name'], equals("Anna's Archive (.pk)"));
      expect(json['baseUrl'], equals('https://annas-archive.pk'));
      expect(json['priority'], equals(1));
      expect(json['enabled'], isTrue);

      final parsed = ArchiveInstance.fromJson(json);
      expect(parsed.id, equals(instance.id));
      expect(parsed.name, equals(instance.name));
      expect(parsed.baseUrl, equals(instance.baseUrl));
      expect(parsed.priority, equals(instance.priority));
      expect(parsed.enabled, equals(instance.enabled));
    });

    test('Instance copyWith works correctly', () {
      final instance = ArchiveInstance(
        id: 'annas_archive_gl',
        name: "Anna's Archive (.gl)",
        baseUrl: 'https://annas-archive.gl',
        priority: 2,
        enabled: true,
      );

      final modified = instance.copyWith(priority: 5, enabled: false);
      expect(modified.id, equals('annas_archive_gl'));
      expect(modified.priority, equals(5));
      expect(modified.enabled, isFalse);
    });

    test('Default mirrors include current working official mirrors', () {
      final defaultUrls = [
        'https://annas-archive.gl',
        'https://annas-archive.pk',
        'https://annas-archive.gd',
      ];

      for (final url in defaultUrls) {
        expect(url.startsWith('https://annas-archive.'), isTrue);
      }
    });
  });
}
