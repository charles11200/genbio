import 'package:flutter/material.dart';

import '../data/database_helper.dart';
import '../data/models.dart';
import '../widgets/dna_helix_background.dart';

const _darkGreen = Color(0xFF2E7D32);
const _accentGreen = Color(0xFF388E3C);

/// Shown immediately after ContentImportService generates a batch of
/// auto-generated questions for a new Module. Every row starts out
/// verified=false (see content_import_service.dart), so none of them are
/// actually playable yet (see DatabaseHelper.getQuestionsWithProgress)
/// until a student edits/removes anything wrong and confirms.
///
/// There's no separate "resume review later" entry point, so *every* way
/// of leaving this screen - the Confirm button, the back arrow, the
/// system back gesture - marks whatever remains as verified. A
/// half-finished review still leaves a playable module instead of an
/// orphaned unplayable one.
class ReviewQuestionsScreen extends StatefulWidget {
  final int moduleId;
  const ReviewQuestionsScreen({super.key, required this.moduleId});

  @override
  State<ReviewQuestionsScreen> createState() => _ReviewQuestionsScreenState();
}

class _ReviewQuestionsScreenState extends State<ReviewQuestionsScreen> {
  late Future<List<Question>> _questionsFuture;
  bool _exiting = false;

  @override
  void initState() {
    super.initState();
    _questionsFuture =
        DatabaseHelper.instance.getQuestionsByModule(widget.moduleId);
  }

  void _reload() {
    setState(() {
      _questionsFuture =
          DatabaseHelper.instance.getQuestionsByModule(widget.moduleId);
    });
  }

  Future<void> _confirmAndExit() async {
    if (_exiting) return;
    _exiting = true;
    await DatabaseHelper.instance.verifyAllQuestions(widget.moduleId);
    if (mounted) Navigator.of(context).pop(true);
  }

  Future<void> _delete(Question q) async {
    await DatabaseHelper.instance.deleteQuestion(q.id!);
    if (mounted) _reload();
  }

  Future<void> _edit(Question q) async {
    final updated = await showDialog<Question>(
      context: context,
      builder: (_) => _EditQuestionDialog(question: q),
    );
    if (updated == null) return;
    await DatabaseHelper.instance.updateQuestion(updated);
    if (mounted) _reload();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _confirmAndExit();
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Review Questions'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: _confirmAndExit,
          ),
        ),
        body: Stack(
          children: [
            const Positioned.fill(
              child: DnaHelixBackground(strandColor: _accentGreen),
            ),
            SafeArea(
              child: FutureBuilder<List<Question>>(
                future: _questionsFuture,
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return const Center(
                      child: CircularProgressIndicator(color: _accentGreen),
                    );
                  }
                  final questions = snapshot.data!;
                  return Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                        child: Text(
                          questions.isEmpty
                              ? 'No questions left. Go back and import '
                                  'different material.'
                              : '${questions.length} question'
                                  '${questions.length == 1 ? '' : 's'} '
                                  'generated. Check each one - edit or '
                                  'remove anything that doesn\'t look '
                                  'right before you start reviewing.',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                      Expanded(
                        child: ListView.separated(
                          padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                          itemCount: questions.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 12),
                          itemBuilder: (context, i) => _QuestionCard(
                            question: questions[i],
                            onEdit: () => _edit(questions[i]),
                            onDelete: () => _delete(questions[i]),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                        child: SizedBox(
                          width: double.infinity,
                          child: FilledButton(
                            onPressed: _confirmAndExit,
                            style: FilledButton.styleFrom(
                              backgroundColor: _darkGreen,
                              padding: const EdgeInsets.symmetric(
                                vertical: 14,
                              ),
                            ),
                            child: Text(
                              'Confirm Reviewer (${questions.length})',
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuestionCard extends StatelessWidget {
  final Question question;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _QuestionCard({
    required this.question,
    required this.onEdit,
    required this.onDelete,
  });

  bool get _isMcq => question.questionType == 'mcq';

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      elevation: 2,
      shadowColor: Colors.black.withValues(alpha: 0.12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  _isMcq ? Icons.quiz_outlined : Icons.compare_arrows,
                  color: _accentGreen,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    question.questionText,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.edit, size: 20),
                  tooltip: 'Edit',
                  onPressed: onEdit,
                  visualDensity: VisualDensity.compact,
                ),
                IconButton(
                  icon: Icon(Icons.delete_outline,
                      size: 20, color: Colors.red.shade400),
                  tooltip: 'Remove',
                  onPressed: onDelete,
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            const SizedBox(height: 6),
            if (_isMcq)
              ...question.choices.map((c) => _ChoiceLine(
                    text: c,
                    isCorrect: c == question.correctAnswer,
                  ))
            else
              _ChoiceLine(text: question.correctAnswer, isCorrect: true),
          ],
        ),
      ),
    );
  }
}

class _ChoiceLine extends StatelessWidget {
  final String text;
  final bool isCorrect;
  const _ChoiceLine({required this.text, required this.isCorrect});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 2, left: 28),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            isCorrect ? Icons.check_circle : Icons.circle_outlined,
            size: 14,
            color: isCorrect ? _darkGreen : Colors.grey.shade400,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 13,
                color: isCorrect ? _darkGreen : Colors.grey.shade700,
                fontWeight: isCorrect ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Edits a single question's text in place. For an 'mcq' row, the 4
/// choices are edited alongside a radio pick for which one is correct -
/// rather than a free-text "correct answer" field - so correctAnswer is
/// always structurally guaranteed to exactly match one of the 4 choice
/// strings on save (game screens judge correctness by exact string
/// equality - see quiz_game_screen.dart). A 'pair' row has no such
/// invariant to protect (no choices array), so it's just two fields.
class _EditQuestionDialog extends StatefulWidget {
  final Question question;
  const _EditQuestionDialog({required this.question});

  @override
  State<_EditQuestionDialog> createState() => _EditQuestionDialogState();
}

class _EditQuestionDialogState extends State<_EditQuestionDialog> {
  late final TextEditingController _questionController;
  late final List<TextEditingController> _choiceControllers;
  late int _correctIndex;

  bool get _isMcq => widget.question.questionType == 'mcq';

  @override
  void initState() {
    super.initState();
    _questionController =
        TextEditingController(text: widget.question.questionText);
    if (_isMcq) {
      _choiceControllers = widget.question.choices
          .map((c) => TextEditingController(text: c))
          .toList();
      final i = widget.question.choices.indexOf(widget.question.correctAnswer);
      _correctIndex = i < 0 ? 0 : i;
    } else {
      _choiceControllers = [
        TextEditingController(text: widget.question.correctAnswer),
      ];
      _correctIndex = 0;
    }
  }

  @override
  void dispose() {
    _questionController.dispose();
    for (final c in _choiceControllers) {
      c.dispose();
    }
    super.dispose();
  }

  void _save() {
    final choiceTexts =
        _choiceControllers.map((c) => c.text.trim()).toList();
    final updated = Question(
      id: widget.question.id,
      moduleId: widget.question.moduleId,
      questionText: _questionController.text.trim(),
      correctAnswer: choiceTexts[_correctIndex],
      choiceA: _isMcq ? choiceTexts[0] : null,
      choiceB: _isMcq ? choiceTexts[1] : null,
      choiceC: _isMcq ? choiceTexts[2] : null,
      choiceD: _isMcq ? choiceTexts[3] : null,
      source: widget.question.source,
      difficulty: widget.question.difficulty,
      theory: widget.question.theory,
      gameMode: widget.question.gameMode,
      questionType: widget.question.questionType,
      verified: false,
    );
    Navigator.of(context).pop(updated);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_isMcq ? 'Edit question' : 'Edit pair'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _questionController,
              maxLines: null,
              decoration: InputDecoration(
                labelText: _isMcq ? 'Question' : 'Term',
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            if (_isMcq)
              Text(
                'Choices (select the correct one)',
                style: Theme.of(context).textTheme.labelMedium,
              )
            else
              Text('Definition', style: Theme.of(context).textTheme.labelMedium),
            const SizedBox(height: 4),
            if (_isMcq)
              RadioGroup<int>(
                groupValue: _correctIndex,
                onChanged: (v) => setState(() => _correctIndex = v!),
                child: Column(
                  children: [
                    for (var i = 0; i < _choiceControllers.length; i++)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Radio<int>(value: i),
                            Expanded(
                              child: TextField(
                                controller: _choiceControllers[i],
                                maxLines: null,
                                decoration: const InputDecoration(
                                  border: OutlineInputBorder(),
                                  isDense: true,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: TextField(
                  controller: _choiceControllers[0],
                  maxLines: null,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}
