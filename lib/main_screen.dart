import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:record/record.dart';
import 'package:audioplayers/audioplayers.dart';

import 'ui/animated_nurse_face.dart';

// ─── Holat turlari ──────────────────────────────────────────────────────────
enum SessionPhase {
  notStarted,  // Suhbat boshlanmagan
  intro,       // AI salomlashdi, user javob kutilmoqda
  mainQ,       // AI asosiy savol berdi
  followUp1,   // AI 1-qo'shimcha savol berdi
  followUp2,   // AI 2-qo'shimcha savol berdi
  grading,     // AI baholayapti
}

enum MicState {
  idle,       // Tayyor, bosish mumkin
  recording,  // Yozilmoqda (push-to-talk)
  processing, // Server qayta ishlayapti
  aiSpeaking, // AI gapirmoqda
}

// ─── MainScreen ──────────────────────────────────────────────────────────────
class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  // WebSocket
  WebSocketChannel? _channel;
  bool _wsConnected = false;

  // Audio
  final AudioRecorder _audioRecorder = AudioRecorder();
  final AudioPlayer _audioPlayer = AudioPlayer();
  StreamSubscription<Uint8List>? _recordSub;

  // Holat
  SessionPhase _phase = SessionPhase.notStarted;
  MicState _micState = MicState.idle;
  String _statusText = 'Boshlash uchun tugmani bosing';
  String _aiText = '';        // AI ning so'nggi matni
  String _userText = '';      // User ning so'nggi matni


  @override
  void initState() {
    super.initState();
    _connectWebSocket();
  }

  // ─── WebSocket ulanish ──────────────────────────────────────────────────────
  Future<void> _connectWebSocket() async {
    // Web va Windows desktop → localhost, Android/iOS telefon → Wi-Fi IP
    final String wsUrl;
    if (kIsWeb) {
      wsUrl = 'ws://localhost:8080';
    } else if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
      wsUrl = 'ws://localhost:8080';
    } else {
      // Android / iOS — kompyuterning Wi-Fi IP manzili
      wsUrl = 'ws://10.125.125.234:8080';
    }
    try {
      _channel = WebSocketChannel.connect(Uri.parse(wsUrl));
      _wsConnected = true;

      _channel!.stream.listen(
        (message) async {
          if (message is String) {
            _handleTextMessage(message);
          } else if (message is Uint8List) {
            // AI audio javob keldi
            await _playAudio(message);
          }
        },
        onDone: () {
          if (mounted) {
            setState(() {
              _wsConnected = false;
              _statusText = 'Ulanish uzildi. Qayta urinilmoqda...';
            });
          }
          // 3 soniyadan keyin qayta ulanish
          Future.delayed(const Duration(seconds: 3), _connectWebSocket);
        },
        onError: (e) {
          if (mounted) {
            setState(() {
              _wsConnected = false;
              _statusText = 'Xato: $e';
            });
          }
        },
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _wsConnected = false;
          _statusText = 'Server topilmadi. Qayta urinilmoqda...';
        });
      }
      Future.delayed(const Duration(seconds: 3), _connectWebSocket);
    }
  }

  // ─── Matnli xabarlarni qayta ishlash ────────────────────────────────────────
  void _handleTextMessage(String raw) {
    if (!mounted) return;
    try {
      final data = jsonDecode(raw) as Map<String, dynamic>;
      final type = data['type'] as String;

      setState(() {
        switch (type) {
          case 'status':
            final content = data['content'] as String;
            if (content == 'listening') {
              _micState = MicState.recording;
              _statusText = 'Eshitilmoqda... (tugmani bosib turing)';
            } else if (content == 'processing') {
              _micState = MicState.processing;
              _statusText = 'Qayta ishlanmoqda...';
            } else if (content == 'thinking') {
              _micState = MicState.aiSpeaking;
              _statusText = 'AI o\'ylayapti...';
            }
            break;

          case 'transcript':
            _userText = data['content'] as String? ?? '';
            break;

          case 'llm_chunk':
            final chunk = data['content'] as String? ?? '';
            _aiText += chunk;
            _micState = MicState.aiSpeaking;
            _statusText = 'AI gapirmoqda...';
            break;

          case 'llm_end':
            // Server qaysi bosqichga o'tganini bildiradi
            final stateStr = data['state'] as String? ?? '';
            _phase = _parsePhase(stateStr);
            _micState = MicState.idle;
            _statusText = _getIdleStatusText();
            _aiText = ''; // Keyingi navbat uchun tozalaymiz
            break;
        }
      });
    } catch (e) {
      debugPrint('Xabar parse xatosi: $e');
    }
  }

  SessionPhase _parsePhase(String s) {
    switch (s) {
      case 'intro': return SessionPhase.intro;
      case 'main_q': return SessionPhase.mainQ;
      case 'follow_up_1': return SessionPhase.followUp1;
      case 'follow_up_2': return SessionPhase.followUp2;
      case 'grading': return SessionPhase.grading;
      default: return _phase;
    }
  }

  String _getIdleStatusText() {
    if (_phase == SessionPhase.grading) {
      return 'Baholash tugadi. Yangi savol uchun gapiring';
    }
    return 'Mikrofon tugmasini bosib turing va gapiring';
  }

  // ─── Audio ──────────────────────────────────────────────────────────────────
  Future<void> _playAudio(Uint8List bytes) async {
    try {
      await _audioPlayer.play(BytesSource(bytes));
    } catch (e) {
      debugPrint('Audio ijro xatosi: $e');
    }
  }

  // ─── Suhbatni boshlash (Birinchi tugma bosish) ────────────────────────────
  Future<void> _startSession() async {
    if (!_wsConnected || _phase != SessionPhase.notStarted) return;

    setState(() {
      _statusText = 'Suhbat boshlanmoqda...';
      _micState = MicState.processing;
      _phase = SessionPhase.intro; // Boshlandi deb belgilaymiz
    });

    _channel?.sink.add(jsonEncode({'type': 'start_session'}));
  }

  // ─── Push-to-talk: Tugma bosildi ────────────────────────────────────────────
  Future<void> _onMicPressDown() async {
    // Faqat suhbat boshlangandan keyin va AI gapirmayotgan paytda
    if (_phase == SessionPhase.notStarted) return;
    if (_micState == MicState.aiSpeaking || _micState == MicState.recording) return;

    // Mikrofon ruxsatini tekshirish
    if (!kIsWeb) {
      final status = await Permission.microphone.status;
      if (!status.isGranted) {
        final result = await Permission.microphone.request();
        if (!result.isGranted) {
          setState(() => _statusText = 'Mikrofon ruxsati berilmadi!');
          return;
        }
      }
    }

    // AI gapirsa, to'xtatamiz
    await _audioPlayer.stop();

    // Serverga "tinglashni boshlash" signalini yuboramiz
    _channel?.sink.add(jsonEncode({'type': 'start_listening'}));

    setState(() {
      _userText = '';
      _micState = MicState.recording;
      _statusText = 'Eshitilmoqda... (tugmani bosib turing)';
    });

    // Mikrofon yozishni boshlash
    try {
      final stream = await _audioRecorder.startStream(const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: 16000,
        numChannels: 1,
      ));

      _recordSub = stream.listen((data) {
        if (_wsConnected && _channel != null) {
          _channel!.sink.add(data);
        }
      });
    } catch (e) {
      debugPrint('Mikrofon xatosi: $e');
      setState(() {
        _statusText = 'Mikrofon xatosi: $e';
        _micState = MicState.idle;
      });
    }
  }

  // ─── Push-to-talk: Tugma qo'yib yuborildi ──────────────────────────────────
  Future<void> _onMicPressUp() async {
    if (_micState != MicState.recording) return;

    // Yozishni to'xtatish
    await _recordSub?.cancel();
    _recordSub = null;
    try {
      await _audioRecorder.stop();
    } catch (e) {
      debugPrint('Yozishni to\'xtatish xatosi: $e');
    }

    // Serverga signal
    _channel?.sink.add(jsonEncode({'type': 'stop_listening'}));

    setState(() {
      _micState = MicState.processing;
      _statusText = 'Qayta ishlanmoqda...';
    });
  }

  // ─── Suhbatni tugatish ────────────────────────────────────────────────────
  Future<void> _endSession() async {
    // AI ni to'xtatamiz
    await _audioPlayer.stop();
    // Yozishni to'xtatamiz
    if (_micState == MicState.recording) {
      await _onMicPressUp();
    }

    setState(() {
      _phase = SessionPhase.notStarted;
      _micState = MicState.idle;
      _statusText = 'Boshlash uchun tugmani bosing';
      _aiText = '';
      _userText = '';
    });
  }

  @override
  void dispose() {
    _recordSub?.cancel();
    _audioRecorder.dispose();
    _audioPlayer.dispose();
    _channel?.sink.close();
    super.dispose();
  }

  // ─── UI ──────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final bool isRecording = _micState == MicState.recording;
    final bool isAiSpeaking = _micState == MicState.aiSpeaking;
    final bool sessionStarted = _phase != SessionPhase.notStarted;

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFFFFF0F8),
              Color(0xFFFCE4F0),
              Color(0xFFFFF0F8),
            ],
            stops: [0.0, 0.5, 1.0],
          ),
        ),
        child: Stack(
          children: [
            _blob(top: -80, left: -80, size: 280, color: const Color(0xFFFFB3CE), opacity: 0.18),
            _blob(bottom: -60, right: -80, size: 320, color: const Color(0xFFFF8FB1), opacity: 0.12),
            _blob(top: 200, right: -60, size: 180, color: const Color(0xFFFFD6E7), opacity: 0.15),
            SafeArea(
              child: Column(
                children: [
                  _buildHeader(sessionStarted: sessionStarted),
                  Expanded(
                    child: Center(
                      child: AnimatedNurseFace(
                        isSpeaking: isAiSpeaking,
                        isListening: isRecording,
                      ),
                    ),
                  ),
                  // AI matni
                  if (_aiText.isNotEmpty && isAiSpeaking)
                    _buildTextBubble(_aiText, isAi: true),
                  // User matni
                  if (_userText.isNotEmpty)
                    _buildTextBubble(_userText, isAi: false),
                  _buildStatusLabel(),
                  _buildBottomBar(
                    sessionStarted: sessionStarted,
                    isRecording: isRecording,
                    isAiSpeaking: isAiSpeaking,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _blob({double? top, double? bottom, double? left, double? right, required double size, required Color color, required double opacity}) {
    return Positioned(
      top: top, bottom: bottom, left: left, right: right,
      child: Container(
        width: size, height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color.withValues(alpha: opacity),
        ),
      ),
    );
  }

  Widget _buildHeader({required bool sessionStarted}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Ulanish holati
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: _wsConnected
                  ? const Color(0xFF4CAF50).withValues(alpha: 0.15)
                  : const Color(0xFFFF5252).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8, height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _wsConnected ? const Color(0xFF4CAF50) : const Color(0xFFFF5252),
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  _wsConnected ? 'Ulangan' : 'Ulanmagan',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: _wsConnected ? const Color(0xFF388E3C) : const Color(0xFFD32F2F),
                  ),
                ),
              ],
            ),
          ),
          // Sarlavha
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.8),
                  shape: BoxShape.circle,
                  boxShadow: [BoxShadow(color: const Color(0xFFFF8FB1).withValues(alpha: 0.3), blurRadius: 12, offset: const Offset(0, 4))],
                ),
                child: const Icon(Icons.health_and_safety, color: Color(0xFFE8527A), size: 22),
              ),
              const SizedBox(width: 8),
              const Text(
                'AI Hamshira',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF7A1F40),
                  letterSpacing: 0.8,
                ),
              ),
            ],
          ),
          // X tugmasi - faqat suhbat boshlanganda
          if (sessionStarted)
            GestureDetector(
              onTap: _endSession,
              child: Container(
                width: 38, height: 38,
                decoration: BoxDecoration(
                  color: const Color(0xFFE8527A).withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.close_rounded, color: Color(0xFFE8527A), size: 22),
              ),
            )
          else
            const SizedBox(width: 38),
        ],
      ),
    );
  }

  Widget _buildTextBubble(String text, {required bool isAi}) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      child: Container(
        key: ValueKey(text),
        margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isAi
              ? const Color(0xFFE8527A).withValues(alpha: 0.1)
              : Colors.white.withValues(alpha: 0.7),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(20),
            topRight: const Radius.circular(20),
            bottomLeft: Radius.circular(isAi ? 4 : 20),
            bottomRight: Radius.circular(isAi ? 20 : 4),
          ),
          boxShadow: [BoxShadow(color: const Color(0xFFFF8FB1).withValues(alpha: 0.12), blurRadius: 8, offset: const Offset(0, 2))],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              isAi ? Icons.health_and_safety_rounded : Icons.person_rounded,
              size: 16,
              color: isAi ? const Color(0xFFE8527A) : const Color(0xFF7A1F40),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                text,
                style: TextStyle(
                  fontSize: 14,
                  color: const Color(0xFF7A1F40).withValues(alpha: 0.9),
                  height: 1.4,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusLabel() {
    final IconData icon;
    final Color color;

    switch (_micState) {
      case MicState.recording:
        icon = Icons.mic;
        color = const Color(0xFFE53935);
        break;
      case MicState.processing:
        icon = Icons.psychology_rounded;
        color = const Color(0xFFE8527A);
        break;
      case MicState.aiSpeaking:
        icon = Icons.volume_up_rounded;
        color = const Color(0xFF7B1FA2);
        break;
      case MicState.idle:
        icon = _phase == SessionPhase.notStarted
            ? Icons.touch_app_rounded
            : Icons.mic_none_rounded;
        color = const Color(0xFFE8527A);
        break;
    }

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      child: Container(
        key: ValueKey(_statusText),
        margin: const EdgeInsets.only(bottom: 10, top: 4),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.72),
          borderRadius: BorderRadius.circular(24),
          boxShadow: [BoxShadow(color: const Color(0xFFFF8FB1).withValues(alpha: 0.18), blurRadius: 10, offset: const Offset(0, 3))],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_micState == MicState.processing)
              const SizedBox(
                width: 16, height: 16,
                child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFE8527A)),
              )
            else
              Icon(icon, size: 16, color: color),
            const SizedBox(width: 8),
            Text(
              _statusText,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Color(0xFF7A1F40),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomBar({
    required bool sessionStarted,
    required bool isRecording,
    required bool isAiSpeaking,
  }) {
    // Suhbat boshlanmagan - faqat "Boshlash" tugmasi
    if (!sessionStarted) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 48, top: 8),
        child: GestureDetector(
          onTap: _wsConnected ? _startSession : null,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 18),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: _wsConnected
                    ? [const Color(0xFFFF9DBE), const Color(0xFFE8527A)]
                    : [Colors.grey.shade300, Colors.grey.shade400],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(36),
              boxShadow: [
                if (_wsConnected)
                  BoxShadow(
                    color: const Color(0xFFE8527A).withValues(alpha: 0.38),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: const [
                Icon(Icons.play_arrow_rounded, color: Colors.white, size: 28),
                SizedBox(width: 10),
                Text(
                  'Suhbatni boshlash',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // Suhbat boshlangan - push-to-talk tugmasi
    final bool canRecord = !isAiSpeaking && _micState != MicState.processing;

    return Padding(
      padding: const EdgeInsets.only(bottom: 48, top: 8),
      child: GestureDetector(
        onTapDown: canRecord ? (_) => _onMicPressDown() : null,
        onTapUp: (_) => _onMicPressUp(),
        onTapCancel: () => _onMicPressUp(),
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Tashqi halqa animatsiyasi (yozib turish paytida)
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              width: isRecording ? 124 : 100,
              height: isRecording ? 124 : 100,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: (isRecording
                    ? const Color(0xFFFF4B4B)
                    : const Color(0xFFFF8FB1))
                    .withValues(alpha: isRecording ? 0.22 : 0.15),
              ),
            ),
            // Ichki tugma
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: isRecording ? 88 : 76,
              height: isRecording ? 88 : 76,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: isRecording
                      ? [const Color(0xFFFF6B6B), const Color(0xFFE53935)]
                      : isAiSpeaking
                          ? [const Color(0xFFCE93D8), const Color(0xFF7B1FA2)]
                          : canRecord
                              ? [const Color(0xFFFF9DBE), const Color(0xFFE8527A)]
                              : [Colors.grey.shade300, Colors.grey.shade500],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                boxShadow: [
                  BoxShadow(
                    color: (isRecording
                        ? const Color(0xFFFF4B4B)
                        : const Color(0xFFE8527A))
                        .withValues(alpha: 0.42),
                    blurRadius: isRecording ? 32 : 20,
                    spreadRadius: isRecording ? 6 : 2,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: _micState == MicState.processing
                  ? const Padding(
                      padding: EdgeInsets.all(20),
                      child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                    )
                  : Icon(
                      isRecording
                          ? Icons.mic
                          : isAiSpeaking
                              ? Icons.volume_up_rounded
                              : Icons.mic_none_rounded,
                      color: Colors.white,
                      size: 34,
                    ),
            ),
            // "Bosib turing" matni
            if (!isRecording && !isAiSpeaking && canRecord)
              Positioned(
                bottom: 0,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8527A).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text(
                    'Bosib turing',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFFE8527A),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
