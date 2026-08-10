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
  // Term to compare candidate distractors against for embedding-based
  // re-ranking (the subject for a definition question, the blanked term
  // for a fill-in-the-blank question) - see TermEmbeddingService.
  final String compareTerm;
  // Every other same-document term available as a distractor, beyond the
  // 3 already randomly picked into `choices` - lets a later re-ranking
  // pass pick better ones without re-deriving the pool from scratch.
  final List<String> distractorCandidates;
  // Whether a distractor term needs the "(related term from the same
  // material...)" suffix when formatted into a choice string - see
  // formatChoices.
  final bool isDefinitionStyle;
  // Other same-document terms' own "Term is Definition" sentences (key:
  // lowercased term), for rendering a definition-style distractor as a
  // real sentence instead of a bare term - see formatChoices. Carried on
  // the question (rather than looked up fresh) so the later embedding-
  // based re-ranking pass in ContentImportService can format its
  // replacement choices the same way.
  final Map<String, String> termDefinitions;

  GeneratedQuestion({
    required this.questionText,
    required this.correctAnswer,
    required this.choices,
    required this.sourceSentence,
    required this.compareTerm,
    required this.distractorCandidates,
    required this.isDefinitionStyle,
    required this.termDefinitions,
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

  /// Question phrasings for a definition-style item. Every generated
  /// question used to open with a literal "What is X?", which made a whole
  /// reviewer read as one repeated question. `{t}` is the term.
  ///
  /// The template is chosen by _stableIndex (a content hash of the term),
  /// NOT at random: generation has to stay deterministic so re-importing
  /// the same material produces the same reviewer, and so the
  /// questionText-based deduplication in generate() stays reliable.
  static const List<String> _definitionTemplates = [
    'What is {t}?',
    'Which of the following best describes {t}?',
    '{t} means which of the following?',
    'How is {t} best defined?',
    'Which statement correctly defines {t}?',
    '{t} refers to which of the following?',
  ];

  /// Same idea for fill-in-the-blank items. `{s}` is the blanked sentence.
  static const List<String> _blankTemplates = [
    'Fill in the blank: "{s}"',
    'Complete the statement: "{s}"',
    'Which term completes this statement? "{s}"',
    'Which term correctly fills the blank? "{s}"',
  ];

  /// Deterministic content hash -> index. Dart's own String.hashCode is
  /// not guaranteed stable across runs, and generate() must be reproducible
  /// (see _definitionTemplates), so this computes its own fixed hash.
  static int _stableIndex(String key, int modulo) {
    var hash = 0;
    for (final unit in key.codeUnits) {
      hash = (hash * 31 + unit) & 0x7FFFFFFF;
    }
    return hash % modulo;
  }

  // Effectively "no cap" - the student picks how many questions they
  // actually want *after* import (see PreparedImport.maxQuestions), so
  // generation's job is to report the material's true ceiling rather than
  // silently stop at an arbitrary number. Still a finite guard against a
  // pathologically large document.
  static const int _generationCeiling = 500;

  static List<GeneratedQuestion> generate(
    String rawText, {
    int count = _generationCeiling,
  }) {
    final sentences = _splitIntoSentences(rawText);
    final termPool = _buildTermPool(sentences);
    final termDefinitions = _buildTermDefinitions(sentences);

    final results = <GeneratedQuestion>[];
    final seen = <String>{};

    for (final sentence in sentences) {
      if (results.length >= count) break;

      final match = _definitionPattern.firstMatch(sentence);
      GeneratedQuestion? question;

      if (match != null) {
        final subject = match.group(1)!.trim();
        if (!_passesQualityFilter(subject, sentence)) continue;
        question = _buildDefinitionQuestion(
          subject,
          _conciseDefinition(match.group(3)!.trim()),
          sentence,
          termPool,
          termDefinitions,
        );
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
    int count = _generationCeiling,
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

  /// Maps each definition-pattern subject (lowercased, article-stripped so
  /// it matches the term pool) to its definition CLAUSE - "mitochondria" ->
  /// "powerhouse of the cell", not the whole "Mitochondria is the
  /// powerhouse of the cell." sentence. Storing clauses is what lets every
  /// choice in a definition question be phrased the same way, with none of
  /// them naming its own term - see _buildDefinitionQuestion.
  static Map<String, String> _buildTermDefinitions(List<String> sentences) {
    final defs = <String, String>{};
    for (final sentence in sentences) {
      final match = _definitionPattern.firstMatch(sentence);
      if (match == null) continue;
      final subject = match.group(1)!.trim();
      if (!_passesQualityFilter(subject, sentence)) continue;
      final definition = _conciseDefinition(match.group(3)!.trim());
      if (definition.isEmpty) continue;
      final key = GrammarValidator.stripLeadingArticle(subject).toLowerCase();
      defs.putIfAbsent(key, () => definition);
    }
    return defs;
  }

  static String? _pickLongestCandidateTerm(String sentence) {
    final matches = _termPattern
        .allMatches(sentence)
        .map((m) => GrammarValidator.trimTrailingVerb(m.group(0)!.trim()))
        .where(GrammarValidator.isMeaningfulSubject);
    if (matches.isEmpty) return null;
    return matches.reduce((a, b) => a.length >= b.length ? a : b);
  }

  /// Builds a definition-style MCQ.
  ///
  /// The choices are definition CLAUSES ("the control center that contains
  /// genetic material"), not the whole source sentences they came from.
  /// Using whole sentences made every correct answer start with the very
  /// term the question named - "What is Nucleus?" answered by "Nucleus is
  /// the control center..." - so a student could pick the right one purely
  /// by matching the first word, without knowing any biology. Clauses
  /// force an actual recall of which definition belongs to which term.
  static GeneratedQuestion? _buildDefinitionQuestion(
      String subject,
      String definition,
      String sentence,
      List<String> termPool,
      Map<String, String> termDefinitions,
      ) {
    // "The mitochondria" -> "mitochondria": reads correctly in a question
    // ("What is mitochondria?" not "What is The mitochondria?") and is the
    // form the term pool holds, so it's also what self-exclusion needs.
    final term = GrammarValidator.stripLeadingArticle(subject);
    if (definition.isEmpty) return null;

    // A definition that repeats its own term still gives the answer away.
    if (definition.toLowerCase().contains(term.toLowerCase())) return null;

    // Only terms that have a definition clause of their own can serve as a
    // distractor now - a bare term alongside three clauses would be its own
    // giveaway. Candidates are article-stripped first: the term pool holds
    // "The mitochondria" (sentences start with an article) while
    // termDefinitions is keyed on "mitochondria", so an unnormalized lookup
    // silently misses every such candidate. Normalizing also collapses
    // "The mitochondria"/"Mitochondria" into one entry, which is what stops
    // a term sneaking in as its own distractor.
    final candidatePool = <String>[];
    final seenKeys = <String>{term.toLowerCase()};
    for (final raw in _candidatePool(termPool, term)) {
      final candidate = GrammarValidator.stripLeadingArticle(raw);
      final key = candidate.toLowerCase();
      final clause = termDefinitions[key];
      // Identical definitions can't be told apart, so they'd make an
      // unanswerable question rather than a harder one.
      if (clause == null || clause == definition) continue;
      // A distractor that names the asked-about term is a tell in its own
      // right - it either baits or hints, depending on the student.
      if (clause.toLowerCase().contains(term.toLowerCase())) continue;
      if (seenKeys.add(key)) candidatePool.add(candidate);
    }
    final distractors = _pickDistractors(candidatePool, 3);
    if (distractors.length < 3) return null;

    final template =
        _definitionTemplates[_stableIndex(term, _definitionTemplates.length)];

    return GeneratedQuestion(
      questionText: template.replaceAll('{t}', term),
      correctAnswer: definition,
      choices: formatChoices(
        correctAnswer: definition,
        distractorTerms: distractors,
        isDefinitionStyle: true,
        termDefinitions: termDefinitions,
      ),
      sourceSentence: sentence,
      compareTerm: term,
      distractorCandidates: candidatePool,
      isDefinitionStyle: true,
      termDefinitions: termDefinitions,
    );
  }

  static GeneratedQuestion? _buildFillBlankQuestion(
      String term,
      String sentence,
      List<String> termPool,
      ) {
    final candidatePool = _candidatePool(termPool, term);
    final distractors = _pickDistractors(candidatePool, 3);
    if (distractors.length < 3) return null;

    final blanked = sentence.replaceFirst(term, '_____');
    final template =
        _blankTemplates[_stableIndex(term, _blankTemplates.length)];
    return GeneratedQuestion(
      questionText: template.replaceAll('{s}', blanked),
      correctAnswer: term,
      choices: formatChoices(
        correctAnswer: term,
        distractorTerms: distractors,
        isDefinitionStyle: false,
      ),
      sourceSentence: sentence,
      compareTerm: term,
      distractorCandidates: candidatePool,
      isDefinitionStyle: false,
      termDefinitions: const {},
    );
  }

  /// Builds the final shuffled 4-choice list for a question. Shared by the
  /// initial random-pick generation path (below) and the embedding-based
  /// distractor re-ranking done later in ContentImportService, so both
  /// paths format choices identically.
  ///
  /// For a definition-style question every choice is a definition clause,
  /// looked up from [termDefinitions] - so all four read alike and none of
  /// them names the term being asked about. _buildDefinitionQuestion only
  /// ever offers candidates that have such a clause, so the `?? d`
  /// fallback to a bare term is unreachable in practice; it exists so a
  /// caller passing an unfiltered pool degrades to a plain term rather
  /// than crashing.
  static List<String> formatChoices({
    required String correctAnswer,
    required List<String> distractorTerms,
    required bool isDefinitionStyle,
    Map<String, String> termDefinitions = const {},
  }) {
    final choices = [
      correctAnswer,
      for (final d in distractorTerms)
        isDefinitionStyle ? (termDefinitions[d.toLowerCase()] ?? d) : d,
    ]..shuffle(Random());
    return choices;
  }

  /// All other same-document terms available as a distractor for
  /// [exclude], deduplicated - the full pool a later embedding-based
  /// re-ranking pass can choose from (see distractorCandidates above).
  static List<String> _candidatePool(List<String> pool, String exclude) {
    return pool.where((t) => t.toLowerCase() != exclude.toLowerCase()).toSet().toList();
  }

  /// Picks [n] distractors from [candidatePool]. Definition-style callers
  /// pre-filter the pool to terms that actually have a definition clause
  /// (see _buildDefinitionQuestion), so this stays a plain random draw.
  static List<String> _pickDistractors(List<String> candidatePool, int n) {
    final shuffled = List<String>.of(candidatePool)..shuffle(Random());
    return shuffled.take(n).toList();
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
    'compareTerm': g.compareTerm,
    'distractorCandidates': g.distractorCandidates,
    'isDefinitionStyle': g.isDefinitionStyle,
    'termDefinitions': g.termDefinitions,
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
