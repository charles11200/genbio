import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../data/database_helper.dart';
import '../data/models.dart';
import 'pdf_extractor.dart';
import 'pptx_extractor.dart';
import 'question_generator.dart';
import 'term_embedding_service.dart';

/// Thrown when imported material can't be turned into a playable Module -
/// message is meant to be shown to the student as-is.
class ContentImportException implements Exception {
  final String message;
  ContentImportException(this.message);

  @override
  String toString() => message;
}

/// Everything generated from one import, held in memory between the two
/// halves of the flow: [ContentImportService.prepare] does all the
/// expensive work (extract -> generate -> rank distractors) and reports
/// how many questions the material can actually support, then the student
/// picks how many they want and [ContentImportService.save] persists that
/// many. Nothing is written to the database until save().
class PreparedImport {
  final String rawText;
  final List<Map<String, dynamic>> mcqMaps;
  final List<Map<String, dynamic>> pairMaps;

  PreparedImport({
    required this.rawText,
    required this.mcqMaps,
    required this.pairMaps,
  });

  /// The real ceiling for this material - how many MCQ questions the
  /// generator could actually build from it, not a guess or a fixed
  /// number. This is what the count picker's maximum is bound to.
  int get maxQuestions => mcqMaps.length;

  /// Matching mode's pairs are generated separately (term/definition, no
  /// distractors) and aren't affected by the MCQ count the student picks.
  int get pairCount => pairMaps.length;
}

/// Turns a PDF, PPTX, or block of pasted notes into a new playable Module:
/// extract text -> generate questions (rule-based, offline) -> persist.
/// No network calls, no server, no login/admin step - any student can run
/// this directly. Extraction and generation both run on a background
/// isolate via compute() so a large file doesn't freeze the UI thread.
class ContentImportService {
  /// Survival mode is lives-based and ends when the pool runs out, so a
  /// short pool makes the mode unplayable - it needs at least this many
  /// questions to be a real round. Quiz and Survival both draw from the
  /// full MCQ pool (see DatabaseHelper.getQuestionsWithProgress), so this
  /// is simply a floor on the MCQ count a student is allowed to pick.
  static const int minSurvivalQuestions = 10;

  /// Generates everything the material can support, without saving. The
  /// expensive half of the import - the caller then asks the student how
  /// many of [PreparedImport.maxQuestions] they actually want, and passes
  /// that to [save].
  static Future<PreparedImport> prepare({
    String? filePath,
    String? pastedNotes,
  }) async {
    final rawText = await _extractRawText(
      filePath: filePath,
      pastedNotes: pastedNotes,
    );

    final mcqMaps = await compute(generateQuestionsIsolate, rawText);
    final pairMaps = await compute(generateTermDefinitionPairsIsolate, rawText);

    if (mcqMaps.isEmpty && pairMaps.isEmpty) {
      throw ContentImportException(
        'Could not generate any questions from this material. '
        'Try a longer file with more complete sentences.',
      );
    }

    // Re-rank each MCQ's distractors by semantic similarity using the
    // on-device Biology term-embedding model, in place of the plain random
    // pick compute() already filled in. Runs here on the main isolate
    // (TFLite asset loading needs Flutter's plugin bindings, which a
    // compute()-spawned isolate doesn't have - see TermEmbeddingService)
    // rather than inside generation itself. Falls back to leaving a
    // question's original random distractors untouched whenever the model
    // doesn't recognize enough of that question's vocabulary, so unusual
    // terms degrade gracefully instead of blocking import.
    for (final g in mcqMaps) {
      await _tryImproveDistractors(g);
    }

    return PreparedImport(
      rawText: rawText,
      mcqMaps: mcqMaps,
      pairMaps: pairMaps,
    );
  }

  /// Persists [prepared] as a new Module, keeping only the first
  /// [questionCount] MCQ questions. Every matching pair is kept
  /// regardless - the count picker governs MCQ questions (Quiz/Survival)
  /// only, since Matching's rounds are built from pairs instead.
  static Future<int> save({
    required PreparedImport prepared,
    required String moduleTitle,
    required int questionCount,
  }) async {
    final keep = questionCount.clamp(0, prepared.maxQuestions);

    final db = DatabaseHelper.instance;
    final moduleId = await db.insertModule(Module(
      title: moduleTitle,
      description: 'Student-generated reviewer from imported material',
      reviewContent: prepared.rawText,
    ));

    final questions = <Question>[
      for (final g in prepared.mcqMaps.take(keep))
        _toMcqQuestion(g, moduleId),
      for (final pairMap in prepared.pairMaps) _toPairQuestion(pairMap, moduleId),
    ];

    await db.insertQuestions(questions);
    return moduleId;
  }

  /// Tries to replace [g]'s random-picked distractors with the 3 most
  /// semantically similar candidates from its full same-document term
  /// pool. Leaves [g] untouched if the embedding model doesn't recognize
  /// enough of the relevant vocabulary to produce 3 ranked candidates.
  static Future<void> _tryImproveDistractors(Map<String, dynamic> g) async {
    final compareTerm = g['compareTerm'] as String;
    final candidates = (g['distractorCandidates'] as List).cast<String>();
    final ranked = await TermEmbeddingService.instance.pickTopSimilar(
      compareTerm,
      candidates,
      3,
    );
    if (ranked.length < 3) return;

    g['choices'] = QuestionGenerator.formatChoices(
      correctAnswer: g['correctAnswer'] as String,
      distractorTerms: ranked,
      isDefinitionStyle: g['isDefinitionStyle'] as bool,
      termDefinitions: (g['termDefinitions'] as Map).cast<String, String>(),
    );
  }

  static Question _toMcqQuestion(Map<String, dynamic> g, int moduleId) {
    final choices = (g['choices'] as List).cast<String>();
    return Question(
      moduleId: moduleId,
      questionText: g['questionText'] as String,
      correctAnswer: g['correctAnswer'] as String,
      choiceA: choices[0],
      choiceB: choices[1],
      choiceC: choices[2],
      choiceD: choices[3],
      source: 'auto_generated',
      theory: g['sourceSentence'] as String,
      // Retrieval is by questionType, not gameMode (see
      // DatabaseHelper.getQuestionsWithProgress) - every MCQ is playable
      // in BOTH Quiz and Survival, so this is just a label now.
      gameMode: 'quiz',
      questionType: 'mcq',
      // Unreviewed until a student confirms/edits it in
      // ReviewQuestionsScreen - see getQuestionsWithProgress.
      verified: false,
    );
  }

  static Question _toPairQuestion(Map<String, dynamic> pair, int moduleId) {
    final term = pair['term'] as String;
    final definition = pair['definition'] as String;
    final sourceSentence = pair['sourceSentence'] as String;
    return Question(
      moduleId: moduleId,
      questionText: term,
      correctAnswer: definition,
      // Matching-mode rows are term/definition pairs, not 4-choice MCQ -
      // choiceA-D are genuinely absent (null), not empty placeholders.
      source: 'auto_generated',
      theory: sourceSentence,
      gameMode: 'matching',
      questionType: 'pair',
      // Unreviewed until a student confirms/edits it in
      // ReviewQuestionsScreen - see getQuestionsWithProgress.
      verified: false,
    );
  }

  static Future<String> _extractRawText({
    String? filePath,
    String? pastedNotes,
  }) async {
    final hasFile = filePath != null && filePath.isNotEmpty;
    final hasNotes = pastedNotes != null && pastedNotes.trim().isNotEmpty;

    if (!hasFile && !hasNotes) {
      throw ContentImportException(
        'Provide a PDF/PPTX file or paste some notes to generate a module from.',
      );
    }

    String text;
    if (hasFile) {
      if (!await File(filePath).exists()) {
        throw ContentImportException('Selected file was not found: $filePath');
      }
      switch (p.extension(filePath).toLowerCase()) {
        case '.pdf':
          text = await compute(PdfExtractor.extractText, filePath);
          break;
        case '.pptx':
          text = await compute(PptxExtractor.extractText, filePath);
          break;
        default:
          throw ContentImportException(
            'Unsupported file type. Only .pdf and .pptx are supported.',
          );
      }
    } else {
      text = pastedNotes!;
    }

    if (text.trim().isEmpty) {
      throw ContentImportException(
        'No readable text was found in the provided material.',
      );
    }
    return text;
  }
}
