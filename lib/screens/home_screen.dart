import 'package:flutter/material.dart';

import '../widgets/dna_helix_background.dart';
import 'module_select_screen.dart';

/// Student-facing entry point. There is no admin/login role in this app -
/// any student can import material and play directly.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  void _openGame(BuildContext context, String gameMode) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ModuleSelectScreen(gameMode: gameMode),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Image(
              image: AssetImage('assets/image.png'),
              width: 32,
              height: 32,
            ),
            SizedBox(width: 8),
            Text('Gen Bio Offline Review'),
          ],
        ),
      ),
      body: Stack(
        children: [
          const Positioned.fill(child: DnaHelixBackground()),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                    '"The Effect of BioQuest Reviewing Offline App on the '
                    'Formative Assessment Score of STEM Students in Biology"',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 32),
                  _GameButton(
                    label: 'Timed Quiz',
                    icon: Icons.timer,
                    onTap: () => _openGame(context, 'quiz'),
                  ),
                  const SizedBox(height: 16),
                  _GameButton(
                    label: 'Matching Game',
                    icon: Icons.compare_arrows,
                    onTap: () => _openGame(context, 'matching'),
                  ),
                  const SizedBox(height: 16),
                  _GameButton(
                    label: 'Survival Mode',
                    icon: Icons.favorite,
                    onTap: () => _openGame(context, 'survival'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GameButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  const _GameButton({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: FilledButton.icon(
        onPressed: onTap,
        icon: Icon(icon),
        label: Text(label, style: const TextStyle(fontSize: 16)),
      ),
    );
  }
}