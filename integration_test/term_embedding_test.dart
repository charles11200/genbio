import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:genbio/services/term_embedding_service.dart';

/// Runs as a real app process on-device rather than flutter_test's
/// host-side runner, which can't load tflite_flutter's native library -
/// that's why this can't just live under test/. Mirrors the manual
/// on-device verification done before this was automated (see git history
/// around the TFLite integration), now repeatable via
/// `flutter test integration_test/term_embedding_test.dart -d <device>`.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('TermEmbeddingService (real on-device inference)', () {
    testWidgets('embeds a known Biology term as a unit-length vector',
        (tester) async {
      final vec = await TermEmbeddingService.instance.embed('mitochondria');
      expect(vec, isNotNull);
      final norm = vec!.map((x) => x * x).reduce((a, b) => a + b);
      expect(norm, closeTo(1.0, 1e-3));
    });

    testWidgets('returns null for text with no recognized vocabulary',
        (tester) async {
      final vec = await TermEmbeddingService.instance
          .embed('zzqxxnotarealword qqjjvv');
      expect(vec, isNull);
    });

    testWidgets(
        'ranks a known-related organelle above an unrelated word for a '
        'classic pair', (tester) async {
      final ranked = await TermEmbeddingService.instance.pickTopSimilar(
        'mitochondria',
        ['chloroplast', 'ecosystem', 'legislature'],
        1,
      );
      expect(ranked, isNotEmpty);
      expect(ranked.first, 'chloroplast');
    });

    testWidgets(
        'pickTopSimilar returns fewer than n when too few candidates are '
        'recognized', (tester) async {
      final ranked = await TermEmbeddingService.instance.pickTopSimilar(
        'mitochondria',
        ['zzqxxnotarealword'],
        3,
      );
      expect(ranked.length, lessThan(3));
    });
  });
}
