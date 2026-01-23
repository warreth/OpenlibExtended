// Flutter imports:
import 'package:flutter_test/flutter_test.dart';

// Project imports:
import 'package:openlib/ui/epub_viewer.dart';

// This test ensures that the epub_viewer.dart file compiles correctly
// and that the EpubController methods are used correctly.
void main() {
  group('EpubViewer Compilation Tests', () {
    test('epub_viewer.dart imports successfully', () {
      // This test will fail at compile time if there are syntax errors
      // or undefined method calls in epub_viewer.dart
      // The import of epub_viewer.dart above ensures the file compiles
      expect(EpubViewerWidget, isNotNull);
      expect(EpubViewer, isNotNull);
    });
  });

  group('EpubViewer Widgets', () {
    test('EpubViewerWidget can be instantiated', () {
      // Verify the widget can be created
      const widget = EpubViewerWidget(fileName: 'test.epub');
      expect(widget.fileName, equals('test.epub'));
    });

    test('EpubViewer can be instantiated', () {
      // Verify the viewer widget can be created
      const widget = EpubViewer(
        filePath: '/path/to/test.epub',
        fileName: 'test.epub',
      );
      expect(widget.filePath, equals('/path/to/test.epub'));
      expect(widget.fileName, equals('test.epub'));
    });
  });
}
