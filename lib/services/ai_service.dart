import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_generative_ai/google_generative_ai.dart';

const String _kGeminiApiKey = '';

enum InterviewState { intro, mainQuestion, followUp, grading }

class Question {
  final int id;
  final String savol;
  final String izoh;

  const Question({
    required this.id,
    required this.savol,
    required this.izoh,
  });

  factory Question.fromJson(Map<String, dynamic> json) {
    return Question(
      id: (json['id'] as int?) ?? 0,
      savol: (json['savol'] as String?) ?? '',
      izoh: (json['izoh'] as String?) ?? '',
    );
  }
}

class AiService {
  late final GenerativeModel _model;
  final List<Question> _questions = [];
  int _currentIndex = 0;

  InterviewState _state = InterviewState.intro;
  int _followUpCount = 0;
  final int _maxFollowUps = 2; // 2 ta qo'shimcha savol
  Question? _currentQuestion;
  String _conversationHistory = '';

  AiService() {
    _model = GenerativeModel(
      model: 'gemini-1.5-flash',
      apiKey: _kGeminiApiKey,
    );
  }

  Future<void> loadQuestions() async {
    try {
      final String raw =
          await rootBundle.loadString('assets/data/questions.json');
      final List<dynamic> data = jsonDecode(raw) as List<dynamic>;
      final parsed = data
          .map((e) => Question.fromJson(e as Map<String, dynamic>))
          .where((q) => q.izoh.trim().isNotEmpty && q.savol.trim().isNotEmpty)
          .toList();
      _questions.addAll(parsed);
      _questions.shuffle();
    } catch (e) {
      debugPrint('Savollar yuklanmadi: $e');
    }
  }

  bool get hasQuestions => _questions.isNotEmpty;

  String getInitialGreeting() {
    _state = InterviewState.intro;
    _followUpCount = 0;
    _conversationHistory = '';
    return "Assalomu alaykum! Men AI hamshirasiman. Bugungi imtihonimizga tayyormisiz?";
  }

  void resetSession() {
    _state = InterviewState.intro;
    _followUpCount = 0;
    _conversationHistory = '';
    _currentQuestion = null;
  }

  /// Foydalanuvchidan kelgan gapni qabul qilib, holatga qarab keyingi AI gapini qaytaradi
  Future<String> processInput(String userInput) async {
    if (_questions.isEmpty) return 'Kechirasiz, savollar bazasi topilmadi.';

    switch (_state) {
      case InterviewState.intro:
      case InterviewState.grading:
        // Yangi mavzuni boshlaymiz
        return await _startNewTopic();

      case InterviewState.mainQuestion:
      case InterviewState.followUp:
        // Foydalanuvchi javobini tarixga qo'shamiz
        _conversationHistory += "Talaba: \$userInput\\n";

        if (_followUpCount < _maxFollowUps) {
          // Yana qo'shimcha savol beramiz
          _followUpCount++;
          _state = InterviewState.followUp;
          return await _generateFollowUp();
        } else {
          // Baholash bosqichi
          _state = InterviewState.grading;
          return await _generateGrading();
        }
    }
  }

  Future<String> _startNewTopic() async {
    _currentQuestion = _questions[_currentIndex % _questions.length];
    _currentIndex++;

    _followUpCount = 0;
    _conversationHistory = "Asosiy savol: \${_currentQuestion!.savol}\\n";
    _state = InterviewState.mainQuestion;

    final prompt = '''
Sen tibbiyot fani bo'yicha og'zaki imtihon o'tkazayotgan mehribon hamshira ustazasan.
Foydalanuvchiga quyidagi savolni jonli o'zbek tilida, qisqa va tushunarli qilib ber.
Savol raqami yoki "savol:" degan so'zlarni aytma. Shunchaki mazmunini so'ra.
Savol: \${_currentQuestion!.savol}
''';

    try {
      final response = await _model.generateContent([Content.text(prompt)]);
      final text = response.text ?? '';
      if (text.isNotEmpty) {
        final generatedQuestion = text.trim();
        _conversationHistory += "AI: \$generatedQuestion\\n";
        return generatedQuestion;
      }
    } catch (e) {
      debugPrint('Gemini savol xatosi: $e');
    }
    
    _conversationHistory += "AI: \${_currentQuestion!.savol}\\n";
    return _currentQuestion!.savol;
  }

  Future<String> _generateFollowUp() async {
    final prompt = '''
Sen tibbiyot fani bo'yicha og'zaki imtihon o'tkazayotgan hamshirasan.
Quyida savol, to'g'ri javob asoslari va shu paytgacha bo'lgan suhbat tarixi keltirilgan.
Sening vazifang: Suhbat tarixini o'qib chiq. Agar talaba javobda xato qilgan bo'lsa yoki to'liq javob bermagan bo'lsa, xatosini to'g'irlamasdan turib, yana bitta mantiqiy qo'shimcha (follow-up) savol ber. Maqsad talabani to'liq tushunishiga va fikrini to'g'ri ifodalashiga undash.
Javobing mehribon, rag'batlantiruvchi va 1-2 gapdan iborat bo'lsin. Hech qanday baho qo'yma!

Asosiy savol: \${_currentQuestion!.savol}
To'g'ri javob asoslari: \${_currentQuestion!.izoh}
Suhbat tarixi:
\$_conversationHistory

AI (Sening keyingi qo'shimcha savoling):
''';

    try {
      final response = await _model.generateContent([Content.text(prompt)]);
      final text = response.text ?? '';
      if (text.isNotEmpty) {
        final generatedFollowUp = text.trim();
        _conversationHistory += "AI: \$generatedFollowUp\\n";
        return generatedFollowUp;
      }
    } catch (e) {
      debugPrint('Gemini follow-up xatosi: $e');
    }
    
    return "Tushunarli. Keling, shu haqida yana nimalarni bilishingizni aytib bersangiz?";
  }

  Future<String> _generateGrading() async {
    final prompt = '''
Sen tibbiyot fani bo'yicha og'zaki imtihon o'tkazayotgan hamshirasan.
Mavzu bo'yicha suhbat yakunlandi. Quyida asosiy savol, to'g'ri javob asoslari va talaba bilan bo'lgan suhbat tarixi keltirilgan.
Sening vazifang:
1. Talabaning bilimi va suhbat tarixini tahlil qilib, umumiy javoblari uchun 1 dan 20 gacha shkalada ball qo'y (masalan, 15/20).
2. Nima to'g'ri va nima noto'g'ri/kam qilinganini qisqacha va mehribonlik bilan tushuntir (2-3 gap).
3. Oxirida "Yangi savolga o'tamizmi?" deb so'ra.

Asosiy savol: \${_currentQuestion!.savol}
To'g'ri javob asoslari: \${_currentQuestion!.izoh}
Suhbat tarixi:
\$_conversationHistory

AI (Baholash va xulosa):
''';

    try {
      final response = await _model.generateContent([Content.text(prompt)]);
      final text = response.text ?? '';
      if (text.isNotEmpty) return text.trim();
    } catch (e) {
      debugPrint('Gemini grading xatosi: $e');
    }
    
    return "Rahmat. Ushbu mavzu bo'yicha yaxshi harakat qildingiz. Yangi savolga o'tamizmi?";
  }
}
