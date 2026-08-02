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
  const EmptyPoolMessage({super.key, required this.gameMode});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          'This module has no $gameMode questions yet. Import more '
          'material first.',
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}