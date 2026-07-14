import 'package:flutter/material.dart';
import 'admin/admin_login_screen.dart';

/// Student-facing entry point. Admin access is deliberately NOT a big
/// visible button - a long-press on the title, per the code below - so
/// students don't casually wander into the question editor.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: GestureDetector(
          onLongPress: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AdminLoginScreen()),
            );
          },
          child: const Text('Gen Bio Offline Review'),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              'Biology Review Games',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 32),
            _GameButton(
              label: 'Timed Quiz',
              icon: Icons.timer,
              onTap: () {
                // TODO: Navigator.push to QuizGameScreen
              },
            ),
            const SizedBox(height: 16),
            _GameButton(
              label: 'Matching Game',
              icon: Icons.compare_arrows,
              onTap: () {
                // TODO: Navigator.push to MatchingGameScreen
              },
            ),
            const SizedBox(height: 16),
            _GameButton(
              label: 'Survival Mode',
              icon: Icons.favorite,
              onTap: () {
                // TODO: Navigator.push to SurvivalGameScreen
              },
            ),
          ],
        ),
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