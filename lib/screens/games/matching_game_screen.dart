import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../../data/database_helper.dart';
import '../../data/models.dart';
import '../../services/difficulty.dart';
import '../../services/question_pool_service.dart';
import 'game_widgets.dart';
import 'results_screen.dart';

/// Matching game: real tap-a-term / tap-a-definition matching, not MCQ.
///
/// The module's whole 'matching' pool is pulled up front and split into
/// 5-pair rounds (QuestionPoolService.chunkIntoRounds). Each round shows
/// its 5 terms and 5 definitions in independently-shuffled columns; a
/// correct tap pair locks both tiles green and scores a point, a wrong
/// pair flashes red and simply deselects (no penalty - the student can
/// retry). A round ends when every pair in it is matched, or when the
/// shared per-round timer runs out; the game itself ends when every round
/// has been played.
class MatchingGameScreen extends StatefulWidget {
  final int moduleId;
  final Difficulty difficulty;

  const MatchingGameScreen({
    super.key,
    required this.moduleId,
    required this.difficulty,
  });

  @override
  State<MatchingGameScreen> createState() => _MatchingGameScreenState();
}

class _MatchingGameScreenState extends State<MatchingGameScreen> {
  final Random _random = Random();

  bool _loading = true;
  List<List<Question>> _rounds = [];
  int _totalPairs = 0;
  int _roundIndex = 0;
  int _score = 0;

  List<Question> _terms = [];
  List<Question> _definitions = [];
  final Set<int> _matchedIds = {};
  int? _selectedTermId;
  int? _selectedDefId;
  int? _wrongFlashTermId;
  int? _wrongFlashDefId;

  Timer? _timer;
  int _secondsLeft = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final pool = await QuestionPoolService.buildPool(widget.moduleId, 'matching');
    if (!mounted) return;
    final rounds = QuestionPoolService.chunkIntoRounds(pool);
    setState(() {
      _rounds = rounds;
      _totalPairs = pool.length;
      _loading = false;
    });
    if (rounds.isNotEmpty) _startRound();
  }

  List<Question> get _currentRoundPairs => _rounds[_roundIndex];

  void _startRound() {
    final pairs = _currentRoundPairs;
    setState(() {
      _terms = List.of(pairs)..shuffle(_random);
      _definitions = List.of(pairs)..shuffle(_random);
      _matchedIds.clear();
      _selectedTermId = null;
      _selectedDefId = null;
      _wrongFlashTermId = null;
      _wrongFlashDefId = null;
    });
    _startRoundTimer();
  }

  void _startRoundTimer() {
    _secondsLeft = widget.difficulty.secondsPerMatchingRound;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_secondsLeft <= 1) {
        t.cancel();
        _goToNextRound();
      } else {
        setState(() => _secondsLeft--);
      }
    });
  }

  void _tapTerm(Question q) {
    if (_matchedIds.contains(q.id) || _wrongFlashTermId != null) return;
    setState(() => _selectedTermId = q.id);
    _attemptMatch();
  }

  void _tapDefinition(Question q) {
    if (_matchedIds.contains(q.id) || _wrongFlashDefId != null) return;
    setState(() => _selectedDefId = q.id);
    _attemptMatch();
  }

  void _attemptMatch() {
    if (_selectedTermId == null || _selectedDefId == null) return;
    final termId = _selectedTermId!;
    final defId = _selectedDefId!;

    if (termId == defId) {
      setState(() {
        _matchedIds.add(termId);
        _score++;
        _selectedTermId = null;
        _selectedDefId = null;
      });
      if (_matchedIds.length == _currentRoundPairs.length) {
        _timer?.cancel();
        Future.delayed(const Duration(milliseconds: 500), _goToNextRound);
      }
    } else {
      setState(() {
        _wrongFlashTermId = termId;
        _wrongFlashDefId = defId;
        _selectedTermId = null;
        _selectedDefId = null;
      });
      Future.delayed(const Duration(milliseconds: 400), () {
        if (!mounted) return;
        setState(() {
          _wrongFlashTermId = null;
          _wrongFlashDefId = null;
        });
      });
    }
  }

  void _goToNextRound() {
    if (!mounted) return;
    _timer?.cancel();
    if (_roundIndex + 1 >= _rounds.length) {
      _finish();
    } else {
      setState(() => _roundIndex++);
      _startRound();
    }
  }

  Future<void> _finish() async {
    await DatabaseHelper.instance.insertAttempt(Attempt(
      gameMode: 'matching',
      moduleId: widget.moduleId,
      score: _score,
      totalItems: _totalPairs,
    ));
    if (!mounted) return;
    Navigator.of(context).pushReplacement(MaterialPageRoute(
      builder: (_) => ResultsScreen(
        gameMode: 'matching',
        moduleId: widget.moduleId,
        score: _score,
        totalItems: _totalPairs,
      ),
    ));
  }

  Color? _tileColor(BuildContext context, int id, {required bool isTerm}) {
    if (_matchedIds.contains(id)) return Colors.green.shade400;
    final flashId = isTerm ? _wrongFlashTermId : _wrongFlashDefId;
    if (flashId == id) return Colors.red.shade300;
    final selectedId = isTerm ? _selectedTermId : _selectedDefId;
    if (selectedId == id) {
      return Theme.of(context).colorScheme.primaryContainer;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Matching Game')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _rounds.isEmpty
              ? const EmptyPoolMessage(gameMode: 'matching')
              : _buildGame(context),
    );
  }

  Widget _buildGame(BuildContext context) {
    final roundTotal = widget.difficulty.secondsPerMatchingRound;
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Round ${_roundIndex + 1}/${_rounds.length}'),
              Text('Matched ${_matchedIds.length}/${_currentRoundPairs.length}'),
              Text('Score: $_score'),
            ],
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: _secondsLeft / roundTotal,
            color: _secondsLeft <= 5 ? Colors.red : null,
          ),
          const SizedBox(height: 4),
          Text('$_secondsLeft s', textAlign: TextAlign.right),
          const SizedBox(height: 16),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    children: [
                      for (final q in _terms)
                        _MatchTile(
                          text: q.questionText,
                          locked: _matchedIds.contains(q.id),
                          color: _tileColor(context, q.id!, isTerm: true),
                          onTap: () => _tapTerm(q),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    children: [
                      for (final q in _definitions)
                        _MatchTile(
                          text: q.correctAnswer,
                          locked: _matchedIds.contains(q.id),
                          color: _tileColor(context, q.id!, isTerm: false),
                          onTap: () => _tapDefinition(q),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MatchTile extends StatelessWidget {
  final String text;
  final bool locked;
  final Color? color;
  final VoidCallback onTap;

  const _MatchTile({
    required this.text,
    required this.locked,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Material(
        color: color ?? Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: locked ? null : onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              text,
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ),
    );
  }
}