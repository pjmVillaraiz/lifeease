/// Category and title hints shared by the reminder parser and home screen.
class VoiceReminderHints {
  const VoiceReminderHints._();

  static const Map<String, String> _titleByKeyword = {
    'doctor appointment': 'Doctor appointment',
    'appointment': 'Appointment',
    'check-up': 'Check-up',
    'checkup': 'Checkup',
    'breakfast': 'Breakfast',
    'lunch': 'Lunch',
    'dinner': 'Dinner',
    'brunch': 'Brunch',
    'snack': 'Snack',
    'food': 'Food',
    'meal': 'Meal',
    'medicine': 'Medicine',
    'medication': 'Medication',
    'meds': 'Medicine',
    'vitamin': 'Vitamins',
    'pill': 'Take pill',
    'pills': 'Take pill',
    'gamot': 'Gamot',
    'groceries': 'Groceries',
    'grocery': 'Groceries',
    'shopping': 'Shopping',
    'hospital': 'Hospital visit',
    'dentist': 'Dentist',
  };

  static String? titleFromText(String rawText) {
    final normalized = rawText.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
    for (final entry in _titleByKeyword.entries) {
      if (_containsWord(normalized, entry.key)) return entry.value;
    }
    return null;
  }

  static String categoryForText(String text) {
    final lower = text.trim().toLowerCase();
    if (_containsAny(lower, const [
      'medicine',
      'medication',
      'gamot',
      'vitamin',
      'pill',
      'pills',
      'meds',
      'tableta',
    ])) {
      return 'pill';
    }
    if (_containsAny(lower, const [
      'doctor',
      'appointment',
      'checkup',
      'check-up',
      'hospital',
      'dentist',
    ])) {
      return 'appointment';
    }
    if (_containsAny(lower, const [
      'food',
      'lunch',
      'dinner',
      'breakfast',
      'brunch',
      'snack',
      'meal',
      'eat',
      'water',
      'drink',
      'uminom',
      'inumin',
    ])) {
      return 'food';
    }
    if (_containsAny(lower, const [
      'buy',
      'groceries',
      'grocery',
      'shopping',
    ])) {
      return 'shopping';
    }
    if (_containsAny(lower, const ['event', 'calendar'])) {
      return 'calendar';
    }
    return 'general';
  }

  static bool _containsAny(String text, List<String> phrases) {
    return phrases.any((phrase) => _containsWord(text, phrase));
  }

  static bool containsTaskKeyword(String text) {
    const keywords = [
      'pill',
      'pills',
      'medicine',
      'medication',
      'meds',
      'vitamin',
      'vitamins',
      'gamot',
      'tableta',
      'appointment',
      'checkup',
      'check-up',
      'food',
      'lunch',
      'dinner',
      'breakfast',
      'brunch',
      'snack',
      'meal',
      'meals',
      'grocery',
      'groceries',
      'hospital',
      'dentist',
    ];
    final normalized = text.trim().toLowerCase();
    return keywords.any((keyword) => _containsWord(normalized, keyword));
  }

  static bool _containsWord(String text, String phrase) {
    if (phrase.contains(' ')) return text.contains(phrase);
    return RegExp(r'\b' + RegExp.escape(phrase) + r'\b').hasMatch(text);
  }
}
