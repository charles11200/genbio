import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../../data/database_helper.dart';
import '../../data/models.dart';
import '../../services/difficulty.dart';
import '../../services/question_pool_service.dart';
import '../../services/scoring.dart';
import '../../services/sound_service.dart';
import 'game_widgets.dart';
import 'results_screen.dart';

/// Matching game: real tap-a-term / tap-a-definition matching, not MCQ.
///
/// The module's whole 'matching' pool is pulled up front and split into
/// 5-pair rounds (QuestionPoolService.chunkIntoRounds). Each round shows
/// its 5 terms and 5 definitions in independently-shuffled columns; a
/// correct tap pair locks both tiles green, scores a point, and draws a
/// connecting line between them (see _recomputeLines). A wrong pair
/// flashes red, draws no line, and simply deselects - no score penalty,
/// but it counts toward `_mistakes`. A round ends when every pair in it is
/// matched, or when the shared per-round timer runs out; the game itself
/// ends when every round has been played.
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
  int _mistakes = 0;

  List<Question> _terms = [];
  List<Question> _definitions = [];
  final Set<int> _matchedIds = {};
  int? _selectedTermId;
  int? _selectedDefId;
  int? _wrongFlashTermId;
  int? _wrongFlashDefId;

  // One tile widget per term/definition id, keyed so _recomputeLines can
  // find each tile's on-screen position after layout - see that method for
  // why a GlobalKey is the right tool here rather than tracking offsets by
  // hand.
  Map<int, GlobalKey> _termKeys = {};
  Map<int, GlobalKey> _defKeys = {};
  final GlobalKey _boardKey = GlobalKey();
  List<_MatchLine> _matchLines = [];

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
    final pool = await QuestionPoolService.buildPool(
      widget.moduleId,
      'matching',
      difficulty: widget.difficulty.dbValue,
    );
    if (!mounted) return;
    final rounds = QuestionPoolService.chunkIntoRounds(pool);
    setState(() {
      _rounds = rounds;
      _totalPairs = pool.length;
      _loading = false;
    });
    if (rounds.isNotEmpty) {
      // Only here, not inside _startRound() - that method also runs for
      // round 2, 3... of the same session, and the start sound should
      // play once per game, not once per round.
      SoundService.playStart();
      _startRound();
    }
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
      _termKeys = {for (final q in pairs) q.id!: GlobalKey()};
      _defKeys = {for (final q in pairs) q.id!: GlobalKey()};
      _matchLines = [];
    });
    _startRoundTimer();
  }

  void _startRoundTimer() {
    _timer?.cancel();
    // Inside setState: _startRound()'s own setState has already scheduled
    // a rebuild by the time this runs, so a bare assignment would leave
    // the round clock showing the previous round's leftover value (0 on
    // the first round) until the first tick a second later.
    setState(() => _secondsLeft = widget.difficulty.secondsPerMatchingRound);
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
      // Tile positions for this pair are only known once this frame has
      // been laid out - see _recomputeLines.
      WidgetsBinding.instance.addPostFrameCallback((_) => _recomputeLines());
      if (_matchedIds.length == _currentRoundPairs.length) {
        _timer?.cancel();
        Future.delayed(const Duration(milliseconds: 500), _goToNextRound);
      }
    } else {
      setState(() {
        _mistakes++;
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

  /// Computes a screen-space line for every matched pair, from the right
  /// edge of its term tile to the left edge of its definition tile.
  ///
  /// Must run in a post-frame callback, not inline in _attemptMatch: the
  /// tile that was just matched hasn't been laid out with its new
  /// (post-match) state yet at the moment setState is called, so reading
  /// its RenderBox synchronously would still return stale-or-absent
  /// geometry. By the time this callback fires, that frame has completed
  /// layout, so every GlobalKey's RenderBox reflects real on-screen
  /// positions - which this then converts into _boardKey's own coordinate
  /// space (not the screen's), since _boardKey is the Stack that both the
  /// tiles and the line-painting CustomPaint live inside. Because that
  /// whole Stack scrolls as a single rigid unit, positions computed this
  /// way stay correct through scrolling with no extra listener needed.
  void _recomputeLines() {
    if (!mounted) return;
    final boardBox = _boardKey.currentContext?.findRenderObject() as RenderBox?;
    if (boardBox == null || !boardBox.attached) return;

    final lines = <_MatchLine>[];
    for (final id in _matchedIds) {
      final termBox =
          _termKeys[id]?.currentContext?.findRenderObject() as RenderBox?;
      final defBox =
          _defKeys[id]?.currentContext?.findRenderObject() as RenderBox?;
      if (termBox == null || defBox == null) continue;
      if (!termBox.attached || !defBox.attached) continue;

      final start = termBox.localToGlobal(
        Offset(termBox.size.width, termBox.size.height / 2),
        ancestor: boardBox,
      );
      final end = defBox.localToGlobal(
        Offset(0, defBox.size.height / 2),
        ancestor: boardBox,
      );
      lines.add(_MatchLine(start, end));
    }
    setState(() => _matchLines = lines);
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
    // Matching has no other win/lose state of its own (every round always
    // completes, there's no "ran out of lives"), so the pass/fail
    // threshold in scoring.dart decides which sound plays - same as Quiz.
    if (isPassingScore(_score, _totalPairs)) {
      SoundService.playWin();
    } else {
      SoundService.playLose();
    }
    await DatabaseHelper.instance.insertAttempt(Attempt(
      gameMode: 'matching',
      moduleId: widget.moduleId,
      score: _score,
      totalItems: _totalPairs,
      mistakes: _mistakes,
    ));
    if (!mounted) return;
    Navigator.of(context).pushReplacement(MaterialPageRoute(
      builder: (_) => ResultsScreen(
        gameMode: 'matching',
        moduleId: widget.moduleId,
        score: _score,
        totalItems: _totalPairs,
        mistakes: _mistakes,
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
              ? EmptyPoolMessage(
                  gameMode: 'matching',
                  difficultyLabel: widget.difficulty.label,
                )
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
          // One shared scroll view over both columns, rather than two
          // independent ones: a term and its definition must stay
          // side-by-side and reachable together, which separate scroll
          // positions would break. Five tiles of up-to-3-line definitions
          // overflow a fixed-height Column on smaller screens.
          Expanded(
            child: SingleChildScrollView(
              child: Stack(
                key: _boardKey,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          children: [
                            for (final q in _terms)
                              _MatchTile(
                                key: _termKeys[q.id],
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
                                key: _defKeys[q.id],
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
                  // Lines only ever get added for confirmed-correct pairs
                  // (see _attemptMatch) - a wrong tap never reaches
                  // _recomputeLines, so it simply never connects.
                  Positioned.fill(
                    child: IgnorePointer(
                      child: CustomPaint(
                        painter: _MatchLinesPainter(_matchLines),
                      ),
                    ),
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

class _MatchLine {
  final Offset start;
  final Offset end;
  const _MatchLine(this.start, this.end);
}

class _MatchLinesPainter extends CustomPainter {
  final List<_MatchLine> lines;
  const _MatchLinesPainter(this.lines);

  static const _arrowheadLength = 9.0;
  static const _arrowheadSpread = 0.5; // radians

  @override
  void paint(Canvas canvas, Size size) {
    final linePaint = Paint()
      ..color = Colors.green.shade700
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final headPaint = Paint()
      ..color = Colors.green.shade700
      ..style = PaintingStyle.fill;

    for (final line in lines) {
      canvas.drawLine(line.start, line.end, linePaint);

      final angle = (line.end - line.start).direction;
      final p1 = line.end -
          Offset(cos(angle - _arrowheadSpread), sin(angle - _arrowheadSpread)) *
              _arrowheadLength;
      final p2 = line.end -
          Offset(cos(angle + _arrowheadSpread), sin(angle + _arrowheadSpread)) *
              _arrowheadLength;
      canvas.drawPath(
        Path()
          ..moveTo(line.end.dx, line.end.dy)
          ..lineTo(p1.dx, p1.dy)
          ..lineTo(p2.dx, p2.dy)
          ..close(),
        headPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _MatchLinesPainter oldDelegate) =>
      !identical(oldDelegate.lines, lines);
}

class _MatchTile extends StatelessWidget {
  final String text;
  final bool locked;
  final Color? color;
  final VoidCallback onTap;

  const _MatchTile({
    super.key,
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
