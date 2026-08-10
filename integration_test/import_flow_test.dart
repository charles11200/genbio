import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:genbio/data/database_helper.dart';
import 'package:genbio/main.dart';

/// End-to-end: Home -> Import Material -> paste notes -> Generate Reviewer
/// -> back on Home with a real Module in the database. Runs as a real app
/// process (see term_embedding_test.dart for why), so this exercises the
/// actual compute()-isolate generation AND the on-device TF distractor
/// re-ranking together, not mocked pieces.
///
/// Doesn't assume a clean database (getAllModules() orders by id DESC, so
/// `.first` after import is always the just-created module regardless of
/// what other modules already exist on the test device) - repeat runs on
/// the same phone just add another module rather than failing.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
      'importing pasted Biology notes creates a module whose MCQ '
      'distractors never leak the question\'s own subject '
      '(regression coverage for the "Subject is the" over-capture bug)',
      (tester) async {
    await tester.pumpWidget(const GenBioReviewApp());
    // NOT pumpAndSettle(): the Home screen's DnaHelixBackground runs a
    // repeat()-forever AnimationController, so the tree never stops
    // scheduling frames and pumpAndSettle() would spin until it times out.
    // Pump in bounded steps and check for the expected widget instead,
    // throughout this whole test - see _pumpUntilFound.
    await _pumpUntilFound(tester, find.text('Import Material'));

    await tester.tap(find.text('Import Material'));
    await _pumpUntilFound(tester, find.byKey(const Key('import_title_field')));

    await tester.enterText(
      find.byKey(const Key('import_title_field')),
      'Integration Test Module',
    );
    await tester.enterText(
      find.byKey(const Key('import_notes_field')),
      'Mitochondria is the powerhouse of the cell that produces energy. '
      'Chloroplast is the organelle where photosynthesis takes place in '
      'plants. Nucleus is the control center that contains genetic '
      'material. Ribosome is the site of protein synthesis in the cell. '
      'Golgi apparatus is the organelle that packages proteins for '
      'transport.',
    );
    await tester.pump();

    await tester.tap(find.text('Generate Reviewer'));
    // Real extraction + generation + on-device inference, then a pop back
    // to the (perpetually-animating) Home screen - generous step budget
    // since this is the one doing real work, not just a UI transition.
    await _pumpUntilFound(
      tester,
      find.textContaining('Module created'),
      maxSteps: 300,
    );

    // Popped back to Home with the success SnackBar. Not also asserting
    // on Home's "Import Material" button text here - the AppBar we just
    // popped is *also* titled "Import Material", so mid-transition both
    // are briefly in the tree at once (a real findsOneWidget flake, not
    // an app bug). findsWidgets rather than findsOneWidget on the
    // SnackBar text too - Material's animated SnackBar entrance commonly
    // renders its Text twice mid-transition, a well-known flutter_test
    // quirk unrelated to app correctness.
    expect(find.textContaining('Module created'), findsWidgets);

    final modules = await DatabaseHelper.instance.getAllModules();
    final created = modules.first;
    expect(created.title, 'Integration Test Module');

    final questions = await DatabaseHelper.instance
        .getQuestionsByModuleAndGameMode(created.id!, 'quiz');
    expect(questions, isNotEmpty);

    for (final q in questions) {
      final subject =
          q.questionText.replaceFirst('What is ', '').replaceAll('?', '');
      final distractors = q.choices.where((c) => c != q.correctAnswer);
      for (final d in distractors) {
        expect(
          d.toLowerCase().startsWith(subject.toLowerCase()),
          isFalse,
          reason:
              'distractor "$d" leaks the question\'s own subject ("$subject")',
        );
      }
    }
  });
}

Future<void> _pumpUntilFound(
  WidgetTester tester,
  Finder finder, {
  Duration step = const Duration(milliseconds: 100),
  int maxSteps = 100,
}) async {
  for (var i = 0; i < maxSteps; i++) {
    if (finder.evaluate().isNotEmpty) return;
    await tester.pump(step);
  }
}
