import 'package:flutter_test/flutter_test.dart';
import 'package:genbio/services/question_generator.dart';
import 'package:genbio/services/text_quality_filter.dart';

void main() {
  group('GrammarValidator.isPlausibleSentence', () {
    test('accepts a normal grammatical sentence', () {
      expect(
        GrammarValidator.isPlausibleSentence(
          'The mitochondria is the powerhouse of the eukaryotic cell.',
        ),
        isTrue,
      );
    });

    test('rejects a sentence with no linking/auxiliary verb', () {
      expect(
        GrammarValidator.isPlausibleSentence(
          'Chapter Three Cellular Biology Overview Diagram Figure Legend',
        ),
        isFalse,
      );
    });

    test('rejects a mostly-numeric/table-like line', () {
      expect(
        GrammarValidator.isPlausibleSentence(
          'Table 3 2 1 45 2 67 8 9 10 11 12 13 14',
        ),
        isFalse,
      );
    });

    test('rejects an ALL CAPS header line', () {
      expect(
        GrammarValidator.isPlausibleSentence(
          'THE MITOCHONDRIA IS THE POWERHOUSE OF THE EUKARYOTIC CELL',
        ),
        isFalse,
      );
    });

    test('accepts a sentence using an action verb instead of a linking verb',
        () {
      expect(
        GrammarValidator.isPlausibleSentence(
          'Mitochondria produce energy through the process of cellular '
          'respiration.',
        ),
        isTrue,
      );
    });

    test('recognizes inflected forms of action verbs via stemming', () {
      expect(
        GrammarValidator.isPlausibleSentence(
          'The chloroplast produces glucose using sunlight captured by '
          'the leaf.',
        ),
        isTrue,
      );
    });

    test('rejects a header line even when it contains a linking verb', () {
      expect(
        GrammarValidator.isPlausibleSentence(
          'Chapter Three Overview Table Figure What is a Cell Structure '
          'Diagram',
        ),
        isFalse,
      );
    });
  });

  group('GrammarValidator.trimTrailingVerb', () {
    test('strips a trailing linking verb', () {
      expect(GrammarValidator.trimTrailingVerb('The mitochondria is'),
          'The mitochondria');
    });

    test('strips a trailing inflected action verb', () {
      expect(GrammarValidator.trimTrailingVerb('Chloroplasts produces'),
          'Chloroplasts');
    });

    test('leaves a clean term untouched', () {
      expect(GrammarValidator.trimTrailingVerb('Photosynthesis'),
          'Photosynthesis');
    });
  });

  group('GrammarValidator.isMeaningfulSubject', () {
    test('rejects pronoun/filler-only subjects', () {
      expect(GrammarValidator.isMeaningfulSubject('It'), isFalse);
      expect(GrammarValidator.isMeaningfulSubject('This'), isFalse);
      expect(GrammarValidator.isMeaningfulSubject('The'), isFalse);
    });

    test('accepts real Biology terms not found in a general dictionary', () {
      expect(GrammarValidator.isMeaningfulSubject('Mitochondria'), isTrue);
      expect(GrammarValidator.isMeaningfulSubject('Homeostasis'), isTrue);
      expect(GrammarValidator.isMeaningfulSubject('Chloroplast'), isTrue);
    });
  });

  group('GrammarValidator.stripLeadingArticle', () {
    test('strips "the"/"a"/"an" from the front of a phrase', () {
      expect(GrammarValidator.stripLeadingArticle('the powerhouse of the cell'),
          'powerhouse of the cell');
      expect(GrammarValidator.stripLeadingArticle('a stable internal state'),
          'stable internal state');
    });

    test('leaves a phrase with no leading article untouched', () {
      expect(GrammarValidator.stripLeadingArticle('Mitochondria'),
          'Mitochondria');
    });
  });

  group('QuestionGenerator.generate', () {
    const sample = 'The mitochondria is the powerhouse of the eukaryotic '
        'cell. The nucleus is the control center of the eukaryotic cell. '
        'The ribosome is the site of protein synthesis in the cell. '
        'Photosynthesis is the process plants use to convert light into '
        'chemical energy stored in glucose molecules for later use.';

    test('produces MCQ questions with 4 unique choices including the answer',
        () {
      final questions = QuestionGenerator.generate(sample);
      expect(questions, isNotEmpty);
      for (final q in questions) {
        expect(q.choices.length, 4);
        expect(q.choices.toSet().length, 4);
        expect(q.choices, contains(q.correctAnswer));
      }
    });

    test('is deterministic in which questions it selects, not just order',
        () {
      final first =
          QuestionGenerator.generate(sample).map((q) => q.questionText).toSet();
      final second =
          QuestionGenerator.generate(sample).map((q) => q.questionText).toSet();
      expect(first, second);
    });

    test('produces nothing from a header/table-only document', () {
      const junk = 'Chapter Three Cellular Biology Overview Diagram Figure '
          '1 2 3 4 5 6 7 8 9 10 11 12 13 SECTION FOUR RESULTS AND DISCUSSION';
      expect(QuestionGenerator.generate(junk), isEmpty);
    });

    test('returns an empty list (not a throw) for a single short fragment '
        'with no valid sentence pattern', () {
      const fragment = 'Cells.';
      expect(() => QuestionGenerator.generate(fragment), returnsNormally);
      expect(QuestionGenerator.generate(fragment), isEmpty);
    });

    test('a "Mitochondria is..." sentence produces a question about '
        'Mitochondria', () {
      const bio = 'Mitochondria is the powerhouse of the cell. '
          'Nucleus is the control center of the cell. '
          'Ribosome is the site of protein synthesis. '
          'Chloroplast is the site of photosynthesis in plant cells.';
      final questions = QuestionGenerator.generate(bio);
      expect(
        questions.any((q) => q.questionText.contains('Mitochondria')),
        isTrue,
      );
    });

    test('filters out a sentence that opens with a pronoun ("It is...")',
        () {
      const bio = 'Mitochondria is the powerhouse of the cell. '
          'Nucleus is the control center of the cell. '
          'Ribosome is the site of protein synthesis. '
          'It is responsible for producing most of the energy the cell '
          'needs to function.';
      final questions = QuestionGenerator.generate(bio);
      expect(
        questions.any((q) =>
            q.sourceSentence.startsWith('It is responsible')),
        isFalse,
      );
    });
  });

  group('QuestionGenerator.generateTermDefinitionPairs', () {
    test('builds term/definition pairs for the Matching game mode', () {
      const text = 'Homeostasis is the maintenance of stable internal '
          'conditions despite external environmental changes occurring. '
          'Osmosis is the diffusion of water across a semipermeable '
          'membrane from low to high solute concentration.';
      final pairs = QuestionGenerator.generateTermDefinitionPairs(text);

      expect(pairs, isNotEmpty);
      for (final pair in pairs) {
        expect(pair.term, isNotEmpty);
        expect(pair.definition, isNotEmpty);
        expect(pair.sourceSentence, isNotEmpty);
      }
    });

    test('strips the leading article from the definition', () {
      const text = 'Osmosis is the diffusion of water across a '
          'semipermeable membrane from low to high solute concentration.';
      final pairs = QuestionGenerator.generateTermDefinitionPairs(text);
      final osmosis = pairs.firstWhere((p) => p.term == 'Osmosis');
      expect(osmosis.definition.startsWith('the '), isFalse);
    });
  });

  group('QuestionGenerator quality filter', () {
    test('accepts a definition sentence that starts with a capital letter',
        () {
      const text = 'Photosynthesis is the process plants use to convert '
          'light into chemical energy for later use. Respiration is the '
          'process cells use to release energy from glucose molecules.';
      final pairs = QuestionGenerator.generateTermDefinitionPairs(text);
      expect(pairs.any((p) => p.term == 'Photosynthesis'), isTrue);
    });

    test('rejects a definition sentence that does not start with a capital '
        'letter, since that signals a mid-sentence extraction fragment',
        () {
      const text = 'photosynthesis is the process plants use to convert '
          'light into chemical energy for later use. Respiration is the '
          'process cells use to release energy from glucose molecules.';
      final pairs = QuestionGenerator.generateTermDefinitionPairs(text);
      expect(
        pairs.any((p) => p.term.toLowerCase() == 'photosynthesis'),
        isFalse,
      );
    });
  });
}