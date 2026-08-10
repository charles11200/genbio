"""
Trains small Biology-domain word embeddings (skip-gram, plain Keras) and
exports a minimal single-token embedding-lookup graph to TFLite, ready to
drop into assets/models/ - this is the actual script that produced the
model the app ships.

Run from anywhere (paths are relative to this script's own location):

    python tool/train_embeddings.py

Requires: tensorflow, numpy. Run tool/fetch_corpus.py first if
biology_corpus.txt isn't present.

Kept deliberately simple/standard-ops-only - this is the one place ML
enters this otherwise fully rule-based, offline app (see
question_generator.dart's own docstring for why generation itself stays
rule-based):
  - tokenizer: lowercase + [a-z]+ regex word split (trivial to mirror in
    Dart - see TermEmbeddingService)
  - model: Embedding -> Dense(vocab_size, softmax) predicting a nearby
    context word, i.e. textbook skip-gram (full softmax, no negative
    sampling - unnecessary complexity at this vocab size)
  - export graph: Embedding lookup for ONE token id -> L2-normalize.
    Multi-word phrases are mean-pooled on the Dart side by calling this
    once per word, so the exported graph itself has nothing but a Gather
    and a norm - verified zero custom ops via verify_tflite.py, unlike
    TensorFlow Hub's Universal Sentence Encoder (which needs an in-graph
    SentencePiece op that plain tflite_flutter can't run - this smaller,
    self-trained model exists specifically to sidestep that).
"""
import re
import json
import numpy as np
import tensorflow as tf
from collections import Counter
from pathlib import Path

HERE = Path(__file__).parent
# biology_corpus.txt: broad general-biology prose from Wikipedia (see
# fetch_corpus.py) - covers curriculum breadth (genetics, evolution,
# ecology, cell biology...).
# questions_corpus.txt: a self-authored ~800-item STEM Biology test bank
# (MCQ/fill-in-blank/identification/true-false covering tissues, organ
# systems, homeostasis, plant physiology) - narrower topically but much
# closer to the actual vocabulary/phrasing register real students and
# their imported review material will use. Q&A format doesn't hurt
# skip-gram training - repeated phrasing of the same relationships across
# many item variations is still valid co-occurrence signal, and the
# tokenizer below only extracts alphabetic words anyway, so option
# labels/numbering/answer-key indices just contribute nothing rather than
# noise.
# openstax_biology_corpus.txt: OpenStax Biology 2e (CC BY 4.0), fetched via
# fetch_openstax.py from the book's official GitHub source - full
# college-level textbook prose, the largest single source.
# openstax_concepts_corpus.txt / openstax_microbiology_corpus.txt: two more
# OpenStax CC BY 4.0 books (fetch_openstax_extra.py) - Concepts of Biology
# mostly reinforces core terms Biology 2e already covers (pushes
# borderline-frequency words past MIN_COUNT rather than adding many brand
# new ones), Microbiology adds vocabulary the other sources barely touch
# (pathogens, immune response, lab technique).
CORPUS_PATHS = [
    HERE / "biology_corpus.txt",
    HERE / "questions_corpus.txt",
    HERE / "openstax_biology_corpus.txt",
    HERE / "openstax_concepts_corpus.txt",
    HERE / "openstax_microbiology_corpus.txt",
]
ASSETS_DIR = HERE.parent / "assets" / "models"

# VOCAB_SIZE is a ceiling, not a target - it should cover every word that
# clears MIN_COUNT, not an arbitrary round number. Measured directly
# against this exact 5-source corpus: 16,444 distinct words occur >= 3
# times (see tool/README or the "sapat na ba" investigation - a smaller
# 3-source version of this corpus only had 12,830, already nearly maxing
# out the old 12,000 cap). 17000 covers all 16,444 with headroom instead
# of silently clipping the tail again. Raising this number alone without
# more real source text would NOT add real vocabulary - words that never
# reach MIN_COUNT occurrences don't get a meaningfully-trained vector no
# matter how high the cap is set. Model size stays mobile-reasonable:
# vocab_size * embed_dim floats, ~4.3MB at 17000*64.
VOCAB_SIZE = 17000         # top-N words by frequency, +1 for <unk> at id 0
MIN_COUNT = 3
EMBED_DIM = 64
WINDOW = 4
EPOCHS = 8
BATCH_SIZE = 1024
SEED = 7

np.random.seed(SEED)
tf.random.set_seed(SEED)

# ---------- 1. Load + tokenize ----------
text = "\n".join(p.read_text(encoding="utf-8") for p in CORPUS_PATHS).lower()
for p in CORPUS_PATHS:
    print(f"  corpus source: {p.name} ({p.stat().st_size:,} bytes)")

WORD_RE = re.compile(r"[a-z]+")
tokens = WORD_RE.findall(text)
tokens = [t for t in tokens if len(t) >= 2]
print(f"Total tokens: {len(tokens):,}")

# ---------- 2. Vocabulary ----------
counts = Counter(tokens)
most_common = [w for w, c in counts.most_common() if c >= MIN_COUNT][: VOCAB_SIZE - 1]
vocab = ["<unk>"] + most_common
word_to_id = {w: i for i, w in enumerate(vocab)}
vocab_size = len(vocab)
print(f"Vocab size: {vocab_size:,} (covering {sum(counts[w] for w in most_common):,}/{len(tokens):,} tokens)")

ids = np.array([word_to_id.get(t, 0) for t in tokens], dtype=np.int32)

# ---------- 3. Skip-gram pairs (center -> each context word in window) ----------
centers, contexts = [], []
n = len(ids)
for offset in range(1, WINDOW + 1):
    left_c, left_ctx = ids[offset:], ids[:-offset]
    right_c, right_ctx = ids[:-offset], ids[offset:]
    centers.append(left_c); contexts.append(left_ctx)
    centers.append(right_c); contexts.append(right_ctx)
centers = np.concatenate(centers)
contexts = np.concatenate(contexts)
mask = centers != 0  # drop <unk>-centered pairs - no useful signal to train on
centers, contexts = centers[mask], contexts[mask]
print(f"Training pairs: {len(centers):,}")

# ---------- 4. Train skip-gram model ----------
train_model = tf.keras.Sequential([
    tf.keras.layers.Embedding(vocab_size, EMBED_DIM, name="embedding"),
    tf.keras.layers.Dense(vocab_size),  # logits over vocab for the context word
])
train_model.compile(
    optimizer=tf.keras.optimizers.Adam(1e-3),
    loss=tf.keras.losses.SparseCategoricalCrossentropy(from_logits=True),
)
train_model.fit(centers, contexts, batch_size=BATCH_SIZE, epochs=EPOCHS, verbose=2)

embedding_weights = train_model.get_layer("embedding").get_weights()[0]
print("Embedding matrix shape:", embedding_weights.shape)

# ---------- 5. Sanity check on real biology relationships ----------
def cos_sim(a, b):
    a = a / (np.linalg.norm(a) + 1e-8)
    b = b / (np.linalg.norm(b) + 1e-8)
    return float(np.dot(a, b))

def sim(w1, w2):
    if w1 not in word_to_id or w2 not in word_to_id:
        return None
    return cos_sim(embedding_weights[word_to_id[w1]], embedding_weights[word_to_id[w2]])

pairs = [
    ("mitochondria", "chloroplast"), ("mitochondria", "ecosystem"),
    ("gene", "chromosome"), ("gene", "kidney"),
    ("artery", "vein"), ("artery", "photosynthesis"),
    ("predator", "prey"), ("predator", "enzyme"),
]
print("\nSanity check (related pair should usually score higher than the unrelated one):")
for w1, w2 in pairs:
    s = sim(w1, w2)
    print(f"  sim({w1}, {w2}) = {s}")

# ---------- 6. Build export-only inference graph: single-token lookup + L2 norm ----------
token_input = tf.keras.Input(shape=(1,), dtype=tf.int32, name="token_id")
embedded = tf.keras.layers.Embedding(
    vocab_size, EMBED_DIM, weights=[embedding_weights], trainable=False, name="embedding"
)(token_input)
flat = tf.keras.layers.Reshape((EMBED_DIM,))(embedded)
normalized = tf.keras.layers.Lambda(
    lambda x: tf.math.l2_normalize(x, axis=-1), name="l2_normalize"
)(flat)
export_model = tf.keras.Model(token_input, normalized, name="biology_term_embedder")
export_model.summary()

# ---------- 7. Convert to TFLite (standard ops only - no SELECT_TF_OPS) ----------
converter = tf.lite.TFLiteConverter.from_keras_model(export_model)
converter.target_spec.supported_ops = [tf.lite.OpsSet.TFLITE_BUILTINS]
tflite_model = converter.convert()

ASSETS_DIR.mkdir(parents=True, exist_ok=True)
tflite_path = ASSETS_DIR / "biology_term_embedder.tflite"
tflite_path.write_bytes(tflite_model)
print(f"\nWrote {tflite_path} ({len(tflite_model):,} bytes)")

vocab_path = ASSETS_DIR / "biology_vocab.txt"
vocab_path.write_text("\n".join(vocab), encoding="utf-8")
print(f"Wrote {vocab_path} ({vocab_size:,} words)")

meta_path = HERE / "embedder_meta.json"
meta_path.write_text(json.dumps({
    "vocab_size": vocab_size, "embed_dim": EMBED_DIM, "window": WINDOW,
    "min_count": MIN_COUNT, "training_pairs": int(len(centers)),
    "corpus_tokens": len(tokens), "epochs": EPOCHS, "seed": SEED,
}, indent=2))
print(f"Wrote {meta_path}")
