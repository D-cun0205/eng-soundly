#!/usr/bin/env python3
"""Convert facebook/wav2vec2-lv-60-espeak-cv-ft (phoneme CTC) to Core ML.

Outputs:
  ../Resources/PhonemeCTC.mlpackage   — FP16 mlprogram, audio [1, N] float32 @16kHz → logits [1, T, V]
  ../Resources/phoneme_vocab.json     — token → id vocabulary for CTC decoding
"""
import json
import os
import sys

import numpy as np
import torch

MODEL_ID = "facebook/wav2vec2-lv-60-espeak-cv-ft"
OUT_DIR = os.path.join(os.path.dirname(__file__), "..", "Resources")
DEFAULT_LEN = 80_000  # 5 s @ 16 kHz


def main():
    from huggingface_hub import hf_hub_download
    from transformers import Wav2Vec2ForCTC
    import coremltools as ct

    print("loading model…", flush=True)
    model = Wav2Vec2ForCTC.from_pretrained(MODEL_ID)
    model.eval()
    model.config.return_dict = False

    # Fetch vocab.json directly — the phoneme tokenizer needs the `phonemizer`
    # package (espeak backend) which we don't need just for the id→token map.
    vocab_path = hf_hub_download(MODEL_ID, "vocab.json")
    with open(vocab_path, encoding="utf-8") as f:
        vocab = json.load(f)
    os.makedirs(OUT_DIR, exist_ok=True)
    with open(os.path.join(OUT_DIR, "phoneme_vocab.json"), "w", encoding="utf-8") as f:
        json.dump(vocab, f, ensure_ascii=False, indent=1)
    print(f"vocab saved ({len(vocab)} tokens)", flush=True)

    class Wrapper(torch.nn.Module):
        def __init__(self, m):
            super().__init__()
            self.m = m

        def forward(self, audio):
            out = self.m(audio)
            return out[0] if isinstance(out, tuple) else out.logits

    wrapper = Wrapper(model).eval()
    example = torch.zeros(1, DEFAULT_LEN, dtype=torch.float32)

    print("tracing…", flush=True)
    with torch.no_grad():
        traced = torch.jit.trace(wrapper, example, strict=False)

    def convert(shape):
        return ct.convert(
            traced,
            inputs=[ct.TensorType(name="audio", shape=shape, dtype=np.float32)],
            outputs=[ct.TensorType(name="logits", dtype=np.float32)],
            minimum_deployment_target=ct.target.iOS17,
            compute_precision=ct.precision.FLOAT16,
            convert_to="mlprogram",
        )

    print("converting (flexible shape)…", flush=True)
    try:
        flexible = ct.Shape(shape=(1, ct.RangeDim(4_000, 160_000, default=DEFAULT_LEN)))
        mlmodel = convert(flexible)
        mode = "flexible"
    except Exception as e:
        print(f"flexible-shape conversion failed ({type(e).__name__}: {e}); retrying fixed shape", flush=True)
        mlmodel = convert((1, DEFAULT_LEN))
        mode = f"fixed:{DEFAULT_LEN}"

    out_path = os.path.join(OUT_DIR, "PhonemeCTC.mlpackage")
    mlmodel.save(out_path)
    with open(os.path.join(OUT_DIR, "phoneme_model_info.json"), "w") as f:
        json.dump({"model": MODEL_ID, "input_mode": mode, "default_len": DEFAULT_LEN,
                   "normalize": True, "sample_rate": 16000}, f, indent=1)
    print(f"saved {out_path} (input mode: {mode})", flush=True)

    # Smoke test: run 1 s of noise through the converted model.
    print("smoke test…", flush=True)
    test_len = DEFAULT_LEN if mode.startswith("fixed") else 16_000
    x = np.random.randn(1, test_len).astype(np.float32)
    x = (x - x.mean()) / (x.std() + 1e-7)
    pred = mlmodel.predict({"audio": x})
    logits = pred["logits"]
    print(f"logits shape: {logits.shape} — OK", flush=True)


if __name__ == "__main__":
    sys.exit(main())
