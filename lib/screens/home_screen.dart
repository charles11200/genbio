import 'package:flutter/material.dart';

import '../data/database_helper.dart';
import '../widgets/dna_helix_background.dart';
import 'import_content_screen.dart';
import 'module_select_screen.dart';

/// Student-facing entry point. There is no admin/login role in this app -
/// any student can import material and play directly.
///
/// The three game-mode buttons are disabled until at least one Module
/// exists - nothing to play otherwise - with a brief loading state while
/// that's being checked, so a student can't tap into an empty module list.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late Future<bool> _hasModules;

  @override
  void initState() {
    super.initState();
    _hasModules = _checkHasModules();
  }

  Future<bool> _checkHasModules() async {
    final modules = await DatabaseHelper.instance.getAllModules();
    return modules.isNotEmpty;
  }

  void _openGame(BuildContext context, String gameMode) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ModuleSelectScreen(gameMode: gameMode),
    ));
  }

  Future<void> _openImport(BuildContext context) async {
    final imported = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const ImportContentScreen()),
    );
    if (!mounted) return;
    // Always re-check, not just when imported == true - re-deriving from
    // the database is cheap, and this keeps the game buttons' enabled
    // state correct even if the popped value itself is ever unreliable
    // (only the SnackBar below is conditional on it, since that one's
    // just a courtesy notification, not correctness-critical).
    //
    // NOTE: must be a block body, not `setState(() => _hasModules = ...)`.
    // An arrow-bodied callback there evaluates to the assignment's value -
    // Future<bool> here - so setState() receives a callback that *returns*
    // a Future instead of void and throws "setState() callback argument
    // returned a Future" the instant this runs, silently aborting before
    // the reassignment or anything after it in this function ever
    // executes. Block body has no implicit return, so this is void.
    setState(() {
      _hasModules = _checkHasModules();
    });
    if (imported == true && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Module created! Pick a game mode to start reviewing.'),
        ),
      );
    }
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
            Text('BioQuest'),
          ],
        ),
      ),
      backgroundColor: const Color(0xFF2E7D32),
      body: Stack(
        children: [
          const Positioned.fill(
            child: DnaHelixBackground(strandColor: Colors.white),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: FutureBuilder<bool>(
                future: _hasModules,
                builder: (context, snapshot) {
                  final checking = !snapshot.hasData;
                  final hasModules = snapshot.data ?? false;
                  final gamesEnabled = !checking && hasModules;

                  return Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text(
                        '"The Effect of BioQuest Reviewing Offline App on '
                        'the Formative Assessment Score of STEM Students '
                        'in Biology"',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 32),
                      _GameButton(
                        label: 'Timed Quiz',
                        icon: Icons.timer,
                        enabled: gamesEnabled,
                        onTap: () => _openGame(context, 'quiz'),
                      ),
                      const SizedBox(height: 16),
                      _GameButton(
                        label: 'Matching Game',
                        icon: Icons.compare_arrows,
                        enabled: gamesEnabled,
                        onTap: () => _openGame(context, 'matching'),
                      ),
                      const SizedBox(height: 16),
                      _GameButton(
                        label: 'Survival Mode',
                        icon: Icons.favorite,
                        enabled: gamesEnabled,
                        onTap: () => _openGame(context, 'survival'),
                      ),
                      const SizedBox(height: 28),
                      _GameButton(
                        label: 'Import Material',
                        icon: Icons.upload_file,
                        // Always enabled - the only way to get out of the
                        // "no modules yet" state in the first place.
                        enabled: true,
                        onTap: () => _openImport(context),
                      ),
                      const SizedBox(height: 20),
                      if (checking)
                        const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      else if (!hasModules)
                        const Text(
                          'Import material first to unlock the games.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.white70),
                        ),
                    ],
                  );
                },
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
  final bool enabled;
  final VoidCallback onTap;

  const _GameButton({
    required this.label,
    required this.icon,
    required this.onTap,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: FilledButton.icon(
        onPressed: enabled ? onTap : null,
        style: FilledButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: const Color(0xFF2E7D32),
          disabledBackgroundColor: Colors.grey.shade300,
          disabledForegroundColor: Colors.grey.shade600,
        ),
        icon: Icon(icon),
        label: Text(label, style: const TextStyle(fontSize: 16)),
      ),
    );
  }
}
