import 'package:flutter_test/flutter_test.dart';
import 'package:lifeease/services/voice/voice_time_parser.dart';

void main() {
  group('VoiceTimeParser.parse', () {
    test('parses hour:minute with flexible separators', () {
      final am = VoiceTimeParser.parse('appointment at 3:41 am');
      expect(am?.hour, 3);
      expect(am?.minute, 41);

      final pm = VoiceTimeParser.parse('3.41 p.m.');
      expect(pm?.hour, 15);
      expect(pm?.minute, 41);

      final spaced = VoiceTimeParser.parse('3 41 PM');
      expect(spaced?.hour, 15);
      expect(spaced?.minute, 41);
    });

    test('parses compact and spaced hour-only times', () {
      expect(VoiceTimeParser.parse('take pill at 10pm')?.hour, 22);
      expect(VoiceTimeParser.parse('at 10 pm')?.hour, 22);
      expect(VoiceTimeParser.parse('3:5 am')?.hour, 3);
      expect(VoiceTimeParser.parse('3:5 am')?.minute, 5);
    });

    test('does not treat 10pm as 1:00 pm', () {
      final time = VoiceTimeParser.parse('10pm');
      expect(time?.hour, 22);
      expect(time?.minute, 0);
    });

    test('parses 24-hour times', () {
      final time = VoiceTimeParser.parse('remind me at 15:30');
      expect(time?.hour, 15);
      expect(time?.minute, 30);
    });

    test('parses morning, evening, noon, and midnight', () {
      expect(VoiceTimeParser.parse('tomorrow morning')?.hour, 8);
      expect(VoiceTimeParser.parse('this evening')?.hour, 18);
      expect(VoiceTimeParser.parse('at noon')?.hour, 12);
      expect(VoiceTimeParser.parse('midnight')?.hour, 0);
    });
  });

  group('VoiceTimeParser.hasExplicitTime', () {
    test('detects flexible explicit times', () {
      expect(VoiceTimeParser.hasExplicitTime('add food reminder at 3:05 PM'), isTrue);
      expect(VoiceTimeParser.hasExplicitTime('remind me in the morning'), isTrue);
      expect(VoiceTimeParser.hasExplicitTime('take pill'), isFalse);
    });
  });
}
