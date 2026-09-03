// Real tests for the read-aloud pipeline: HTML stripping, sentence
// chunking, and the TtsService state machine. The engine boundary is the
// flutter_tts method channel, faked there; everything on the Dart side
// (state transitions, resume emulation, chunk advance) is the real code.

// Flutter imports:
import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

// Package imports:
import 'package:flutter_tts/flutter_tts.dart';

// Project imports:
import 'package:openlib/services/tts_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final calls = <String>[];
  bool pauseSupported = true;
  bool langAvailable = true;

  // Utterances in flight: the fake engine does not finish speaking on
  // its own, tests complete the future when they want the utterance to
  // end - that is what a real engine with awaitSpeakCompletion does.
  final speakFutures = <Completer<bool>>[];

  void fakeChannel() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('flutter_tts'),
            (call) async {
      calls.add(call.method);
      switch (call.method) {
        case 'awaitSpeakCompletion':
          return true;
        case 'speak':
          final completer = Completer<bool>();
          speakFutures.add(completer);
          return completer.future;
        case 'pause':
          return pauseSupported;
        case 'stop':
          return true;
        case 'isLanguageAvailable':
          return langAvailable;
        case 'setLanguage':
          return true;
        case 'getLanguages':
          return <Object>['en-US', 'de-DE'];
        default:
          return null;
      }
    });
  }

  TtsService makeService() => TtsService.forTest(FlutterTts());

  /// Ends every utterance still held open by the fake engine, so no
  /// test leaves a speak() future dangling across teardown.
  Future<void> endUtterances() async {
    for (final c in speakFutures) {
      if (!c.isCompleted) c.complete(true);
    }
    await Future<void>.delayed(Duration.zero);
  }

  setUp(() {
    calls.clear();
    speakFutures.clear();
    pauseSupported = true;
    langAvailable = true;
    fakeChannel();
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('flutter_tts'), null);
  });

  group('htmlToSpeechText', () {
    test('strips tags, scripts and styles to readable text', () {
      const html = '''
        <html><head><style>.a{color:red}</style>
        <script>var x = 1;</script></head>
        <body><h1>Title</h1><p>First paragraph.</p>
        <p>Second, with a <b>bold</b> bit.</p></body></html>
      ''';
      final text = htmlToSpeechText(html);
      expect(text, contains('Title'));
      expect(text, contains('First paragraph.'));
      expect(text, contains('Second, with a bold bit.'));
      expect(text, isNot(contains('color:red')));
      expect(text, isNot(contains('var x')));
      expect(text, isNot(contains('<')));
    });

    test('collapses whitespace runs into single spaces', () {
      expect(htmlToSpeechText('<p>a\n\n  b</p><p>c</p>'), 'a b c');
    });
  });

  group('splitIntoSpeechChunks', () {
    test('returns empty for blank input', () {
      expect(splitIntoSpeechChunks(''), isEmpty);
      expect(splitIntoSpeechChunks('   '), isEmpty);
    });

    test('keeps a short sentence as one chunk', () {
      expect(
          splitIntoSpeechChunks('One sentence only.'), ['One sentence only.']);
    });

    test('breaks long text only at sentence ends', () {
      const sentence = 'This is one full sentence with an ending. ';
      final long = sentence * 40; // ~1440 chars, default cap 600
      final chunks = splitIntoSpeechChunks(long);
      expect(chunks.length, greaterThan(1));
      for (final chunk in chunks) {
        expect(chunk.endsWith('.'), isTrue,
            reason: 'chunks must break at sentence ends');
      }
      // No text lost or duplicated across chunks.
      final rejoined = chunks.join(' ').replaceAll(' ', '');
      expect(rejoined, long.replaceAll(' ', ''));
    });

    test('caps chunk length even without sentence boundaries', () {
      final long = 'Word ' * 300;
      final chunks = splitIntoSpeechChunks(long, maxChunkChars: 600);
      expect(chunks.first.length, lessThanOrEqualTo(600));
    });
  });

  group('TtsService state machine', () {
    test('speak resolves as done when the engine ignores completion await',
        () async {
      // The fake channel answers speak() immediately: with
      // awaitSpeakCompletion the utterance is over once it resolves,
      // exactly like an engine that ignores the completion await.
      final service = makeService();
      var chunkDone = false;
      service.onChunkDone.listen((_) => chunkDone = true);

      final speaking = service.speak('Hello world');
      await Future<void>.delayed(Duration.zero);
      expect(service.state, TtsState.playing);
      // The engine future resolving IS the utterance ending.
      await endUtterances();
      final ok = await speaking;
      expect(ok, isTrue);
      expect(calls, contains('speak'));
      expect(service.state, TtsState.idle);
      // The utterance really ended: the reader may advance.
      expect(chunkDone, isTrue);
      service.dispose();
    });

    test('engine completion resets state and fires chunk-done', () async {
      final service = makeService();
      var chunkDone = false;
      service.onChunkDone.listen((_) => chunkDone = true);

      final speaking = service.speak('Hello');
      await Future<void>.delayed(Duration.zero);
      // The engine reports the utterance done through its handler.
      service.engine!.completionHandler!();
      await Future<void>.delayed(Duration.zero);

      expect(service.state, TtsState.idle);
      expect(chunkDone, isTrue);
      await endUtterances();
      await speaking;
      service.dispose();
    });

    test('pause on an engine without pause support emulates it', () async {
      pauseSupported = false;
      final service = makeService();
      var chunkDone = 0;
      service.onChunkDone.listen((_) => chunkDone++);

      // Utterance in flight, like on a real device.
      final speaking = service.speak('Hello');
      await Future<void>.delayed(Duration.zero);
      expect(service.state, TtsState.playing);

      await service.pause();
      await Future<void>.delayed(Duration.zero);

      expect(service.state, TtsState.paused);
      expect(calls, contains('stop'));
      // The emulated pause's stop must not advance the reader.
      expect(chunkDone, 0);

      // The in-flight utterance is over while we stay paused.
      speakFutures.first.complete(true);
      await speaking;
      await Future<void>.delayed(Duration.zero);
      expect(chunkDone, 0);
      expect(service.state, TtsState.paused);

      // resume() re-speaks and, like a real engine with the completion
      // await on, only resolves once that utterance ends.
      final resuming = service.resume();
      await Future<void>.delayed(Duration.zero);
      expect(calls.where((c) => c == 'speak').length, 2);
      await endUtterances();
      await resuming;
      expect(service.state, TtsState.idle);
      service.dispose();
    });

    test('pause on an engine with real pause does not stop', () async {
      final service = makeService();
      final speaking = service.speak('Hello');
      await Future<void>.delayed(Duration.zero);
      await service.pause();

      expect(service.state, TtsState.paused);
      expect(calls, isNot(contains('stop')));

      await service.resume();
      expect(service.state, TtsState.playing);
      await endUtterances();
      await speaking;
      service.dispose();
    });

    test('stop clears the utterance and returns to idle', () async {
      final service = makeService();
      final speaking = service.speak('Hello');
      await Future<void>.delayed(Duration.zero);
      await service.stop();

      expect(service.state, TtsState.idle);
      expect(calls, contains('stop'));
      await endUtterances();
      await speaking;
      service.dispose();
    });

    test('setRate clamps out-of-range values', () async {
      final service = makeService();
      await service.setRate(5.0);
      expect(service.rate, TtsService.maxRate);
      await service.setRate(-1);
      expect(service.rate, TtsService.minRate);
      await service.setRate(0.5);
      expect(service.rate, 0.5);
      expect(calls, contains('setSpeechRate'));
      service.dispose();
    });

    test('setLanguage reports unavailable languages', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(const MethodChannel('flutter_tts'),
              (call) async {
        if (call.method == 'isLanguageAvailable') return false;
        return null;
      });
      final service = makeService();
      expect(await service.setLanguage('xx-XX'), isFalse);
      service.dispose();
    });

    test('desktop stub is a silent no-op', () async {
      final service = TtsService.forDesktopStub();
      expect(await service.speak('Hello'), isFalse);
      expect(calls, isEmpty);
      expect(await service.setLanguage('en-US'), isFalse);
      await service.stop();
      service.dispose();
      expect(calls, isEmpty);
    });

    test('blank text is refused', () async {
      final service = makeService();
      // The constructor's completion-await setup is expected traffic;
      // a blank utterance must add nothing on top of it.
      final baseline = calls.length;
      expect(await service.speak('   '), isFalse);
      expect(calls.length, baseline);
      service.dispose();
    });
  });
}
