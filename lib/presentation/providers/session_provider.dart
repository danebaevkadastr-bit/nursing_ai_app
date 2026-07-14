import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/models/question_model.dart';
import '../../domain/models/feedback_result.dart';
import '../../data/repositories/question_repository_impl.dart';

enum SessionStatus {
  idle,
  askingQuestion,
  listening,
  transcribing,
  checking,
  speakingFeedback,
  nextQuestion,
}

class SessionState {
  final SessionStatus status;
  final List<QuestionModel> questions;
  final int currentQuestionIndex;
  final FeedbackResult? lastFeedback;

  SessionState({
    this.status = SessionStatus.idle,
    this.questions = const [],
    this.currentQuestionIndex = 0,
    this.lastFeedback,
  });

  SessionState copyWith({
    SessionStatus? status,
    List<QuestionModel>? questions,
    int? currentQuestionIndex,
    FeedbackResult? lastFeedback,
  }) {
    return SessionState(
      status: status ?? this.status,
      questions: questions ?? this.questions,
      currentQuestionIndex: currentQuestionIndex ?? this.currentQuestionIndex,
      lastFeedback: lastFeedback ?? this.lastFeedback,
    );
  }
}

class SessionNotifier extends Notifier<SessionState> {
  @override
  SessionState build() {
    _loadQuestions();
    return SessionState();
  }

  Future<void> _loadQuestions() async {
    final questions = await ref.read(questionRepositoryProvider).loadQuestions();
    state = state.copyWith(questions: questions);
  }

  void startSession() {
    if (state.questions.isEmpty) return;
    state = state.copyWith(status: SessionStatus.askingQuestion, currentQuestionIndex: 0);
    // TODO: AI ovozli savol berish mantiqini shu yerda chaqirish kerak
    _simulateAskingQuestion();
  }

  void startListening() {
    state = state.copyWith(status: SessionStatus.listening);
    // TODO: Mikrofonni yoqish
  }

  void stopListeningAndProcess() {
    state = state.copyWith(status: SessionStatus.transcribing);
    _simulateProcessing();
  }

  void _simulateAskingQuestion() async {
    await Future.delayed(const Duration(seconds: 2));
    state = state.copyWith(status: SessionStatus.idle); // Savol berib bo'ldi, endi foydalanuvchi javobini kutadi
  }

  void _simulateProcessing() async {
    // STT
    await Future.delayed(const Duration(seconds: 1));
    state = state.copyWith(status: SessionStatus.checking);
    
    // LLM Checking
    await Future.delayed(const Duration(seconds: 2));
    final mockFeedback = FeedbackResult(
      score: 80,
      correct: true,
      foundPoints: ["isitma", "bel og'rig'i"],
      missingPoints: ["dizuriya"],
      feedback: "Javobingiz qisman to'g'ri, yana dizuriya ham bo'lishi kerak edi.",
    );
    state = state.copyWith(status: SessionStatus.speakingFeedback, lastFeedback: mockFeedback);
    
    // TTS Feedback
    await Future.delayed(const Duration(seconds: 3));
    _nextQuestion();
  }

  void _nextQuestion() {
    if (state.currentQuestionIndex < state.questions.length - 1) {
      state = state.copyWith(
        currentQuestionIndex: state.currentQuestionIndex + 1,
        status: SessionStatus.askingQuestion,
      );
      _simulateAskingQuestion();
    } else {
      state = state.copyWith(status: SessionStatus.idle);
      // Mashg'ulot tugadi
    }
  }
}

final questionRepositoryProvider = Provider<QuestionRepository>((ref) {
  return QuestionRepositoryImpl();
});

final sessionProvider = NotifierProvider<SessionNotifier, SessionState>(() {
  return SessionNotifier();
});
