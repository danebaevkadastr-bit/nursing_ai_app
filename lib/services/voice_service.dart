import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

class VoiceService {
  final FlutterTts _tts = FlutterTts();
  final stt.SpeechToText _speech = stt.SpeechToText();

  bool _speechReady = false;

  VoiceService() {
    _initTts();
  }

  Future<void> _initTts() async {
    await _tts.setLanguage('uz-UZ');
    await _tts.setSpeechRate(0.48);
    await _tts.setVolume(1.0);
    await _tts.setPitch(1.05);
  }

  void Function(String)? onStatusChange;

  Future<bool> initSpeech() async {
    if (_speechReady) return true;
    _speechReady = await _speech.initialize(
      onError: (e) => debugPrint('STT Error: $e'),
      onStatus: (s) {
        debugPrint('STT Status: $s');
        onStatusChange?.call(s);
      },
    );
    return _speechReady;
  }

  bool get isSpeechReady => _speechReady;

  Future<void> speak(String text, {VoidCallback? onComplete}) async {
    if (text.isEmpty) return;
    await _tts.stop();

    _tts.setCompletionHandler(() {
      onComplete?.call();
    });

    await _tts.speak(text);
  }

  Future<void> stopSpeaking() async {
    await _tts.stop();
  }

  Future<void> startListening({
    required void Function(String words) onResult,
    VoidCallback? onListeningDone,
  }) async {
    if (!_speechReady) return;

    await _speech.listen(
      onResult: (result) {
        if (result.finalResult) {
          onResult(result.recognizedWords);
          onListeningDone?.call();
        }
      },
      listenOptions: stt.SpeechListenOptions(
        localeId: kIsWeb ? 'uz' : 'uz_UZ',
        cancelOnError: true,
        partialResults: false,
        listenFor: const Duration(seconds: 30),
        pauseFor: const Duration(seconds: 3),
      ),
    );
  }

  Future<void> stopListening() async {
    await _speech.stop();
  }

  bool get isListening => _speech.isListening;
}
