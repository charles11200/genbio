import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/database_helper.dart';
import '../../data/models.dart';
import '../../services/adaptive_learning_service.dart';
import '../../services/difficulty.dart';
import '../../services/question_pool_service.dart';
import '../../services/sound_service.dart';
import 'game_widgets.dart';
import 'results_screen.dart';

/// Survival mode: same MCQ/per-question-timer structure as
/// QuizGameScreen, but lives-based instead of a fixed-length list. A
/// wrong answer or a timeout costs a life; a correct answer scores a
/// point and costs nothing. The round ends when lives hit 0, or when the
/// module's 'survival' pool runs out first (a completion/win state, not
/// a loss) - whichever comes first.
class SurvivalGameScreen extends StatefulWidget {
  final int moduleId;
  final Difficulty difficulty;

  const SurvivalGameScreen({
    super.key,
    required this.moduleId,
    required this.difficulty,
  });

  @override
  State<SurvivalGameScreen> createState() => _SurvivalGameScreenState();
}

class _SurvivalGameScreenState extends State<SurvivalGameScreen> {
  static const int _startingLives = 3;

  bool _loading = true;
  List<Question> _questions = [];
  int _index = 0;
  int _lives = _startingLives;
  int _score = 0; // correct answers
  int _attempted = 0; // questions answered/timed-out before game over
  int? _selectedIndex;
  bool _answered = false;
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
      'survival',
      difficulty: widget.difficulty.dbValue,
    );
    if (!mounted) return;
    setState(() {
      _questions = pool;
      _loading = false;
    });
    if (pool.isNotEmpty) {
      SoundService.playStart();
      _startQuestionTimer();
    }
  }

  void _startQuestionTimer() {
    _timer?.cancel();
    // Inside setState for the same reason as QuizGameScreen's copy - see
    // the comment there.
    setState(() => _secondsLeft = widget.difficulty.secondsPerQuestion);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_secondsLeft <= 1) {
        t.cancel();
        _handleTimeout();
      } else {
        setState(() => _secondsLeft--);
      }
    });
  }

  Question get _current => _questions[_index];

  void _handleAnswer(int choiceIndex) {
    if (_answered) return;
    _timer?.cancel();
    final correct = _current.choices[choiceIndex] == _current.correctAnswer;
    _recordOutcome(correct);
    setState(() {
      _answered = true;
      _selectedIndex = choiceIndex;
    });
    Future.delayed(const Duration(milliseconds: 700), _advance);
  }

  void _handleTimeout() {
    if (_answered) return;
    _recordOutcome(false);
    setState(() => _answered = true);
    Future.delayed(const Duration(milliseconds: 700), _advance);
  }

  void _recordOutcome(bool correct) {
    _attempted++;
    if (correct) {
      _score++;
    } else {
      _lives--;
    }
    if (_current.id != null) {
      AdaptiveLearningService.recordAnswer(_current.id!, correct);
    }
  }

  void _advance() {
    if (!mounted) return;
    if (_lives <= 0 || _index + 1 >= _questions.length) {
      _finish();
      return;
    }
    setState(() {
      _index++;
      _answered = false;
      _selectedIndex = null;
    });
    _startQuestionTimer();
  }

  Future<void> _finish() async {
    // Survival already has a real win/lose state - pool cleared with lives
    // to spare vs. lives run out - so that decides the sound directly,
    // unlike Quiz/Matching which fall back to a score threshold.
    if (_lives > 0) {
      SoundService.playWin();
    } else {
      SoundService.playLose();
    }
    await DatabaseHelper.instance.insertAttempt(Attempt(
      gameMode: 'survival',
      moduleId: widget.moduleId,
      score: _score,
      totalItems: _attempted,
    ));
    if (!mounted) return;
    Navigator.of(context).pushReplacement(MaterialPageRoute(
      builder: (_) => ResultsScreen(
        gameMode: 'survival',
        moduleId: widget.moduleId,
        score: _score,
        totalItems: _attempted,
        completed: _lives > 0,
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Survival Mode')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _questions.isEmpty
              ? EmptyPoolMessage(
                  gameMode: 'survival',
                  difficultyLabel: widget.difficulty.label,
                )
              : _buildGame(context),
    );
  }

  Widget _buildGame(BuildContext context) {
    final q = _current;
    // Scrollable for the same reason as QuizGameScreen - four
    // sentence-length choices plus a long question can exceed the screen.
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  for (var i = 0; i < _startingLives; i++)
                    Icon(
                      i < _lives ? Icons.favorite : Icons.favorite_border,
                      color: Colors.red,
                    ),
                ],
              ),
              Text('Score: $_score'),
            ],
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: _secondsLeft / widget.difficulty.secondsPerQuestion,
            color: _secondsLeft <= 5 ? Colors.red : null,
          ),
          const SizedBox(height: 4),
          Text('$_secondsLeft s', textAlign: TextAlign.right),
          const SizedBox(height: 24),
          Text(q.questionText, style: const TextStyle(fontSize: 20)),
          const SizedBox(height: 24),
          for (var i = 0; i < q.choices.length; i++) ...[
            ChoiceButton(
              text: q.choices[i],
              onTap: () => _handleAnswer(i),
              state: _choiceState(q, i),
            ),
            const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }

  ChoiceVisualState _choiceState(Question q, int i) {
    if (!_answered) return ChoiceVisualState.neutral;
    final isCorrectChoice = q.choices[i] == q.correctAnswer;
    if (isCorrectChoice) return ChoiceVisualState.correct;
    if (i == _selectedIndex) return ChoiceVisualState.wrong;
    return ChoiceVisualState.neutral;
  }
}