"""
NodeX Vocal — inference script (ONNX Runtime).

CLI for Go subprocess: reads audio, removes vocals, writes instrumental.

Usage:
    python3 inference.py --input track.mp3 --output instrumental.mp3 --model nodex_vocal.onnx

Outputs JSON to stdout on success:
    {"status": "ok", "duration_seconds": 240.5, "output": "/tmp/instrumental.mp3"}
"""

import argparse
import json
import os
import sys
import time

import numpy as np
import soundfile as sf

SAMPLE_RATE = 44100
N_FFT = 2048
HOP_LENGTH = 512
CHUNK_SECONDS = 30
OVERLAP_SECONDS = 5


def load_audio(path):
    """Load audio file, resample to 44100 Hz."""
    import librosa
    audio, sr = librosa.load(path, sr=SAMPLE_RATE, mono=False)
    if audio.ndim == 1:
        audio = np.stack([audio, audio])  # mono → pseudo-stereo
    return audio  # (channels, samples)


def stft(audio_1d):
    """Compute STFT magnitude and phase."""
    import librosa
    S = librosa.stft(audio_1d, n_fft=N_FFT, hop_length=HOP_LENGTH)
    magnitude = np.abs(S).astype(np.float32)
    phase = np.angle(S).astype(np.float32)
    return magnitude, phase


def istft(magnitude, phase):
    """Reconstruct audio from magnitude and phase."""
    import librosa
    S = magnitude * np.exp(1j * phase)
    return librosa.istft(S, hop_length=HOP_LENGTH)


def process_channel(audio_1d, session):
    """Process a single audio channel through NodeX Vocal."""
    chunk_samples = CHUNK_SECONDS * SAMPLE_RATE
    overlap_samples = OVERLAP_SECONDS * SAMPLE_RATE
    step = chunk_samples - overlap_samples

    total_samples = len(audio_1d)
    output = np.zeros(total_samples, dtype=np.float32)
    weight = np.zeros(total_samples, dtype=np.float32)

    pos = 0
    while pos < total_samples:
        end = min(pos + chunk_samples, total_samples)
        chunk = audio_1d[pos:end]

        # Pad chunk to full size if needed
        if len(chunk) < chunk_samples:
            chunk = np.pad(chunk, (0, chunk_samples - len(chunk)))

        # STFT
        mag, phase = stft(chunk)

        # Normalize
        eps = 1e-7
        mag_max = mag.max() + eps
        mag_norm = mag / mag_max

        # Prepare input tensor: (1, 1, freq_bins, time_frames)
        input_tensor = mag_norm[np.newaxis, np.newaxis, :, :]

        # ONNX inference — predict vocal mask
        input_name = session.get_inputs()[0].name
        output_name = session.get_outputs()[0].name
        vocal_mask = session.run([output_name], {input_name: input_tensor})[0]
        vocal_mask = vocal_mask[0, 0]  # (freq_bins, time_frames)

        # Ensure mask shape matches magnitude
        vocal_mask = vocal_mask[:mag.shape[0], :mag.shape[1]]

        # Instrumental = magnitude * (1 - vocal_mask)
        instrumental_mag = mag * (1.0 - vocal_mask)

        # ISTFT
        chunk_out = istft(instrumental_mag, phase[:mag.shape[0], :mag.shape[1]])

        # Accumulate with overlap-add
        actual_len = min(len(chunk_out), end - pos)
        output[pos:pos + actual_len] += chunk_out[:actual_len]
        weight[pos:pos + actual_len] += 1.0

        pos += step

    # Normalize overlapping regions
    weight = np.maximum(weight, 1.0)
    return output / weight


def main():
    parser = argparse.ArgumentParser(description="NodeX Vocal — remove vocals")
    parser.add_argument("--input", required=True, help="Input audio file")
    parser.add_argument("--output", required=True, help="Output instrumental file")
    parser.add_argument("--model", required=True, help="ONNX model path")
    args = parser.parse_args()

    if not os.path.exists(args.input):
        print(json.dumps({"status": "error", "message": f"Input not found: {args.input}"}))
        sys.exit(1)

    if not os.path.exists(args.model):
        print(json.dumps({"status": "error", "message": f"Model not found: {args.model}"}))
        sys.exit(1)

    t0 = time.time()

    # Load ONNX model
    import onnxruntime as ort
    session = ort.InferenceSession(args.model, providers=["CPUExecutionProvider"])

    # Load audio
    audio = load_audio(args.input)
    duration = audio.shape[1] / SAMPLE_RATE

    # Process each channel
    channels = []
    for ch in range(audio.shape[0]):
        instrumental_ch = process_channel(audio[ch], session)
        channels.append(instrumental_ch)

    # Stack channels
    instrumental = np.stack(channels)  # (2, samples)

    # Write output
    sf.write(args.output, instrumental.T, SAMPLE_RATE)

    elapsed = time.time() - t0
    result = {
        "status": "ok",
        "duration_seconds": round(duration, 2),
        "processing_seconds": round(elapsed, 2),
        "output": args.output,
    }
    print(json.dumps(result))


if __name__ == "__main__":
    main()
