import 'package:flutter/material.dart';

/// Small widgets shared by the MCQ-style game screens (Quiz, Survival) so
/// the answer-button visuals stay identical between them.
enum ChoiceVisualState { neutral, correct, wrong }

class ChoiceButton extends StatelessWidget {
  final String text;
  final VoidCallback onTap;
  final ChoiceVisualState state;

  const ChoiceButton({
    super.key,
    required this.text,
    required this.onTap,
    required this.state,
  });

  @override
  Widget build(BuildContext context) {
    Color? bg;
    switch (state) {
      case ChoiceVisualState.correct:
        bg = Colors.green.shade400;
        break;
      case ChoiceVisualState.wrong:
        bg = Colors.red.shade300;
        break;
      case ChoiceVisualState.neutral:
        bg = null;
        break;
    }
    return SizedBox(
      width: double.infinity,
      child: FilledButton(
        style: bg == null ? null : FilledButton.styleFrom(backgroundColor: bg),
        onPressed: onTap,
        child: Text(text, textAlign: TextAlign.center),
      ),
    );
  }
}

class EmptyPoolMessage extends StatelessWidget {
  final String gameMode;
  // Shown when given, since an empty pool now more often means "none at
  // this difficulty" than "none at all" - see
  // DatabaseHelper.getQuestionsWithProgress.
  final String? difficultyLabel;

  const EmptyPoolMessage({
    super.key,
    required this.gameMode,
    this.difficultyLabel,
  });

  @override
  Widget build(BuildContext context) {
    final message = difficultyLabel == null
        ? 'This module has no $gameMode questions yet. Import more '
            'material first.'
        : 'This module has no $difficultyLabel $gameMode questions yet. '
            'Try a different difficulty, or import more material.';
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(message, textAlign: TextAlign.center),
      ),
    );
  }
}