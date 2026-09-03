// Dart imports:
import 'dart:async';

// Flutter imports:
import 'package:flutter/foundation.dart';

// Package imports:
import 'package:flutter_tts/flutter_tts.dart';

// Project imports:
import 'package:openlib/services/platform_utils.dart';

/// The events a listener can get from the reader while it narrates.
enum TtsState { idle, playing, paused }

/// Wraps flutter_tts so the reader can talk to a plain Dart object with
/// real state transitions, instead of the platform channel directly.
///
/// The underlying [FlutterTts] instance is injectable so tests can drive
/// the same state machine the reader uses against a fake channel.
class TtsService {
  TtsService._(FlutterTts? tts, bool enabled)
      : _tts = enabled ? tts : null,
        _enabled = enabled {
    final engine = _tts;
    if (engine == null) return;

    // Make speak() resolve only when the utterance finishes, so chunk
    // advancement works even on engines that never call the completion
    // handler (flutter_tts #523).
    engine.awaitSpeakCompletion(true);
    engine.setStartHandler(() => _setState(TtsState.playing));
    engine.setCompletionHandler(_onSpeechDone);
    engine.setCancelHandler(_onSpeechDone);
    engine.setPauseHandler(() => _setState(TtsState.paused));
    engine.setContinueHandler(() => _setState(TtsState.playing));
    engine.setErrorHandler((_) => _onSpeechDone());
  }

  /// Production constructor: real engine on mobile, disabled stub on
  /// desktop so the reader can share one code path.
  factory TtsService() => ttsAvailableOnPlatform()
      ? TtsService._(FlutterTts(), true)
      : TtsService._(null, false);

  /// Test constructor: drives the state machine with an injected engine.
  @visibleForTesting
  TtsService.forTest(FlutterTts tts) : this._(tts, true);

  /// Desktop stub for tests: every action is a no-op, like on desktops
  /// where the reader shows no read-aloud controls at all.
  @visibleForTesting
  TtsService.forDesktopStub() : this._(null, false);

  final FlutterTts? _tts;
  final bool _enabled;

  FlutterTts? get engine => _tts;

  /// Rate between 0.0 and 1.0 as flutter_tts expects it (0.5 is normal).
  static const defaultRate = 0.5;
  static const minRate = 0.1;
  static const maxRate = 1.0;

  double _rate = defaultRate;
  double get rate => _rate;

  TtsState _state = TtsState.idle;
  TtsState get state => _state;
  final _stateController = StreamController<TtsState>.broadcast();

  /// Emits every state change so the reader toolbar can rebuild.
  Stream<TtsState> get onStateChanged => _stateController.stream;

  /// Fired when the engine finishes (or is stopped). The reader uses it
  /// to advance to the next chunk of text.
  final _chunkDoneController = StreamController<void>.broadcast();
  Stream<void> get onChunkDone => _chunkDoneController.stream;

  /// Text currently being spoken, used to resume after a pause on
  /// platforms whose pause() is unreliable (older Android engines).
  String _currentText = '';
  bool _pausedMidChunk = false;

  bool _speechSupported = true;
  bool get isSpeechSupported => _speechSupported;

  // A token per utterance: speak() and the completion handler can both
  // report the same utterance done (awaitSpeakCompletion + handler);
  // only the first report may fire chunkDone.
  int _utteranceEpoch = 0;
  int _doneEpoch = -1;

  // True while pause() emulates itself with stop(): that stop's speech
  // end must NOT advance the reader, we stay paused instead.
  bool _pauseEmulated = false;

  Future<void> _setState(TtsState next) async {
    if (_state == next) return;
    _state = next;
    _stateController.add(next);
  }

  void _onSpeechDone({bool fromHandler = false}) {
    final epoch = _utteranceEpoch;
    if (_pauseEmulated) {
      // The engine was stopped only to emulate pause: keep the text and
      // the paused state, and never advance to the next chunk.
      _pauseEmulated = false;
      return;
    }
    if (_doneEpoch == epoch) return; // already reported for this utterance
    _doneEpoch = epoch;
    _currentText = '';
    _pausedMidChunk = false;
    _state = TtsState.idle;
    _stateController.add(TtsState.idle);
    _chunkDoneController.add(null);
  }

  /// Speaks [text]. Returns false when the platform has no engine.
  Future<bool> speak(String text) async {
    final engine = _tts;
    if (!_enabled || engine == null || text.trim().isEmpty) return false;
    _currentText = text;
    _pausedMidChunk = false;
    _pauseEmulated = false;
    final epoch = ++_utteranceEpoch;
    // Reflect the action at once: with awaitSpeakCompletion the engine
    // future only resolves when speech ends, and the toolbar must not
    // sit in idle for the whole utterance.
    await _setState(TtsState.playing);
    final ok = await engine.speak(text);
    if (ok is bool && !ok) {
      _speechSupported = false;
      await _setState(TtsState.idle);
      return false;
    }
    _speechSupported = true;
    // The future resolves when speech ends (awaitSpeakCompletion) or at
    // once on engines that ignore it; the epoch guard dedupes with the
    // completion handler, so either path advancing is enough.
    if (_utteranceEpoch == epoch && !_pauseEmulated) {
      _onSpeechDone();
    }
    return true;
  }

  /// Pauses the current utterance.
  Future<void> pause() async {
    final engine = _tts;
    if (!_enabled || engine == null) return;
    final ok = await engine.pause();
    if (ok is bool && !ok) {
      // Engine cannot pause: emulate by stopping and remembering the
      // spot. Mark it so the stop's speech-end report is swallowed
      // instead of advancing the reader.
      _pausedMidChunk = true;
      _pauseEmulated = true;
      await engine.stop();
      await _setState(TtsState.paused);
      return;
    }
    await _setState(TtsState.paused);
  }

  /// Resumes a paused utterance (re-speaks the same text on engines with
  /// no real pause).
  Future<void> resume() async {
    if (!_enabled || _tts == null) return;
    if (_pausedMidChunk) {
      await speak(_currentText);
      return;
    }
    // Engines with a real pause() resume on their own through the
    // continue handler; nothing else to do but reflect it.
    await _setState(TtsState.playing);
  }

  Future<void> stop() async {
    final engine = _tts;
    if (!_enabled || engine == null) return;
    _currentText = '';
    _pausedMidChunk = false;
    await engine.stop();
    await _setState(TtsState.idle);
  }

  /// Sets the speech rate, clamped to what engines accept.
  Future<void> setRate(double value) async {
    final engine = _tts;
    _rate = value.clamp(minRate, maxRate);
    if (!_enabled || engine == null) return;
    await engine.setSpeechRate(_rate);
  }

  /// Sets the language; returns false when unavailable on the device.
  Future<bool> setLanguage(String language) async {
    final engine = _tts;
    if (!_enabled || engine == null) return false;
    final available = await engine.isLanguageAvailable(language);
    if (available is bool && !available) return false;
    await engine.setLanguage(language);
    return true;
  }

  /// Checks the language with a fallback to its 2-letter code ('en' for
  /// 'en-US'), since engines often only register the short form. Returns
  /// false only when the device has no usable engine at all.
  Future<bool> ensureEngineReady(String language) async {
    final engine = _tts;
    if (!_enabled || engine == null) return false;
    if (await setLanguage(language)) return true;
    final short = language.length > 2 ? language.substring(0, 2) : language;
    if (short != language && await setLanguage(short)) return true;
    return false;
  }

  /// The reader moves a page/chapter forward when a chunk finishes.
  void onChunkComplete(VoidCallback advance) {
    _chunkDoneController.stream.listen((_) => advance());
  }

  void dispose() {
    if (_enabled) {
      _tts?.stop();
    }
    _stateController.close();
    _chunkDoneController.close();
  }
}

/// Splits chapter HTML into speakable sentences. Strips tags the same way
/// the visible-text helper in annas_archieve.dart does, then groups the
/// text into chunks short enough that "stop" never loses more than a
/// sentence or two.
List<String> splitIntoSpeechChunks(String htmlText, {int maxChunkChars = 600}) {
  // Plain text input (already stripped) goes through the same pipeline.
  final text = htmlText.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (text.isEmpty) return const [];

  final sentences = text
      .split(RegExp(r'(?<=[.!?;:])\s+(?=[^a-z])'))
      .where((s) => s.trim().isNotEmpty);
  final chunks = <String>[];
  final buffer = StringBuffer();

  void flush() {
    final chunk = buffer.toString().trim();
    if (chunk.isNotEmpty) chunks.add(chunk);
    buffer.clear();
  }

  for (final sentence in sentences) {
    if (buffer.isNotEmpty && buffer.length + sentence.length > maxChunkChars) {
      flush();
    }
    if (sentence.length > maxChunkChars) {
      // A run-on longer than the cap has no sentence end to break at;
      // hard-split it at word boundaries so no chunk overflows the engine.
      int start = 0;
      while (start < sentence.length) {
        int end = start + maxChunkChars;
        if (end >= sentence.length) {
          end = sentence.length;
        } else {
          final lastSpace = sentence.lastIndexOf(' ', end);
          if (lastSpace > start) end = lastSpace;
        }
        chunks.add(sentence.substring(start, end).trim());
        start = end;
      }
      continue;
    }
    buffer.write('$sentence ');
  }
  flush();
  return chunks;
}

/// Strips HTML to visible text for TTS: no scripts, no styles, no tags.
String htmlToSpeechText(String html) {
  // A cheap but correct-enough pass for chapter XHTML: drop script/style
  // blocks wholesale, then remove remaining tags.
  var text = html
      .replaceAll(RegExp(r'<script\b[^>]*>.*?</script>', dotAll: true), ' ')
      .replaceAll(RegExp(r'<style\b[^>]*>.*?</style>', dotAll: true), ' ');
  // Block-level tags read better with a space between them.
  text = text.replaceAll(
      RegExp(r'</(p|div|h[1-6]|li|blockquote|tr)>', caseSensitive: false),
      r' ');
  text = text.replaceAll(RegExp(r'<[^>]+>'), '');
  return text.replaceAll(RegExp(r'\s+'), ' ').trim();
}

/// TTS is a mobile-only feature: the reader on desktop shows no toolbar.
bool ttsAvailableOnPlatform() => PlatformUtils.isMobile;
