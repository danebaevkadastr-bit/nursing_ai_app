import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/session_provider.dart';
import '../widgets/microphone_button.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessionState = ref.watch(sessionProvider);
    final sessionNotifier = ref.read(sessionProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: const Text("Hamshiralik AI"),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 20),
            // Status Indicator
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.grey.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                _getStatusText(sessionState.status),
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ),
            
            const Spacer(),

            // Question Display
            if (sessionState.questions.isNotEmpty)
              Padding(
                padding: const EdgeInsets.all(20.0),
                child: Text(
                  sessionState.questions[sessionState.currentQuestionIndex].savol,
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
              ),

            // Feedback Display
            if (sessionState.status == SessionStatus.speakingFeedback && sessionState.lastFeedback != null)
              Padding(
                padding: const EdgeInsets.all(20.0),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: sessionState.lastFeedback!.correct ? Colors.green.withValues(alpha: 0.2) : Colors.red.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    children: [
                      Text(
                        "Ball: ${sessionState.lastFeedback!.score}/100",
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        sessionState.lastFeedback!.feedback,
                        style: const TextStyle(fontSize: 16),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),

            const Spacer(),

            // Start Session Button
            if (sessionState.status == SessionStatus.idle && sessionState.questions.isNotEmpty && sessionState.currentQuestionIndex == 0)
              ElevatedButton(
                onPressed: () {
                  sessionNotifier.startSession();
                },
                child: const Text("Mashg'ulotni boshlash"),
              ),

            // Microphone Button
            if (sessionState.status == SessionStatus.idle && sessionState.currentQuestionIndex > 0 || sessionState.status == SessionStatus.listening)
              MicrophoneButton(
                isListening: sessionState.status == SessionStatus.listening,
                onTap: () {
                  if (sessionState.status == SessionStatus.idle) {
                    sessionNotifier.startListening();
                  } else if (sessionState.status == SessionStatus.listening) {
                    sessionNotifier.stopListeningAndProcess();
                  }
                },
              ),

            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  String _getStatusText(SessionStatus status) {
    switch (status) {
      case SessionStatus.idle:
        return "Kutmoqda";
      case SessionStatus.askingQuestion:
        return "AI Savol beryapti...";
      case SessionStatus.listening:
        return "Sizni eshityapman...";
      case SessionStatus.transcribing:
        return "Javob tahlil qilinmoqda...";
      case SessionStatus.checking:
        return "AI tekshirmoqda...";
      case SessionStatus.speakingFeedback:
        return "Natija aytilmoqda...";
      case SessionStatus.nextQuestion:
        return "Keyingi savol...";
    }
  }
}
