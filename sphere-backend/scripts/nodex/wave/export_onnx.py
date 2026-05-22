"""
Export NodeX Wave model to ONNX.

Usage:
    python3 export_onnx.py --checkpoint checkpoints/nodex_wave_best.pth --output models/nodex_wave.onnx
"""

import argparse
import os

import torch
from model import NodeXWaveNet, TOTAL_FEATURES


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--checkpoint", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--opset", type=int, default=17)
    args = parser.parse_args()

    model = NodeXWaveNet()
    ckpt = torch.load(args.checkpoint, map_location="cpu", weights_only=True)
    model.load_state_dict(ckpt["model_state_dict"])
    model.eval()

    dummy = torch.randn(1, TOTAL_FEATURES)

    torch.onnx.export(
        model, dummy, args.output,
        input_names=["features"],
        output_names=["score"],
        dynamic_axes={"features": {0: "batch"}, "score": {0: "batch"}},
        opset_version=args.opset,
        do_constant_folding=True,
    )

    size_kb = os.path.getsize(args.output) / 1024
    print(f"Exported to {args.output} ({size_kb:.1f} KB)")


if __name__ == "__main__":
    main()
