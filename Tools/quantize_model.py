#!/usr/bin/env python3
"""Quantize the converted PhonemeCTC.mlpackage weights to int8.

Operates directly on the saved mlprogram package — no torch or re-tracing
needed. Writes PhonemeCTC_int8.mlpackage next to the original; swap it in
after validating recognition quality with the regression script.
"""
import coremltools as ct
import coremltools.optimize.coreml as cto

SRC = "../Resources/PhonemeCTC.mlpackage"
DST = "../Resources/PhonemeCTC_int8.mlpackage"

print("loading fp16 model…", flush=True)
model = ct.models.MLModel(SRC, compute_units=ct.ComputeUnit.CPU_ONLY)

config = cto.OptimizationConfig(
    global_config=cto.OpLinearQuantizerConfig(
        mode="linear_symmetric",
        dtype="int8",
        granularity="per_channel",
    )
)

print("quantizing weights to int8…", flush=True)
quantized = cto.linear_quantize_weights(model, config=config)
quantized.save(DST)
print(f"saved {DST}", flush=True)
