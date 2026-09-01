// Real tests for the read-aloud pipeline: HTML stripping, sentence
// chunking, and the TtsService state machine. The engine boundary is the
// flutter_tts method channel, faked there; everything on the Dart side
// (state transitions, resume emulation, chunk advance) is the real code.

// Flutter imports:
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

  void fakeChannel() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('flutter_tts'),
            (call) async {
      calls.add(call.method);
      switch (call.method) {
        case 'speak':
          return true;
        case 'pause':
          return pauseSupported;
        case 'stop':
          return true;
        case 'isLanguageAvailable':
          return true;
        default:
          return null;
      }
    });
  }

  TtsService makeService() => TtsService.forTest(FlutterTts());

  setUp(() {
    calls.clear();
    pauseSupported = true;
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
    test('speak goes to playing and sends text to the engine', () async {
      final service = makeService();
      final states = <TtsState>[];
      service.onStateChanged.listen(states.add);

      final ok = await service.speak('Hello world');
      expect(ok, isTrue);
      expect(service.state, TtsState.playing);
      expect(calls, contains('speak'));
      expect(states.first, TtsState.playing);
      service.dispose();
    });

    test('engine completion resets state and fires chunk-done', () async {
      final service = makeService();
      var chunkDone = false;
      service.onChunkDone.listen((_) => chunkDone = true);

      await service.speak('Hello');
      service.engine!.completionHandler!();
      await Future<void>.delayed(Duration.zero);

      expect(service.state, TtsState.idle);
      expect(chunkDone, isTrue);
      service.dispose();
    });

    test('pause on an engine without pause support emulates it', () async {
      pauseSupported = false;
      final service = makeService();

      await service.speak('Hello');
      await service.pause();

      expect(service.state, TtsState.paused);
      expect(calls, contains('stop'));

      await service.resume();
      expect(service.state, TtsState.playing);
      // Resume re-speaks the same text through the engine.
      expect(calls.where((c) => c == 'speak').length, 2);
      service.dispose();
    });

    test('pause on an engine with real pause does not stop', () async {
      final service = makeService();
      await service.speak('Hello');
      await service.pause();

      expect(service.state, TtsState.paused);
      expect(calls, isNot(contains('stop')));

      await service.resume();
      expect(service.state, TtsState.playing);
      service.dispose();
    });

    test('stop clears the utterance and returns to idle', () async {
      final service = makeService();
      await service.speak('Hello');
      await service.stop();

      expect(service.state, TtsState.idle);
      expect(calls, contains('stop'));
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
      expect(await service.speak('   '), isFalse);
      expect(calls, isEmpty);
      service.dispose();
    });
  });
}
