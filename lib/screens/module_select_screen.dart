import 'package:flutter/material.dart';

import '../data/database_helper.dart';
import '../data/models.dart';
import '../services/difficulty.dart';
import '../widgets/dna_helix_background.dart';
import 'difficulty_select_screen.dart';
import 'games/matching_game_screen.dart';
import 'games/quiz_game_screen.dart';
import 'games/survival_game_screen.dart';
import 'import_content_screen.dart';

// Same palette as Home (_darkGreen) and the Difficulty picker (_accentGreen)
// - kept in sync across all three screens in this flow so the DNA-helix
// backdrop reads as one consistent visual language, not three ad-hoc ones.
const _darkGreen = Color(0xFF2E7D32);
const _accentGreen = Color(0xFF388E3C);

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

  Future<void> _openImport() async {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const ImportContentScreen()),
    );
    // initState() only fetches once, so a module created while this screen
    // was already open (either entry point below) needs an explicit
    // refresh to actually show up in the list. Refresh unconditionally
    // rather than gating on the popped value - re-querying is cheap, and
    // this keeps the list correct even if that value is ever unreliable.
    //
    // Block body, not `setState(() => _modules = ...)`: an arrow-bodied
    // callback evaluates to the assignment's value (Future<List<Module>>
    // here), so setState() would receive a callback that *returns* a
    // Future instead of void and throw "setState() callback argument
    // returned a Future" - silently aborting before the reassignment
    // happens. Same bug, same fix, as home_screen.dart's _openImport.
    if (mounted) {
      setState(() {
        _modules = DatabaseHelper.instance.getAllModules();
      });
    }
  }

  Future<void> _pickDifficultyAndStart(Module module) async {
    final difficulty = await Navigator.of(context).push<Difficulty>(
      MaterialPageRoute(
        builder: (_) => DifficultySelectScreen(
          module: module,
          gameMode: widget.gameMode,
        ),
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
      appBar: AppBar(
        title: const Text('Choose a Module'),
        actions: [
          IconButton(
            tooltip: 'Import new material',
            icon: const Icon(Icons.upload_file),
            onPressed: _openImport,
          ),
        ],
      ),
      body: Stack(
        children: [
          const Positioned.fill(
            child: DnaHelixBackground(strandColor: _accentGreen),
          ),
          SafeArea(
            child: FutureBuilder<List<Module>>(
              future: _modules,
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(
                    child: CircularProgressIndicator(color: _accentGreen),
                  );
                }
                final modules = snapshot.data!;
                if (modules.isEmpty) {
                  return _EmptyState(onImport: _openImport);
                }
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
                  itemCount: modules.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, i) {
                    final m = modules[i];
                    return _ModuleCard(
                      module: m,
                      onTap: () => _pickDifficultyAndStart(m),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// One imported Module, styled like a small reviewer "book" rather than a
/// plain text row - gives each module the same card-and-icon treatment as
/// the Difficulty picker's cards, instead of a bare ListTile.
class _ModuleCard extends StatelessWidget {
  final Module module;
  final VoidCallback onTap;

  const _ModuleCard({required this.module, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      elevation: 3,
      shadowColor: Colors.black.withValues(alpha: 0.15),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: _accentGreen.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.menu_book, color: _darkGreen),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      module.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      module.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              const Icon(Icons.chevron_right, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }
}

/// Shown instead of a bare "no modules yet" text + button when the student
/// has nothing imported - a floating card over the DNA background, same
/// visual weight as the Difficulty picker's card, instead of looking like
/// an error state.
class _EmptyState extends StatelessWidget {
  final VoidCallback onImport;
  const _EmptyState({required this.onImport});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Container(
          padding: const EdgeInsets.all(28),
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
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: _accentGreen.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.science, size: 32, color: _darkGreen),
              ),
              const SizedBox(height: 16),
              const Text(
                'No modules yet',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
              ),
              const SizedBox(height: 8),
              Text(
                'Import a PDF, PPTX, or pasted notes to create your first '
                'reviewer.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade600),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: onImport,
                  style: FilledButton.styleFrom(backgroundColor: _darkGreen),
                  icon: const Icon(Icons.upload_file),
                  label: const Text('Import Material'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
