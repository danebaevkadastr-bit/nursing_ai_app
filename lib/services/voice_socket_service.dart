import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:record/record.dart';
import 'package:audioplayers/audioplayers.dart';

class VoiceSocketService {
  WebSocketChannel? _channel;
  final AudioRecorder _audioRecorder = AudioRecorder();
  final AudioPlayer _audioPlayer = AudioPlayer();
  
  StreamSubscription<Uint8List>? _recordSub;
  bool isConnected = false;

  Function(String)? onStatusChange;
  Function(String)? onTranscript;
  Function(String)? onBotReplyChunk;

  Future<void> connect(String url) async {
    try {
      _channel = WebSocketChannel.connect(Uri.parse(url));
      isConnected = true;
      onStatusChange?.call('Tayyor');
      
      _channel!.stream.listen(
        (message) async {
          if (message is String) {
            final data = jsonDecode(message);
            if (data['type'] == 'transcript') {
              onTranscript?.call(data['content']);
            } else if (data['type'] == 'llm_chunk') {
              onBotReplyChunk?.call(data['content']);
            } else if (data['type'] == 'llm_end') {
              onStatusChange?.call('Tayyor');
            }
          } else if (message is Uint8List) {
            // Serverdan TTS audio baytlari keldi
            await _playAudioChunk(message);
          }
        },
        onDone: () {
          isConnected = false;
          onStatusChange?.call('Uzildi');
        },
        onError: (e) {
          isConnected = false;
          onStatusChange?.call('Xato');
        },
      );
    } catch (e) {
      isConnected = false;
      onStatusChange?.call('Xato: $e');
    }
  }

  Future<void> _playAudioChunk(Uint8List bytes) async {
    // Audioplayers yordamida baytlarni ijro etish
    await _audioPlayer.play(BytesSource(bytes));
  }

  Future<void> startListening() async {
    if (!isConnected) return;
    try {
      // Deepgram uchun 16kHz PCM16 eng qulay format
      final stream = await _audioRecorder.startStream(const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: 16000,
        numChannels: 1,
      ));
      
      onStatusChange?.call('Eshitilmoqda...');
      
      _recordSub = stream.listen((data) {
        if (isConnected && _channel != null) {
          _channel!.sink.add(data);
        }
      });
    } catch (e) {
      print("Mikrofonda xato: $e");
    }
  }

  Future<void> stopListening() async {
    await _recordSub?.cancel();
    await _audioRecorder.stop();
    onStatusChange?.call('Javob kutilmoqda...');
  }

  Future<void> stopSpeaking() async {
    await _audioPlayer.stop();
  }

  Future<void> dispose() async {
    await stopListening();
    _channel?.sink.close();
    await _audioPlayer.dispose();
  }
}
