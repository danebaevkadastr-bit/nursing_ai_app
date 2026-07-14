class FeedbackResult {
  final int score;
  final bool correct;
  final List<String> foundPoints;
  final List<String> missingPoints;
  final String feedback;

  FeedbackResult({
    required this.score,
    required this.correct,
    required this.foundPoints,
    required this.missingPoints,
    required this.feedback,
  });

  factory FeedbackResult.fromJson(Map<String, dynamic> json) {
    return FeedbackResult(
      score: json['score'] as int,
      correct: json['correct'] as bool,
      foundPoints: List<String>.from(json['found_points']),
      missingPoints: List<String>.from(json['missing_points']),
      feedback: json['feedback'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'score': score,
      'correct': correct,
      'found_points': foundPoints,
      'missing_points': missingPoints,
      'feedback': feedback,
    };
  }
}
