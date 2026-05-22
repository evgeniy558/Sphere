"""
Export trained NodeX Vocal model to ONNX format for production inference.

Usage:
    python3 export_onnx.py --checkpoint checkpoints/nodex_vocal_best.pth --output models/nodex_vocal.onnx
"""

import argparse

import torch

from model import NodeXVocalNet, FREQ_BINS


def main():
    parser = argparse.ArgumentParser(description="Export NodeX Vocal to ONNX")
    parser.add_argument("--checkpoint", required=True, help="Path to .pth checkpoint")
    parser.add_argument("--output", required=True, help="Output .onnx path")
    parser.add_argument("--opset", type=int, default=17, help="ONNX opset version")
    args = parser.parse_args()

    model = NodeXVocalNet()

    # Load trained weights
    checkpoint = torch.load(args.checkpoint, map_location="cpu", weights_only=True)
    model.load_state_dict(checkpoint["model_state_dict"])
    model.eval()

    # Dummy input: (batch=1, channels=1, freq_bins=1025, time_frames=256)
    # Time frames is dynamic in production.
    dummy = torch.randn(1, 1, FREQ_BINS, 256)

    torch.onnx.export(
        model,
        dummy,
        args.output,
        input_names=["spectrogram"],
        output_names=["vocal_mask"],
        dynamic_axes={
            "spectrogram": {0: "batch", 3: "time_frames"},
            "vocal_mask": {0: "batch", 3: "time_frames"},
        },
        opset_version=args.opset,
        do_constant_folding=True,
    )

    import os
    size_mb = os.path.getsize(args.output) / (1024 * 1024)
    print(f"Exported to {args.output} ({size_mb:.1f} MB)")
    print(f"ONNX opset version: {args.opset}")


if __name__ == "__main__":
    main()
