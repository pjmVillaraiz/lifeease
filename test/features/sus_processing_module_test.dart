import 'package:flutter_test/flutter_test.dart';
import 'package:lifeease/features/sus_evaluation/application/sus_processing_module.dart';

void main() {
  group('SusProcessingModule', () {
    test(
      'computes SUS score using alternating positive and negative items',
      () {
        final module = SusProcessingModule();

        final score = module.computeScore([5, 1, 5, 1, 5, 1, 5, 1, 5, 1]);

        expect(score, 100);
        expect(module.getRatingBand(score), 'Excellent');
      },
    );

    test('rejects incomplete SUS answers', () {
      final module = SusProcessingModule();

      expect(() => module.computeScore([1, 2, 3]), throwsArgumentError);
    });
  });
}
