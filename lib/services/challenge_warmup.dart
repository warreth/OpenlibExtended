// Warm-up for the DDoS-Guard challenge protecting Anna's Archive mirrors.
//
// Measured behavior (Linux/WebKitGTK): the first challenge per app run takes
// ~2.2 minutes of DDoS-Guard's JS proof-of-work. Every additional webview in
// the same process (new solver windows, the download-link browser) shares the
// default WebKit context, so after one clear everything is fast (~8s).
//
// This warm-up runs that one slow challenge once, right after launch, while
// the user is on the home screen - so the first search/book/download of the
// session hits an already-cleared browser context instead of a 2+ minute
// visible challenge window.
//
// Mobile runs it headless (invisible); desktop shows the small solver window
// once. If the user closes the desktop window early, nothing breaks: the
// next request just solves on demand like before.

// Project imports:
import 'package:openlib/services/instance_manager.dart';
import 'package:openlib/services/logger.dart';
import 'package:openlib/services/webview_challenge_solver.dart';

class ChallengeWarmup {
  ChallengeWarmup._();

  static final AppLogger _logger = AppLogger();

  static bool _warmupDone = false;

  /// Runs the one-time challenge warm-up for the current mirror.
  /// Fire-and-forget; safe to call multiple times.
  static Future<void> warmAfterLaunch() async {
    if (_warmupDone || !WebviewChallengeSolver.isSupported) return;
    _warmupDone = true;

    try {
      final instance = await InstanceManager().getCurrentInstance();
      final homepage = instance.baseUrl;

      _logger.info('Warming DDoS challenge for mirror',
          tag: 'ChallengeWarmup', metadata: {'mirror': homepage});

      final html = await WebviewChallengeSolver.fetchHtmlAfterChallenge(
        homepage,
        timeout: const Duration(minutes: 4),
      );

      if (html != null) {
        _logger.info('Challenge warm-up complete',
            tag: 'ChallengeWarmup',
            metadata: {'mirror': homepage, 'htmlLength': html.length});
      } else {
        // Not fatal: requests fall back to solving on demand.
        _logger.warning('Challenge warm-up returned no HTML',
            tag: 'ChallengeWarmup', metadata: {'mirror': homepage});
      }
    } catch (e, st) {
      _logger.error('Challenge warm-up failed',
          tag: 'ChallengeWarmup', error: e, stackTrace: st);
    }
  }
}
