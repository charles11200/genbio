import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../services/content_import_service.dart';
import 'review_questions_screen.dart';

/// Lets a student turn a PDF, PPTX, or pasted notes into a new playable
/// Module. No login/admin gate - this is the only way any Module gets
/// created, and any student can reach it directly (see home_screen.dart
/// and module_select_screen.dart for the entry points).
///
/// Pops with `true` on success so callers know to refresh their module
/// list / show a confirmation - see the two entry-point screens.
class ImportContentScreen extends StatefulWidget {
  const ImportContentScreen({super.key});

  @override
  State<ImportContentScreen> createState() => _ImportContentScreenState();
}

class _ImportContentScreenState extends State<ImportContentScreen> {
  final _titleController = TextEditingController();
  final _notesController = TextEditingController();

  String? _pickedFilePath;
  bool _isImporting = false;
  String? _errorMessage;

  @override
  void dispose() {
    _titleController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'pptx'],
      allowMultiple: false,
    );
    final path = result?.files.single.path;
    if (path == null) return;
    setState(() {
      _pickedFilePath = path;
      _notesController.clear();
      _errorMessage = null;
    });
  }

  void _clearFile() => setState(() => _pickedFilePath = null);

  bool get _canSubmit =>
      _titleController.text.trim().isNotEmpty &&
      (_pickedFilePath != null || _notesController.text.trim().isNotEmpty);

  Future<void> _submit() async {
    if (!_canSubmit || _isImporting) return;
    setState(() {
      _isImporting = true;
      _errorMessage = null;
    });

    try {
      final prepared = await ContentImportService.prepare(
        filePath: _pickedFilePath,
        pastedNotes: _pickedFilePath == null ? _notesController.text : null,
      );
      if (!mounted) return;

      // Ask how many of the questions this material can actually support
      // the student wants, before anything is written to the database.
      final chosenCount = await showDialog<int>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _QuestionCountDialog(prepared: prepared),
      );
      if (!mounted || chosenCount == null) {
        setState(() => _isImporting = false);
        return;
      }

      final moduleId = await ContentImportService.save(
        prepared: prepared,
        moduleTitle: _titleController.text.trim(),
        questionCount: chosenCount,
      );
      if (!mounted) return;
      // Hand off to review before this pops - see ReviewQuestionsScreen's
      // docstring for why every way of leaving it (Confirm/back/system
      // gesture) ends up popping true, so this line always runs with a
      // real result rather than hanging.
      final reviewed = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => ReviewQuestionsScreen(moduleId: moduleId),
        ),
      );
      if (!mounted) return;
      Navigator.of(context).pop(reviewed ?? false);
    } on ContentImportException catch (e) {
      setState(() => _errorMessage = e.message);
    } catch (_) {
      setState(
        () => _errorMessage = 'Something went wrong. Please try again.',
      );
    } finally {
      if (mounted) setState(() => _isImporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final fieldsEnabled = !_isImporting;
    return PopScope(
      canPop: !_isImporting,
      child: Scaffold(
        appBar: AppBar(title: const Text('Import Material')),
        body: Padding(
          padding: const EdgeInsets.all(20),
          child: ListView(
            children: [
              TextField(
                key: const Key('import_title_field'),
                controller: _titleController,
                enabled: fieldsEnabled,
                decoration: const InputDecoration(
                  labelText: 'Module title',
                  hintText: 'e.g. Cell Biology Chapter 3',
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 24),
              Text(
                'Source material',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              if (_pickedFilePath == null)
                OutlinedButton.icon(
                  onPressed: fieldsEnabled ? _pickFile : null,
                  icon: const Icon(Icons.upload_file),
                  label: const Text('Pick a PDF or PPTX file'),
                )
              else
                ListTile(
                  tileColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                  leading: const Icon(Icons.description),
                  title: Text(
                    p.basename(_pickedFilePath!),
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: fieldsEnabled ? _clearFile : null,
                  ),
                ),
              const SizedBox(height: 16),
              const Row(
                children: [
                  Expanded(child: Divider()),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8),
                    child: Text('OR'),
                  ),
                  Expanded(child: Divider()),
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                key: const Key('import_notes_field'),
                controller: _notesController,
                enabled: fieldsEnabled && _pickedFilePath == null,
                maxLines: 8,
                decoration: const InputDecoration(
                  labelText: 'Paste notes instead',
                  border: OutlineInputBorder(),
                  alignLabelWithHint: true,
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 24),
              if (_errorMessage != null) ...[
                Text(
                  _errorMessage!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
                const SizedBox(height: 12),
              ],
              FilledButton(
                onPressed: _canSubmit && fieldsEnabled ? _submit : null,
                child: _isImporting
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Generate Reviewer'),
              ),
              if (_isImporting) ...[
                const SizedBox(height: 12),
                const Text(
                  'Extracting text and generating questions - this can '
                  'take a moment for longer files.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontStyle: FontStyle.italic),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Asks how many questions to actually create, once the generator has
/// reported what this specific material can support. The maximum isn't a
/// fixed number - it's however many the imported text could genuinely
/// produce (PreparedImport.maxQuestions), so a short set of notes offers
/// a small range and a full chapter offers a large one.
class _QuestionCountDialog extends StatefulWidget {
  final PreparedImport prepared;
  const _QuestionCountDialog({required this.prepared});

  @override
  State<_QuestionCountDialog> createState() => _QuestionCountDialogState();
}

class _QuestionCountDialogState extends State<_QuestionCountDialog> {
  late int _count;

  int get _max => widget.prepared.maxQuestions;

  /// Survival needs a real pool to be playable at all, so the slider
  /// floors at 10 whenever the material can supply that many. When it
  /// can't, the floor drops to whatever exists (and the note below warns
  /// that Survival will be short) rather than blocking the import.
  int get _min => _max < ContentImportService.minSurvivalQuestions
      ? _max
      : ContentImportService.minSurvivalQuestions;

  bool get _belowSurvivalMinimum =>
      _max < ContentImportService.minSurvivalQuestions;

  @override
  void initState() {
    super.initState();
    _count = _max;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('How many questions?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'This material can make up to $_max question'
            '${_max == 1 ? '' : 's'}'
            '${widget.prepared.pairCount > 0 ? ' and ${widget.prepared.pairCount} matching pair${widget.prepared.pairCount == 1 ? '' : 's'}' : ''}.',
          ),
          const SizedBox(height: 20),
          Text(
            '$_count question${_count == 1 ? '' : 's'}',
            style: Theme.of(context)
                .textTheme
                .headlineSmall
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          if (_max > _min)
            Slider(
              value: _count.toDouble(),
              min: _min.toDouble(),
              max: _max.toDouble(),
              divisions: _max - _min,
              label: '$_count',
              onChanged: (v) => setState(() => _count = v.round()),
            )
          else
            const SizedBox(height: 8),
          if (_belowSurvivalMinimum)
            Text(
              'Survival Mode needs at least '
              '${ContentImportService.minSurvivalQuestions} questions - '
              'import longer material to unlock a full round.',
              style: TextStyle(fontSize: 12, color: Colors.orange.shade800),
            )
          else
            Text(
              'Minimum $_min, so Survival Mode always has a full round.',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_count),
          child: const Text('Create'),
        ),
      ],
    );
  }
}
