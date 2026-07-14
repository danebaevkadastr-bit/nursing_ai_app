import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../../domain/models/question_model.dart';

abstract class QuestionRepository {
  Future<List<QuestionModel>> loadQuestions();
}

class QuestionRepositoryImpl implements QuestionRepository {
  @override
  Future<List<QuestionModel>> loadQuestions() async {
    try {
      final String response = await rootBundle.loadString('assets/data/questions.json');
      final data = await json.decode(response) as List<dynamic>;
      return data.map((json) => QuestionModel.fromJson(json)).toList();
    } catch (e) {
      debugPrint("Error loading questions: $e");
      return [];
    }
  }
}
