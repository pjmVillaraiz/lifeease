class SchedulingSuggestion {
  final int suggestedLeadMinutes;
  final String note;

  const SchedulingSuggestion({
    required this.suggestedLeadMinutes,
    required this.note,
  });
}

class RuleBasedSchedulingEngine {
  SchedulingSuggestion buildSuggestion({
    required String category,
    required bool isRepeating,
  }) {
    final normalized = category.toLowerCase();

    if (normalized == "pill") {
      return const SchedulingSuggestion(
        suggestedLeadMinutes: 15,
        note: "Medication reminders work best with 15-minute lead time.",
      );
    }
    if (normalized == "appointment") {
      return const SchedulingSuggestion(
        suggestedLeadMinutes: 30,
        note: "Appointments benefit from earlier warning for preparation.",
      );
    }
    if (normalized == "food") {
      return const SchedulingSuggestion(
        suggestedLeadMinutes: 10,
        note: "Meal reminders can stay short and simple.",
      );
    }
    if (isRepeating) {
      return const SchedulingSuggestion(
        suggestedLeadMinutes: 10,
        note: "Repeating reminders usually need moderate lead time.",
      );
    }
    return const SchedulingSuggestion(
      suggestedLeadMinutes: 5,
      note: "Default quick reminder lead time.",
    );
  }
}
