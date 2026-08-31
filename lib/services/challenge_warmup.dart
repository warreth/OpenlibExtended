// Warm-up for the DDoS-Guard challenge protecting Anna's Archive mirrors.
//
// Measured behavior (Linux/WebKitGTK): the first challenge of an app run can
// take ~2 minutes. Analysis of the challenge bundle showed why: the JS
// fingerprint (canvas/webgl/audio/fonts) completes in well under a second on
// WebKitGTK, and the optional canvas proof-of-work ("picasso") is disabled
// (HTTP 204) for this client - so the wall time is NOT local computation.
// It is DDoS-Guard's trust score repeatedly re-issuing the challenge page
// (~2-5 s per cycle including its forced reload delay) until it accepts the
// WebView's session. Real Firefox/Chrome pass in one or two cycles (~15 s)
// because their TLS/HTTP fingerprint scores higher.
//
// All webviews in the process share the default WebKit context, so once one
// window clears the challenge, every later solve is near-instant (measured
// 5-9 s even after the clearance cookie expires). This warm-up pays the
// one-time cost right after launch, while the user is on the home screen.
//
// Mobile runs it headless (invisible); desktop shows the small solver window
// once. If the desktop window is closed early, nothing breaks: the next
// request falls back to solving on demand.

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
