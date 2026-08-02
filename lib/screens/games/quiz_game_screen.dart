import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/database_helper.dart';
import '../../data/models.dart';
import '../../services/adaptive_learning_service.dart';
import '../../services/difficulty.dart';
import '../../services/question_pool_service.dart';
import 'game_widgets.dart';
import 'results_screen.dart';

/// Timed Quiz: a fixed list of MCQ questions, each with its own
/// per-question countdown (sized by [difficulty]). Unanswered-in-time
/// counts as wrong, same as a wrong tap. This is also the structural
/// pattern SurvivalGameScreen follows (pool -> per-question timer ->
/// record answer -> advance), just without the lives/early-exit rules.
class QuizGameScreen extends StatefulWidget {
  final int moduleId;
  final Difficulty difficulty;

  const QuizGameScreen({
    super.key,
    required this.moduleId,
    required this.difficulty,
  });

  @override
  State<QuizGameScreen> createState() => _QuizGameScreenState();
}

class _QuizGameScreenState extends State<QuizGameScreen> {
  static const int _questionLimit = 15;

  bool _loading = true;
  List<Question> _questions = [];
  int _index = 0;
  int _score = 0;
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
      'quiz',
      limit: _questionLimit,
    );
    if (!mounted) return;
    setState(() {
      _questions = pool;
      _loading = false;
    });
    if (pool.isNotEmpty) _startQuestionTimer();
  }

  void _startQuestionTimer() {
    _secondsLeft = widget.difficulty.secondsPerQuestion;
    _timer?.cancel();
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
    setState(() {
      _answered = true;
      _selectedIndex = choiceIndex;
      if (correct) _score++;
    });
    if (_current.id != null) {
      AdaptiveLearningService.recordAnswer(_current.id!, correct);
    }
    Future.delayed(const Duration(milliseconds: 700), _advance);
  }

  void _handleTimeout() {
    if (_answered) return;
    setState(() => _answered = true);
    if (_current.id != null) {
      AdaptiveLearningService.recordAnswer(_current.id!, false);
    }
    Future.delayed(const Duration(milliseconds: 700), _advance);
  }

  void _advance() {
    if (!mounted) return;
    if (_index + 1 >= _questions.length) {
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
    await DatabaseHelper.instance.insertAttempt(Attempt(
      gameMode: 'quiz',
      moduleId: widget.moduleId,
      score: _score,
      totalItems: _questions.length,
    ));
    if (!mounted) return;
    Navigator.of(context).pushReplacement(MaterialPageRoute(
      builder: (_) => ResultsScreen(
        gameMode: 'quiz',
        moduleId: widget.moduleId,
        score: _score,
        totalItems: _questions.length,
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Timed Quiz')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _questions.isEmpty
              ? const EmptyPoolMessage(gameMode: 'quiz')
              : _buildQuiz(context),
    );
  }

  Widget _buildQuiz(BuildContext context) {
    final q = _current;
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Question ${_index + 1}/${_questions.length}'),
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