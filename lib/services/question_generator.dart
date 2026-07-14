import 'dart:math';

/// Offline Question Generator (Flutter/Dart version)
/// -----------------------------------------------------
/// Deliberately rule-based, not a wrapped AI model:
///  - explainable step-by-step in your capstone defense
///  - no model file to bundle, no inference cost on a student's phone
///  - fully offline, zero network calls
///
/// How it works:
///  1. Split extracted text (from PDF/PPTX) into sentences.
///  2. Keep sentences of reasonable length (not headers, not fragments).
///  3. Detect a "Subject is/are Definition" pattern -> definition question.
///     Otherwise, fall back to a fill-in-the-blank on the sentence's
///     longest capitalized/noun-like phrase.
///  4. Build wrong-answer choices ("distractors") from other candidate
///     terms found elsewhere in the SAME document, so distractors stay
///     topically relevant instead of being random junk.
///
/// NOTE: every generated question is meant to be reviewed by the admin
/// before it becomes playable. The app never auto-publishes generated
/// content straight to students.
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

class QuestionGenerator {
  static final RegExp _definitionPattern = RegExp(
    r'^(.{3,60}?)\s+(is|are|was|were)\s+(.{10,})$',
    caseSensitive: false,
  );

  static final RegExp _termPattern = RegExp(
    r'\b[A-Z][a-zA-Z]{2,}(?:\s+[a-z]{2,}){0,2}\b',
  );

  static List<GeneratedQuestion> generate(String rawText, {int count = 10}) {
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
        question = _buildDefinitionQuestion(subject, sentence, termPool);
      } else {
        final term = _pickLongestCandidateTerm(sentence);
        if (term != null) {
          question = _buildFillBlankQuestion(term, sentence, termPool);
        }
      }

      if (question != null && seen.add(question.questionText)) {
        results.add(question);
      }
    }
    return results;
  }

  static List<String> _splitIntoSentences(String text) {
    final cleaned = text.replaceAll('\n', ' ');
    final rawSentences = cleaned.split(RegExp(r'(?<=[.!?])\s+'));
    return rawSentences.map((s) => s.trim()).where((s) {
      final wordCount = s.split(RegExp(r'\s+')).length;
      return wordCount >= 6 && wordCount <= 28;
    }).toList();
  }

  static List<String> _buildTermPool(List<String> sentences) {
    final pool = <String>{};
    for (final s in sentences) {
      for (final m in _termPattern.allMatches(s)) {
        pool.add(m.group(0)!.trim());
      }
    }
    return pool.toList();
  }

  static String? _pickLongestCandidateTerm(String sentence) {
    final matches = _termPattern.allMatches(sentence).map((m) => m.group(0)!);
    if (matches.isEmpty) return null;
    return matches.reduce((a, b) => a.length >= b.length ? a : b);
  }

  static GeneratedQuestion? _buildDefinitionQuestion(
      String subject,
      String sentence,
      List<String> termPool,
      ) {
    if (subject.length < 3) return null;
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