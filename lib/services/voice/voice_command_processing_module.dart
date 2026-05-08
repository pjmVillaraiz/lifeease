enum LightweightNlpModel {
  gemma2bIt,
  mobileBertIntent,
}

enum VoiceIntentType {
  addReminder,
  callEmergency,
  translate,
  summarize,
  unknown,
}

class VoiceIntentResult {
  final VoiceIntentType type;
  final String normalizedText;
  final String summary;
  final LightweightNlpModel recommendedPrimaryModel;
  final LightweightNlpModel recommendedSecondaryModel;

  const VoiceIntentResult({
    required this.type,
    required this.normalizedText,
    required this.summary,
    required this.recommendedPrimaryModel,
    required this.recommendedSecondaryModel,
  });
}

class VoiceCommandProcessingModule {
  VoiceIntentResult parse(String rawText) {
    final text = rawText.trim().toLowerCase();
    final normalized = text.replaceAll(RegExp(r"\s+"), " ");

    final type = _detectIntent(normalized);
    return VoiceIntentResult(
      type: type,
      normalizedText: normalized,
      summary: summarizeText(rawText),
      recommendedPrimaryModel: LightweightNlpModel.gemma2bIt,
      recommendedSecondaryModel: LightweightNlpModel.mobileBertIntent,
    );
  }

  String summarizeText(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return "";
    final sentences = trimmed.split(RegExp(r"(?<=[.!?])\s+"));
    if (sentences.length == 1) return sentences.first;
    return "${sentences.first} ${sentences.last}".trim();
  }

  VoiceIntentType _detectIntent(String text) {
    if (text.contains("add reminder") ||
        text.contains("remind me") ||
        text.contains("schedule")) {
      return VoiceIntentType.addReminder;
    }
    if (text.contains("call") ||
        text.contains("emergency") ||
        text.contains("dial")) {
      return VoiceIntentType.callEmergency;
    }
    if (text.contains("translate") ||
        text.contains("tagalog") ||
        text.contains("english")) {
      return VoiceIntentType.translate;
    }
    if (text.contains("summarize") || text.contains("summary")) {
      return VoiceIntentType.summarize;
    }
    return VoiceIntentType.unknown;
  }
}
