// The Android notification progress rule: updates must fire on real
// percentage movement (debounced), not per network chunk or exact-MB
// boundaries that chunked streams almost never hit.

// Flutter imports:
import 'package:flutter_test/flutter_test.dart';

// Project imports:
import 'package:openlib/services/download_notification.dart';

void main() {
  group('shouldNotifyProgress', () {
    test('small movements within the step do not re-post', () {
      expect(shouldNotifyProgress(10, 11), isFalse);
      expect(shouldNotifyProgress(10, 11), isFalse); // repeated
      expect(shouldNotifyProgress(0, 1), isFalse);
    });

    test('a full step re-posts', () {
      expect(shouldNotifyProgress(10, 12), isTrue);
      expect(shouldNotifyProgress(0, 2), isTrue);
    });

    test('big jumps re-post once', () {
      expect(shouldNotifyProgress(4, 98), isTrue);
      // The next chunk after re-posting starts a new window.
      expect(shouldNotifyProgress(98, 99), isFalse);
    });

    test('step is at least two whole percent', () {
      expect(notificationProgressStepPercent, greaterThanOrEqualTo(2));
      expect(notificationProgressStepPercent, lessThanOrEqualTo(5));
    });
  });
}
