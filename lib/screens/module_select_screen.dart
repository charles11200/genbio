import 'package:flutter/material.dart';

import '../data/database_helper.dart';
import '../data/models.dart';
import '../services/difficulty.dart';
import 'games/matching_game_screen.dart';
import 'games/quiz_game_screen.dart';
import 'games/survival_game_screen.dart';

/// Student picks which imported Module to play [gameMode] on, then a
/// Difficulty, then lands directly in the game screen. No login/admin -
/// any student sees every module imported on this device.
class ModuleSelectScreen extends StatefulWidget {
  final String gameMode; // 'quiz' | 'matching' | 'survival'
  const ModuleSelectScreen({super.key, required this.gameMode});

  @override
  State<ModuleSelectScreen> createState() => _ModuleSelectScreenState();
}

class _ModuleSelectScreenState extends State<ModuleSelectScreen> {
  late Future<List<Module>> _modules;

  @override
  void initState() {
    super.initState();
    _modules = DatabaseHelper.instance.getAllModules();
  }

  Future<void> _pickDifficultyAndStart(Module module) async {
    final difficulty = await showDialog<Difficulty>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Choose difficulty'),
        children: [
          for (final d in Difficulty.values)
            SimpleDialogOption(
              onPressed: () => Navigator.of(context).pop(d),
              child: Text(d.label),
            ),
        ],
      ),
    );
    if (difficulty == null || !mounted) return;
    _startGame(module.id!, difficulty);
  }

  void _startGame(int moduleId, Difficulty difficulty) {
    final Widget screen = switch (widget.gameMode) {
      'matching' =>
        MatchingGameScreen(moduleId: moduleId, difficulty: difficulty),
      'survival' =>
        SurvivalGameScreen(moduleId: moduleId, difficulty: difficulty),
      _ => QuizGameScreen(moduleId: moduleId, difficulty: difficulty),
    };
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Choose a Module')),
      body: FutureBuilder<List<Module>>(
        future: _modules,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final modules = snapshot.data!;
          if (modules.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'No modules yet. Import a PDF, PPTX, or pasted notes to '
                  'create one.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return ListView.builder(
            itemCount: modules.length,
            itemBuilder: (context, i) {
              final m = modules[i];
              return ListTile(
                title: Text(m.title),
                subtitle: Text(m.description),
                onTap: () => _pickDifficultyAndStart(m),
              );
            },
          );
        },
      ),
    );
  }
}