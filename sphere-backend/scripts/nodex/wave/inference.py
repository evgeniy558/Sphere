"""
NodeX Wave — inference script (ONNX Runtime).

Reads features JSON from stdin, outputs scores JSON to stdout.

Usage:
    echo '{"features": [[0.5, ...], [0.3, ...]]}' | \
    python3 inference.py --model nodex_wave.onnx
"""

import argparse
import json
import sys

import numpy as np


def main():
    parser = argparse.ArgumentParser(description="NodeX Wave inference")
    parser.add_argument("--model", required=True, help="ONNX model path")
    args = parser.parse_args()

    import onnxruntime as ort
    session = ort.InferenceSession(args.model, providers=["CPUExecutionProvider"])
    input_name = session.get_inputs()[0].name
    output_name = session.get_outputs()[0].name

    data = json.loads(sys.stdin.read())
    features = np.array(data["features"], dtype=np.float32)

    if features.ndim == 1:
        features = features.reshape(1, -1)

    scores = session.run([output_name], {input_name: features})[0]
    scores = scores.flatten().tolist()

    print(json.dumps({"scores": scores}))


if __name__ == "__main__":
    main()
