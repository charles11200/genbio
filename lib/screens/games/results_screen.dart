import 'package:flutter/material.dart';

/// Shared post-game summary for all three modes. The game screen has
/// already saved the Attempt row before navigating here - this widget
/// only displays it and offers a way back to the Home screen.
class ResultsScreen extends StatelessWidget {
  final String gameMode; // 'quiz' | 'matching' | 'survival'
  final int moduleId;
  final int score;
  final int totalItems;

  /// Survival-only: true if the game ended because the question pool ran
  /// out (a completion/win state), false if lives reached 0. Ignored by
  /// Quiz/Matching, which always finish by exhausting their question set.
  final bool? completed;

  const ResultsScreen({
    super.key,
    required this.gameMode,
    required this.moduleId,
    required this.score,
    required this.totalItems,
    this.completed,
  });

  String get _headline {
    switch (gameMode) {
      case 'survival':
        return completed == true ? 'Pool Cleared!' : 'Game Over';
      case 'matching':
        return 'Matching Complete';
      default:
        return 'Quiz Complete';
    }
  }

  @override
  Widget build(BuildContext context) {
    final percent = totalItems == 0 ? 0.0 : (score / totalItems) * 100;
    return Scaffold(
      appBar: AppBar(title: const Text('Results')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_headline, style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 16),
              Text('$score / $totalItems correct', style: const TextStyle(fontSize: 20)),
              const SizedBox(height: 8),
              Text(
                '${percent.toStringAsFixed(1)}%',
                style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 32),
              FilledButton(
                onPressed: () =>
                    Navigator.of(context).popUntil((route) => route.isFirst),
                child: const Text('Back to Home'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}