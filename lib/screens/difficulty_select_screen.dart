import 'package:flutter/material.dart';

import '../data/models.dart';
import '../services/difficulty.dart';
import '../widgets/dna_helix_background.dart';

/// Full-screen difficulty picker. Used to be a plain SimpleDialog, but a
/// dialog is too small to meaningfully show a designed background, and
/// difficulty is an important-enough choice (it sizes every timer in the
/// chosen game) to deserve its own screen rather than a quick popup.
/// Reuses DnaHelixBackground (already the Home screen's backdrop) rather
/// than inventing a second background treatment.
class DifficultySelectScreen extends StatelessWidget {
  final Module module;
  final String gameMode; // 'quiz' | 'matching' | 'survival'

  const DifficultySelectScreen({
    super.key,
    required this.module,
    required this.gameMode,
  });

  String get _gameModeLabel => switch (gameMode) {
        'matching' => 'Matching Game',
        'survival' => 'Survival Mode',
        _ => 'Timed Quiz',
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(module.title)),
      body: Stack(
        children: [
          const Positioned.fill(
            child: DnaHelixBackground(strandColor: Color(0xFF388E3C)),
          ),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.10),
                        blurRadius: 24,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Select Difficulty Level',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Choose how challenging this $_gameModeLabel round '
                        'should be.',
                        style: TextStyle(color: Colors.grey.shade600),
                      ),
                      const SizedBox(height: 20),
                      GridView.count(
                        crossAxisCount: 2,
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 12,
                        childAspectRatio: 1.05,
                        children: [
                          for (final d in Difficulty.values)
                            _DifficultyCard(
                              difficulty: d,
                              gameMode: gameMode,
                              onTap: () => Navigator.of(context).pop(d),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Biology-themed visual progression instead of the generic seedling /
/// flexing-figure / trophy icon set this design was adapted from: simple
/// life -> genetics -> cognition -> mastery. Color keeps the standard
/// green-to-red difficulty convention so it still reads correctly at a
/// glance despite the icon change.
class _DifficultyStyle {
  final IconData icon;
  final Color color;
  const _DifficultyStyle(this.icon, this.color);
}

const _difficultyStyles = {
  Difficulty.easy: _DifficultyStyle(Icons.eco, Color(0xFF43A047)),
  Difficulty.medium: _DifficultyStyle(Icons.biotech, Color(0xFFFB8C00)),
  Difficulty.hard: _DifficultyStyle(Icons.psychology, Color(0xFFE64A19)),
  Difficulty.veryHard: _DifficultyStyle(Icons.emoji_events, Color(0xFFD32F2F)),
};

class _DifficultyCard extends StatelessWidget {
  final Difficulty difficulty;
  final String gameMode;
  final VoidCallback onTap;

  const _DifficultyCard({
    required this.difficulty,
    required this.gameMode,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final style = _difficultyStyles[difficulty]!;
    final seconds = gameMode == 'matching'
        ? difficulty.secondsPerMatchingRound
        : difficulty.secondsPerQuestion;
    final timeLabel =
        gameMode == 'matching' ? '${seconds}s / round' : '${seconds}s / question';

    return Material(
      color: style.color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(style.icon, size: 36, color: style.color),
              const SizedBox(height: 10),
              Text(
                difficulty.label,
                style: TextStyle(
                  color: style.color,
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                timeLabel,
                style: TextStyle(
                  color: style.color.withValues(alpha: 0.8),
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
