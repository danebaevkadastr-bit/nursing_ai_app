class QuestionModel {
  final int id;
  final String fan;
  final String savol;
  final List<String> togriJavob;
  final String izoh;

  QuestionModel({
    required this.id,
    required this.fan,
    required this.savol,
    required this.togriJavob,
    required this.izoh,
  });

  factory QuestionModel.fromJson(Map<String, dynamic> json) {
    return QuestionModel(
      id: json['id'] as int,
      fan: json['fan'] as String,
      savol: json['savol'] as String,
      togriJavob: List<String>.from(json['togri_javob']),
      izoh: json['izoh'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'fan': fan,
      'savol': savol,
      'togri_javob': togriJavob,
      'izoh': izoh,
    };
  }
}
