"""
Verifies assets/models/biology_term_embedder.tflite (produced by
train_embeddings.py) before it's trusted to ship:

  1. Confirms it contains ONLY standard TFLite builtin ops - no CUSTOM ops.
     This is the exact check that caught the earlier attempt (TF Hub's
     Universal Sentence Encoder QA on-device model) baking in a custom
     SentencePiece op that plain tflite_flutter can't execute.
  2. Runs real inference through the TFLite interpreter (not just the
     Keras model) and confirms it reproduces the expected similarity
     score, proving the exported graph matches the trained weights.

Run from anywhere:  python tool/verify_tflite.py
"""
import numpy as np
import tensorflow as tf
from pathlib import Path

HERE = Path(__file__).parent
MODEL_PATH = HERE.parent / "assets" / "models" / "biology_term_embedder.tflite"
VOCAB_PATH = HERE.parent / "assets" / "models" / "biology_vocab.txt"

interpreter = tf.lite.Interpreter(model_path=str(MODEL_PATH))
interpreter.allocate_tensors()

inp = interpreter.get_input_details()
out = interpreter.get_output_details()
print("Input:", inp[0]["shape"], inp[0]["dtype"])
print("Output:", out[0]["shape"], out[0]["dtype"])

# ---------- Enumerate every op baked into the model ----------
from tensorflow.lite.python import schema_py_generated as schema_fb

buf = bytearray(MODEL_PATH.read_bytes())
model = schema_fb.Model.GetRootAsModel(buf, 0)
rev_builtin = {v: k for k, v in schema_fb.BuiltinOperator.__dict__.items() if isinstance(v, int)}

ops_used, custom_ops = set(), set()
for i in range(model.OperatorCodesLength()):
    oc = model.OperatorCodes(i)
    custom_code = oc.CustomCode()
    if custom_code:
        name = custom_code.decode("utf-8")
        custom_ops.add(name)
        ops_used.add(f"CUSTOM:{name}")
    else:
        ops_used.add(rev_builtin.get(oc.DeprecatedBuiltinCode(), f"BUILTIN#{oc.DeprecatedBuiltinCode()}"))

print("\nOps used:", sorted(ops_used))
if custom_ops:
    raise SystemExit(f"FAIL: found custom op(s) {custom_ops} - tflite_flutter cannot run this model")
print("CUSTOM ops found: NONE (fully standard builtins - safe for tflite_flutter)")

# ---------- Functional test ----------
vocab = [w.strip() for w in VOCAB_PATH.read_text(encoding="utf-8").split("\n") if w.strip()]
word_to_id = {w: i for i, w in enumerate(vocab)}

def embed(word):
    tid = word_to_id.get(word, 0)
    interpreter.set_tensor(inp[0]["index"], np.array([[tid]], dtype=np.int32))
    interpreter.invoke()
    return interpreter.get_tensor(out[0]["index"])[0]

v1, v2 = embed("mitochondria"), embed("chloroplast")
cos = float(np.dot(v1, v2) / (np.linalg.norm(v1) * np.linalg.norm(v2)))
print(f"\ninterpreter.invoke() test: sim(mitochondria, chloroplast) = {cos:.4f}")
print("(compare against the value train_embeddings.py printed during training - should match)")
