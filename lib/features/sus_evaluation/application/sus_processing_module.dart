import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class SusEvaluationResult {
  final double score;
  final String rating;
  final String interpretation;
  final List<String> improvements;
  final DateTime createdAt;

  const SusEvaluationResult({
    required this.score,
    required this.rating,
    required this.interpretation,
    this.improvements = const [],
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
    'sus_score': score.round(),
    'rating': rating,
    'interpretation': interpretation,
    'improvements': improvements,
    'created_at': createdAt.toIso8601String(),
  };
}

class SusProcessingModule {
  static const String _storageKey = 'sus_results';

  static const questions = [
    'I think that I would like to use LifeEase frequently.',
    'I found LifeEase unnecessarily complex.',
    'I thought LifeEase was easy to use.',
    'I think that I would need support to use LifeEase.',
    'I found the app features well integrated.',
    'I thought there was too much inconsistency in the app.',
    'I imagine most people would learn LifeEase quickly.',
    'I found LifeEase very cumbersome to use.',
    'I felt confident using LifeEase.',
    'I needed to learn many things before using LifeEase.',
  ];

  double computeScore(List<int> answers) {
    if (answers.length != 10) {
      throw ArgumentError('SUS requires exactly 10 answers.');
    }
    var raw = 0;
    for (var i = 0; i < answers.length; i++) {
      final value = answers[i];
      if (value < 1 || value > 5) {
        throw ArgumentError('Each SUS answer must be between 1 and 5.');
      }
      if ((i + 1).isOdd) {
        raw += value - 1;
      } else {
        raw += 5 - value;
      }
    }
    return raw * 2.5;
  }

  SusEvaluationResult evaluate(List<int> answers) {
    final score = computeScore(answers);
    final rating = getRatingBand(score);
    return SusEvaluationResult(
      score: score,
      rating: rating,
      interpretation: _interpret(score),
      improvements: buildImprovementPlan(answers),
      createdAt: DateTime.now(),
    );
  }

  List<String> buildImprovementPlan(List<int> answers) {
    if (answers.length != 10) {
      throw ArgumentError('SUS requires exactly 10 answers.');
    }

    final improvements = <String>[];
    void add(String value) {
      if (!improvements.contains(value)) improvements.add(value);
    }

    if (answers[0] <= 3) {
      add('Make daily reminders faster to reach from the home screen.');
    }
    if (answers[1] >= 3 || answers[7] >= 3) {
      add('Reduce form steps and keep reminder actions visible and simple.');
    }
    if (answers[2] <= 3) {
      add('Improve labels, spacing, and defaults so first-time use feels clear.');
    }
    if (answers[3] >= 3 || answers[9] >= 3) {
      add('Add clearer onboarding and contextual help for voice and reminder setup.');
    }
    if (answers[4] <= 3 || answers[5] >= 3) {
      add('Make voice, translation, scheduling, and notifications feel more consistent.');
    }
    if (answers[6] <= 3) {
      add('Simplify navigation so new users can learn the app quickly.');
    }
    if (answers[8] <= 3) {
      add('Add stronger success feedback after saving, completing, or changing reminders.');
    }

    if (improvements.isEmpty) {
      return const [
        'Maintain the current design and continue monitoring SUS after each release.',
      ];
    }
    return improvements.take(4).toList();
  }

  Future<void> saveResult(SusEvaluationResult result) async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getStringList(_storageKey) ?? [];
    saved.insert(0, jsonEncode(result.toJson()));
    await prefs.setStringList(_storageKey, saved.take(25).toList());
  }

  Future<List<SusEvaluationResult>> loadResults() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getStringList(_storageKey) ?? [];
    return saved.map((raw) {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final score = (json['sus_score'] as num).toDouble();
      return SusEvaluationResult(
        score: score,
        rating: json['rating'] as String,
        interpretation: json['interpretation'] as String,
        improvements:
            (json['improvements'] as List<dynamic>?)
                ?.map((item) => item.toString())
                .toList() ??
            const [],
        createdAt:
            DateTime.tryParse(json['created_at'] as String? ?? '') ??
            DateTime.now(),
      );
    }).toList();
  }

  String getPurposeDescription() {
    return 'SUS measures ease of learning, ease of use, confidence, navigation '
        'simplicity, and accessibility effectiveness.';
  }

  String getRatingBand(double score) {
    if (score >= 80) return 'Excellent';
    if (score >= 68) return 'Good';
    if (score >= 51) return 'OK';
    return 'Needs Improvement';
  }

  String _interpret(double score) {
    if (score >= 80) return 'Highly usable system';
    if (score >= 68) return 'Usable system with minor improvements needed';
    if (score >= 51) return 'Moderately usable system needing refinement';
    return 'Usability needs significant improvement';
  }
}
