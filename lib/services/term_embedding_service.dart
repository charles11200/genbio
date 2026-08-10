import 'dart:math';

import 'package:flutter/services.dart' show rootBundle;
import 'package:tflite_flutter/tflite_flutter.dart';

/// On-device semantic similarity for ranking distractor relevance, backed
/// by a small Biology-domain word-embedding model trained offline (see
/// tool/train_embeddings.py in the repo root) and bundled as a TFLite
/// asset. Fully offline at runtime - no network calls, no cloud inference,
/// same as everything else in this app.
///
/// The model is a single-token embedding lookup (Gather + L2-normalize -
/// two standard ops, nothing exotic). Multi-word terms are embedded by
/// looking up each word separately and mean-pooling here in Dart, rather
/// than baking padding/pooling into the exported graph.
///
/// Deliberately used only on the main isolate: TFLite asset loading needs
/// Flutter's plugin/asset bindings, which a plain compute()-spawned
/// isolate doesn't have without extra setup. Since this runs a handful of
/// small lookups per generated question rather than processing a whole
/// document, it doesn't need its own background isolate the way PDF/PPTX
/// extraction does - see content_import_service.dart for where it's
/// actually called, after the compute()-based generation step returns.
class TermEmbeddingService {
  TermEmbeddingService._();
  static final TermEmbeddingService instance = TermEmbeddingService._();

  static const _modelAsset = 'assets/models/biology_term_embedder.tflite';
  static const _vocabAsset = 'assets/models/biology_vocab.txt';

  // Mirrors the tokenizer used at training time (see train_embeddings.py:
  // lowercase, then split into runs of a-z, length >= 2). Keeping both
  // sides of this contract this simple is what makes it safe to reimplement
  // independently in Dart instead of porting a general-purpose tokenizer.
  static final RegExp _wordPattern = RegExp(r'[a-z]+');

  Interpreter? _interpreter;
  Map<String, int>? _vocab;
  int _embedDim = 0;
  bool _unavailable = false;

  List<String> _tokenizeWords(String text) => _wordPattern
      .allMatches(text.toLowerCase())
      .map((m) => m.group(0)!)
      .where((w) => w.length >= 2)
      .toList();

  Future<void> _ensureLoaded() async {
    if (_interpreter != null || _unavailable) return;
    try {
      final interpreter = await Interpreter.fromAsset(_modelAsset);
      _embedDim = interpreter.getOutputTensor(0).shape.last;

      final vocabText = await rootBundle.loadString(_vocabAsset);
      final vocab = <String, int>{};
      final lines = vocabText.split('\n');
      for (var i = 0; i < lines.length; i++) {
        final w = lines[i].trim();
        if (w.isNotEmpty) vocab[w] = i;
      }

      _interpreter = interpreter;
      _vocab = vocab;
    } catch (_) {
      // Model/vocab missing or failed to load - every public method below
      // degrades to "nothing recognized", so callers fall back to their
      // existing non-ML behavior instead of crashing question generation.
      _unavailable = true;
    }
  }

  List<double> _embedToken(int tokenId) {
    final input = [
      [tokenId],
    ];
    final output = [List<double>.filled(_embedDim, 0.0)];
    _interpreter!.run(input, output);
    return output[0];
  }

  List<double> _l2Normalize(List<double> v) {
    final norm = sqrt(v.fold<double>(0, (s, x) => s + x * x));
    if (norm < 1e-8) return v;
    return [for (final x in v) x / norm];
  }

  /// Mean-pooled, L2-normalized embedding for a (possibly multi-word) term.
  /// Returns null if none of the term's words are in the trained
  /// vocabulary - nothing meaningful to compare, caller should fall back.
  Future<List<double>?> embed(String term) async {
    await _ensureLoaded();
    if (_unavailable) return null;

    final vocab = _vocab!;
    final ids = [
      for (final w in _tokenizeWords(term))
        if (vocab.containsKey(w)) vocab[w]!,
    ];
    if (ids.isEmpty) return null;

    final sum = List<double>.filled(_embedDim, 0.0);
    for (final id in ids) {
      final vec = _embedToken(id);
      for (var i = 0; i < _embedDim; i++) {
        sum[i] += vec[i];
      }
    }
    return _l2Normalize([for (final s in sum) s / ids.length]);
  }

  /// Cosine similarity between two already-normalized embeddings reduces
  /// to a plain dot product.
  static double _cosineSimilarity(List<double> a, List<double> b) {
    var dot = 0.0;
    for (var i = 0; i < a.length && i < b.length; i++) {
      dot += a[i] * b[i];
    }
    return dot;
  }

  /// Ranks [candidates] by semantic similarity to [term] and returns the
  /// top [n]. Candidates the embedding model doesn't recognize are simply
  /// excluded rather than penalized. Returns fewer than [n] (down to an
  /// empty list) if [term] itself isn't recognized or too few candidates
  /// are - callers should treat a short result as "not enough signal" and
  /// fall back to their existing distractor selection.
  Future<List<String>> pickTopSimilar(
    String term,
    List<String> candidates,
    int n,
  ) async {
    final termVec = await embed(term);
    if (termVec == null) return const [];

    final scored = <(String, double)>[];
    for (final candidate in candidates) {
      final vec = await embed(candidate);
      if (vec == null) continue;
      scored.add((candidate, _cosineSimilarity(termVec, vec)));
    }
    scored.sort((a, b) => b.$2.compareTo(a.$2));
    return scored.take(n).map((s) => s.$1).toList();
  }
}
