class LanguageTranslationProcessingModule {
  static const Map<String, String> _enToTl = {
    "good morning": "magandang umaga",
    "good afternoon": "magandang hapon",
    "good evening": "magandang gabi",
    "take medicine": "uminom ng gamot",
    "call emergency": "tumawag sa emergency",
    "add reminder": "magdagdag ng paalala",
    "how are you": "kumusta ka",
  };

  static const Map<String, String> _tlToEn = {
    "magandang umaga": "good morning",
    "magandang hapon": "good afternoon",
    "magandang gabi": "good evening",
    "uminom ng gamot": "take medicine",
    "tumawag sa emergency": "call emergency",
    "magdagdag ng paalala": "add reminder",
    "kumusta ka": "how are you",
  };

  String translate({
    required String text,
    required bool toTagalog,
  }) {
    final key = text.trim().toLowerCase();
    if (key.isEmpty) return "";
    if (toTagalog) return _enToTl[key] ?? text;
    return _tlToEn[key] ?? text;
  }
}
