/// Offline grammar/quality validation for auto-generated questions.
///
/// This is deliberately NOT a general English dictionary lookup. A general
/// wordlist would flag legitimate Biology vocabulary (mitochondria,
/// homeostasis, chloroplast, osmoregulation...) as "not a real word" and
/// reject exactly the content this app exists to quiz on.
///
/// Instead, EnglishGrammarDictionary is a small, hand-curated, closed set
/// of core English words - function words (articles, linking/auxiliary
/// verbs) plus a common science-text action-verb list - that a real
/// grammatical sentence overwhelmingly contains, regardless of subject
/// matter. GrammarValidator uses those closed sets to reject things that
/// aren't real sentences (slide headers, table rows, page numbers, bullet
/// fragments) even when they slip past a simple word-count filter. Fully
/// offline, fully deterministic, and explainable rule-by-rule - no model,
/// no training data.
class EnglishGrammarDictionary {
  /// Copula/auxiliary verbs - the original, narrowest signal of "this is
  /// a sentence" ("X is Y", "X has Y").
  static const Set<String> linkingVerbs = {
    'is', 'are', 'was', 'were', 'be', 'been', 'being',
    'has', 'have', 'had',
    'does', 'do', 'did',
    'can', 'could', 'will', 'would', 'shall', 'should', 'may', 'might', 'must',
  };

  /// Base forms of common science-text action verbs. Not every sentence
  /// uses a linking verb - "Mitochondria produce energy" is just as valid
  /// as "Mitochondria is the powerhouse" - so this covers that case too.
  /// Matched via GrammarValidator's suffix stemmer, so one base form here
  /// ("produce") also recognizes "produces"/"produced"/"producing".
  static const Set<String> actionVerbs = {
    'produce', 'contain', 'consist', 'occur', 'function', 'convert',
    'regulate', 'control', 'help', 'allow', 'enable', 'form', 'create',
    'provide', 'act', 'serve', 'move', 'break', 'change', 'require', 'use',
    'release', 'absorb', 'respond', 'maintain', 'protect', 'store',
    'transport', 'generate', 'synthesize', 'reproduce', 'digest', 'secrete',
    'filter', 'pump', 'divide', 'replicate', 'transmit', 'receive',
    'connect', 'support', 'cover', 'surround', 'contract', 'expand',
    'circulate', 'excrete', 'grow', 'develop', 'carry', 'send', 'build',
    'work', 'need', 'consume', 'process', 'trigger', 'stimulate', 'inhibit',
    'attach', 'detect', 'sense',
  };

  /// Words that mark a line as document furniture - headers, captions,
  /// navigation chrome - rather than reviewable content, even when the
  /// line happens to contain a verb (e.g. "Chapter 3 Overview: What Is a
  /// Cell?").
  static const Set<String> documentFurniture = {
    'chapter', 'section', 'page', 'figure', 'table', 'appendix',
    'reference', 'references', 'bibliography', 'objective', 'objectives',
    'outline', 'agenda', 'summary', 'overview', 'introduction',
    'conclusion', 'quiz', 'activity', 'worksheet', 'handout', 'module',
    'lesson', 'unit', 'topic', 'assignment', 'exercise', 'copyright',
    'slide',
  };

  /// Subjects/terms that must never stand alone as a quiz answer - they
  /// carry no content on their own, regardless of subject matter.
  static const Set<String> meaninglessSubjects = {
    'it', 'this', 'that', 'these', 'those', 'there', 'such',
    'also', 'however', 'therefore', 'thus', 'meanwhile', 'furthermore',
    'moreover', 'additionally', 'here', 'now', 'then', 'today', 'overall',
    'the', 'a', 'an', 'and', 'or', 'but',
    'he', 'she', 'they', 'we', 'you', 'its', 'their', 'our', 'his', 'her',
    'some', 'many', 'few', 'several', 'various', 'certain', 'other',
    'others', 'each', 'every', 'any', 'all', 'both',
  };

  static bool containsAny(Iterable<String> words, Set<String> dict) =>
      words.any((w) => dict.contains(w.toLowerCase()));
}

class GrammarValidator {
  static final RegExp _wordSplit = RegExp(r'[^\w]+');
  static final RegExp _alphaOnly = RegExp(r'^[A-Za-z]+$');
  static final RegExp _hasLetter = RegExp(r'[A-Za-z]');
  static final RegExp _sibilantEs = RegExp(r'(ch|sh|ss|x|z|s)es$');

  /// Strips common English verb inflection suffixes so a single dictionary
  /// entry ("produce") also matches "produces"/"produced"/"producing".
  /// Simple, deterministic stemming - a fixed set of suffix-stripping
  /// rules, not a trained model.
  static String _stem(String word) {
    final w = word.toLowerCase();
    if (w.endsWith('ies') && w.length > 4) {
      return '${w.substring(0, w.length - 3)}y';
    }
    if (w.endsWith('ing') && w.length > 5) return w.substring(0, w.length - 3);
    if (w.endsWith('ed') && w.length > 4) return w.substring(0, w.length - 2);
    // Sibilant-ending stems add -es (box->boxes, watch->watches); every
    // other verb just adds -s (produce->produces), so only strip the
    // trailing 's' for those - stripping 'es' would wrongly turn
    // "produces" into "produc" instead of "produce".
    if (w.endsWith('es') && w.length > 4 && _sibilantEs.hasMatch(w)) {
      return w.substring(0, w.length - 2);
    }
    if (w.endsWith('s') && w.length > 3) return w.substring(0, w.length - 1);
    return w;
  }

  static bool _isVerb(String word) {
    final lower = word.toLowerCase();
    return EnglishGrammarDictionary.linkingVerbs.contains(lower) ||
        EnglishGrammarDictionary.actionVerbs.contains(_stem(lower));
  }

  /// A sentence is only accepted as quiz material if it looks like an
  /// actual grammatical sentence, not a page header, bullet fragment, or
  /// OCR artifact that slipped past the word-count filter.
  static bool isPlausibleSentence(String sentence) {
    final words = sentence
        .split(_wordSplit)
        .where((w) => w.isNotEmpty)
        .toList();
    if (words.length < 6) return false;

    // A real sentence has a verb - either a linking/auxiliary verb
    // ("is"/"has") or a common action verb ("produce", "regulate"...).
    if (!words.any(_isVerb)) return false;

    // Document furniture (headers/captions) sometimes accidentally
    // contains a verb - reject if furniture words dominate the line.
    final furnitureCount = words
        .where((w) =>
            EnglishGrammarDictionary.documentFurniture.contains(w.toLowerCase()))
        .length;
    if (furnitureCount / words.length > 0.25) return false;

    // Reject lines that are mostly digits/symbols (tables, figure
    // captions, page numbers) - a real sentence is overwhelmingly
    // alphabetic.
    final alphaWords = words.where((w) => _alphaOnly.hasMatch(w));
    if (alphaWords.length / words.length < 0.7) return false;

    // Reject ALL-CAPS lines (slide titles / section headers), which are
    // not meant to be read as prose.
    final letterWords = words.where((w) => _hasLetter.hasMatch(w));
    if (letterWords.isNotEmpty) {
      final allCapsCount =
          letterWords.where((w) => w == w.toUpperCase()).length;
      if (allCapsCount / letterWords.length > 0.6) return false;
    }

    return true;
  }

  static final RegExp _leadingArticle =
      RegExp(r'^(the|a|an)\s+', caseSensitive: false);

  /// Strips a leading article ("The"/"A"/"An") so a meaningfulness check
  /// (or a displayed term/definition) looks at the actual content word -
  /// "The mitochondria" must be judged on "mitochondria", not rejected
  /// just because sentences naturally start with "The".
  static String stripLeadingArticle(String text) {
    final trimmed = text.trim();
    final match = _leadingArticle.firstMatch(trimmed);
    return match == null ? trimmed : trimmed.substring(match.end).trim();
  }

  /// A subject/term is only usable as a quiz answer if it's a real content
  /// word, not a pronoun/filler that carries no subject-matter meaning.
  static bool isMeaningfulSubject(String subject) {
    final core = stripLeadingArticle(subject);
    if (core.length < 3) return false;
    final firstWord = core.split(RegExp(r'\s+')).first.toLowerCase();
    return !EnglishGrammarDictionary.meaninglessSubjects.contains(firstWord);
  }

  /// The term-extraction regex sometimes captures a trailing verb as part
  /// of the phrase ("Mitochondria produce"). Trimming it keeps
  /// fill-in-the-blank answers and distractor text clean - repeatedly
  /// strips trailing linking/action-verb words until none remain.
  static String trimTrailingVerb(String term) {
    final words = term.trim().split(RegExp(r'\s+'));
    while (words.length > 1 && _isVerb(words.last)) {
      words.removeLast();
    }
    return words.join(' ');
  }
}
