import 'dart:math';

import 'text_quality_filter.dart';

/// Offline Question Generator (Flutter/Dart version)
/// -----------------------------------------------------
/// Deliberately rule-based, not a wrapped AI model:
///  - explainable step-by-step in your capstone defense
///  - no model file to bundle, no inference cost on a student's phone
///  - fully offline, zero network calls
///
/// How it works:
///  1. Split extracted text (from PDF/PPTX) into sentences.
///  2. Keep sentences of reasonable length (not headers, not fragments)
///     AND that pass GrammarValidator.isPlausibleSentence - see
///     text_quality_filter.dart for why this uses a small closed
///     dictionary of English grammar words instead of a general
///     wordlist (a general dictionary would reject real Biology terms).
///  3. Detect a "Subject is/are Definition" pattern -> definition question.
///     Otherwise, fall back to a fill-in-the-blank on the sentence's
///     longest capitalized/noun-like phrase.
///  4. Build wrong-answer choices ("distractors") from other candidate
///     terms found elsewhere in the SAME document, so distractors stay
///     topically relevant instead of being random junk.
///  5. generateTermDefinitionPairs() builds term/definition pairs (no MCQ
///     distractors) for the Matching game mode, which needs pairs to
///     match rather than 4-choice questions.
///
/// NOTE: every generated question is meant to be reviewed before it
/// becomes playable. The app never silently overwrites bad content.
class GeneratedQuestion {
  final String questionText;
  final String correctAnswer;
  final List<String> choices;
  final String sourceSentence;

  GeneratedQuestion({
    required this.questionText,
    required this.correctAnswer,
    required this.choices,
    required this.sourceSentence,
  });
}

/// A term/definition pair for the Matching game mode.
class TermDefinitionPair {
  final String term;
  final String definition;
  final String sourceSentence;

  TermDefinitionPair({
    required this.term,
    required this.definition,
    required this.sourceSentence,
  });
}

class QuestionGenerator {
  static final RegExp _definitionPattern = RegExp(
    r'^(.{3,60}?)\s+(is|are|was|were)\s+(.{10,})$',
    caseSensitive: false,
  );

  static final RegExp _termPattern = RegExp(
    r'\b[A-Z][a-zA-Z]{2,}(?:\s+[a-z]{2,}){0,2}\b',
  );

  static List<GeneratedQuestion> generate(String rawText, {int count = 24}) {
    final sentences = _splitIntoSentences(rawText);
    final termPool = _buildTermPool(sentences);

    final results = <GeneratedQuestion>[];
    final seen = <String>{};

    for (final sentence in sentences) {
      if (results.length >= count) break;

      final match = _definitionPattern.firstMatch(sentence);
      GeneratedQuestion? question;

      if (match != null) {
        final subject = match.group(1)!.trim();
        if (!_passesQualityFilter(subject, sentence)) continue;
        question = _buildDefinitionQuestion(subject, sentence, termPool);
      } else {
        final term = _pickLongestCandidateTerm(sentence);
        if (term != null && _passesQualityFilter(term, sentence)) {
          question = _buildFillBlankQuestion(term, sentence, termPool);
        }
      }

      if (question != null && seen.add(question.questionText)) {
        results.add(question);
      }
    }
    return results;
  }

  /// Term/definition pairs for the Matching game mode - built only from
  /// sentences that matched the "Subject is/are Definition" pattern,
  /// since those give a clean, unambiguous term to match against. The
  /// definition is trimmed to a short, readable clause rather than kept
  /// as the full source sentence (see _conciseDefinition) - a matching
  /// tile needs to be scannable at a glance, not a full sentence.
  static List<TermDefinitionPair> generateTermDefinitionPairs(
    String rawText, {
    int count = 12,
  }) {
    final sentences = _splitIntoSentences(rawText);
    final pairs = <TermDefinitionPair>[];
    final seen = <String>{};

    for (final sentence in sentences) {
      if (pairs.length >= count) break;

      final match = _definitionPattern.firstMatch(sentence);
      if (match == null) continue;

      final subject = match.group(1)!.trim();
      if (!_passesQualityFilter(subject, sentence)) continue;

      final key = subject.toLowerCase();
      if (!seen.add(key)) continue;

      final definition = _conciseDefinition(match.group(3)!.trim());
      if (definition.isEmpty) continue;

      pairs.add(TermDefinitionPair(
        term: subject,
        definition: definition,
        sourceSentence: sentence,
      ));
    }
    return pairs;
  }

  static const int _maxDefinitionLength = 100;

  /// Trims a matched "is/are ..." clause into a short matching-tile
  /// definition: strip the leading article ("the"/"a"/"an"), drop a
  /// trailing period, then cut to a word-boundary length limit instead of
  /// showing the entire rest of the sentence.
  static String _conciseDefinition(String clause) {
    var text = GrammarValidator.stripLeadingArticle(clause);
    if (text.endsWith('.')) text = text.substring(0, text.length - 1);
    text = text.trim();
    if (text.length <= _maxDefinitionLength) return text;
    final cut = text.substring(0, _maxDefinitionLength);
    final lastSpace = cut.lastIndexOf(' ');
    final trimmed = lastSpace > 0 ? cut.substring(0, lastSpace) : cut;
    return '$trimmed…';
  }

  // Final acceptance gate applied to every generated question/pair before
  // it's added to a results list. Kept as one small, named function -
  // rather than folded silently into the regex matching - so each
  // rejection rule can be pointed to and explained individually in a
  // capstone defense:
  //  - subject/term is a pronoun or pronoun-led phrase (it/this/that/
  //    these/those/he/she/they/we, ...)
  //  - subject/term starts with a stopword suggesting a truncated
  //    fragment (and/but/or/however/therefore/thus/also, ...)
  //  - subject/term is under 3 characters after trimming
  //    (the three rules above are all enforced by
  //    GrammarValidator.isMeaningfulSubject)
  //  - the source sentence doesn't start with a capital letter, which is
  //    a strong signal it was sliced out of the middle of a longer
  //    sentence during PDF/PPTX text extraction (a stray line break, a
  //    bullet split mid-clause), even though it otherwise parses as a
  //    plausible sentence.
  static bool _passesQualityFilter(String subject, String sourceSentence) {
    if (!GrammarValidator.isMeaningfulSubject(subject)) return false;
    if (sourceSentence.isEmpty) return false;
    final first = sourceSentence[0];
    if (first != first.toUpperCase() || first == first.toLowerCase()) {
      return false;
    }
    return true;
  }

  static List<String> _splitIntoSentences(String text) {
    final cleaned = text.replaceAll('\n', ' ');
    final rawSentences = cleaned.split(RegExp(r'(?<=[.!?])\s+'));
    return rawSentences.map((s) => s.trim()).where((s) {
      final wordCount = s.split(RegExp(r'\s+')).length;
      if (wordCount < 6 || wordCount > 28) return false;
      return GrammarValidator.isPlausibleSentence(s);
    }).toList();
  }

  static List<String> _buildTermPool(List<String> sentences) {
    final pool = <String>{};
    for (final s in sentences) {
      for (final m in _termPattern.allMatches(s)) {
        final term = GrammarValidator.trimTrailingVerb(m.group(0)!.trim());
        if (GrammarValidator.isMeaningfulSubject(term)) {
          pool.add(term);
        }
      }
    }
    return pool.toList();
  }

  static String? _pickLongestCandidateTerm(String sentence) {
    final matches = _termPattern
        .allMatches(sentence)
        .map((m) => GrammarValidator.trimTrailingVerb(m.group(0)!.trim()))
        .where(GrammarValidator.isMeaningfulSubject);
    if (matches.isEmpty) return null;
    return matches.reduce((a, b) => a.length >= b.length ? a : b);
  }

  static GeneratedQuestion? _buildDefinitionQuestion(
      String subject,
      String sentence,
      List<String> termPool,
      ) {
    final distractors = _pickDistractors(termPool, subject, 3);
    if (distractors.length < 3) return null;

    final choices = [
      sentence,
      ...distractors.map(
              (d) => '$d (related term from the same material, not this definition)'),
    ]..shuffle(Random());

    return GeneratedQuestion(
      questionText: 'What is $subject?',
      correctAnswer: sentence,
      choices: choices,
      sourceSentence: sentence,
    );
  }

  static GeneratedQuestion? _buildFillBlankQuestion(
      String term,
      String sentence,
      List<String> termPool,
      ) {
    final distractors = _pickDistractors(termPool, term, 3);
    if (distractors.length < 3) return null;

    final blanked = sentence.replaceFirst(term, '_____');
    final choices = [term, ...distractors]..shuffle(Random());

    return GeneratedQuestion(
      questionText: 'Fill in the blank: "$blanked"',
      correctAnswer: term,
      choices: choices,
      sourceSentence: sentence,
    );
  }

  static List<String> _pickDistractors(
      List<String> pool, String exclude, int n) {
    final filtered = pool
        .where((t) => t.toLowerCase() != exclude.toLowerCase())
        .toSet()
        .toList()
      ..shuffle(Random());
    return filtered.take(n).toList();
  }
}

/// Top-level wrappers so QuestionGenerator's work can be handed to
/// Flutter's compute() (which requires a top-level/static function
/// reference) and run on a background isolate - a large document
/// shouldn't freeze the UI thread. Isolate messages must be simple/
/// sendable, so results are flattened to Map<String, dynamic> here
/// rather than passing GeneratedQuestion/TermDefinitionPair instances
/// across the isolate boundary directly.
List<Map<String, dynamic>> generateQuestionsIsolate(String rawText) {
  return QuestionGenerator.generate(rawText)
      .map((g) => {
    'questionText': g.questionText,
    'correctAnswer': g.correctAnswer,
    'choices': g.choices,
    'sourceSentence': g.sourceSentence,
  })
      .toList();
}

List<Map<String, dynamic>> generateTermDefinitionPairsIsolate(
    String rawText) {
  return QuestionGenerator.generateTermDefinitionPairs(rawText)
      .map((p) => {
    'term': p.term,
    'definition': p.definition,
    'sourceSentence': p.sourceSentence,
  })
      .toList();
}
