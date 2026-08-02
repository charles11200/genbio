import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../data/database_helper.dart';
import '../data/models.dart';
import 'pdf_extractor.dart';
import 'pptx_extractor.dart';
import 'question_generator.dart';

/// Thrown when imported material can't be turned into a playable Module -
/// message is meant to be shown to the student as-is.
class ContentImportException implements Exception {
  final String message;
  ContentImportException(this.message);

  @override
  String toString() => message;
}

/// Turns a PDF, PPTX, or block of pasted notes into a new playable Module:
/// extract text -> generate questions (rule-based, offline) -> persist.
/// No network calls, no server, no login/admin step - any student can run
/// this directly. Extraction and generation both run on a background
/// isolate via compute() so a large file doesn't freeze the UI thread.
class ContentImportService {
  // Matching mode uses generateTermDefinitionPairs() (term/definition)
  // instead of MCQ.
  static const List<String> _mcqGameModes = ['quiz', 'survival'];

  static Future<int> importAndGenerate({
    String? filePath,
    String? pastedNotes,
    required String moduleTitle,
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

    final db = DatabaseHelper.instance;
    final moduleId = await db.insertModule(Module(
      title: moduleTitle,
      description: 'Student-generated reviewer from imported material',
      reviewContent: rawText,
    ));

    final questions = <Question>[
      for (var i = 0; i < mcqMaps.length; i++)
        _toMcqQuestion(
          mcqMaps[i],
          moduleId,
          _mcqGameModes[i % _mcqGameModes.length],
        ),
      for (final pairMap in pairMaps) _toPairQuestion(pairMap, moduleId),
    ];

    await db.insertQuestions(questions);
    return moduleId;
  }

  static Question _toMcqQuestion(
      Map<String, dynamic> g, int moduleId, String gameMode) {
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
      gameMode: gameMode,
      questionType: 'mcq',
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
