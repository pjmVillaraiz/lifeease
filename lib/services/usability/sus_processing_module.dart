class SusProcessingModule {
  double computeScore(List<int> answers) {
    if (answers.length != 10) {
      throw ArgumentError("SUS requires exactly 10 answers.");
    }
    var raw = 0;
    for (var i = 0; i < answers.length; i++) {
      final value = answers[i];
      if (value < 1 || value > 5) {
        throw ArgumentError("Each SUS answer must be between 1 and 5.");
      }
      if ((i + 1).isOdd) {
        raw += value - 1;
      } else {
        raw += 5 - value;
      }
    }
    return raw * 2.5;
  }

  String getPurposeDescription() {
    return "SUS measures how easy and usable the app feels to people. "
        "It helps identify if users can learn and use features quickly.";
  }

  String getRatingBand(double score) {
    if (score >= 80) return "Excellent";
    if (score >= 68) return "Good";
    if (score >= 51) return "OK";
    return "Needs Improvement";
  }
}
