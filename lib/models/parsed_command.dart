class ParsedCommand {
  final String intent;
  final String? task;
  final String? date;
  final String? time;

  const ParsedCommand({
    required this.intent,
    this.task,
    this.date,
    this.time,
  });

  Map<String, dynamic> toJson() {
    return {
      'intent': intent,
      'task': task,
      'date': date,
      'time': time,
    };
  }

  factory ParsedCommand.fromJson(Map<String, dynamic> json) {
    return ParsedCommand(
      intent: json['intent']?.toString() ?? 'unknown',
      task: json['task']?.toString(),
      date: json['date']?.toString(),
      time: json['time']?.toString(),
    );
  }

  @override
  String toString() {
    return 'ParsedCommand(intent: $intent, task: $task, date: $date, time: $time)';
  }
}
