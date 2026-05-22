"""
NodeX Vocal dataset — loads MUSDB18 stems and produces spectrogram pairs.
"""

import random
import numpy as np
import torch
from torch.utils.data import Dataset

from model import N_FFT, HOP_LENGTH, SAMPLE_RATE

CHUNK_DURATION = 5.0  # seconds per training sample
CHUNK_SAMPLES = int(CHUNK_DURATION * SAMPLE_RATE)


def stft_magnitude(audio_np):
    """Compute magnitude spectrogram from mono audio numpy array."""
    spec = np.abs(
        np.fft.rfft(
            np.lib.stride_tricks.sliding_window_view(
                np.pad(audio_np, (N_FFT // 2, N_FFT // 2)),
                N_FFT,
            )[::HOP_LENGTH]
            * np.hanning(N_FFT),
            axis=-1,
        )
    ).T  # (freq_bins, time_frames)
    return spec.astype(np.float32)


def compute_stft(audio_np):
    """Compute STFT magnitude using librosa-style approach."""
    try:
        import librosa
        S = np.abs(librosa.stft(audio_np, n_fft=N_FFT, hop_length=HOP_LENGTH))
        return S.astype(np.float32)
    except ImportError:
        return stft_magnitude(audio_np)


class MUSDB18Dataset(Dataset):
    """
    Loads MUSDB18 dataset and returns (mix_spectrogram, vocal_mask) pairs.

    Each item is a random 5-second chunk from a random track.
    mix_spec:   (1, freq_bins, time_frames)
    vocal_mask: (1, freq_bins, time_frames) — values in [0, 1]
    """

    def __init__(self, root="./musdb18", split="train", samples_per_epoch=2000,
                 augment=True):
        try:
            import musdb
        except ImportError:
            raise ImportError("pip install musdb musdb-hq")

        self.db = musdb.DB(root=root, subsets=split, is_wav=False)
        self.samples_per_epoch = samples_per_epoch
        self.augment = augment

    def __len__(self):
        return self.samples_per_epoch

    def __getitem__(self, idx):
        track = random.choice(self.db.tracks)

        # Random start position
        max_start = max(0, track.audio.shape[0] - CHUNK_SAMPLES)
        start = random.randint(0, max_start) if max_start > 0 else 0
        end = start + CHUNK_SAMPLES

        # Load stems
        mix = track.audio[start:end]       # (samples, 2) stereo
        vocals = track.targets["vocals"].audio[start:end]

        # Convert to mono
        mix_mono = np.mean(mix, axis=1).astype(np.float32)
        vocal_mono = np.mean(vocals, axis=1).astype(np.float32)

        # Data augmentation
        if self.augment:
            # Random gain ±6dB
            gain = 10 ** (random.uniform(-6, 6) / 20.0)
            mix_mono *= gain
            vocal_mono *= gain

        # Compute spectrograms
        mix_spec = compute_stft(mix_mono)
        vocal_spec = compute_stft(vocal_mono)

        # Compute vocal mask: vocal_magnitude / (mix_magnitude + eps)
        eps = 1e-7
        vocal_mask = np.clip(vocal_spec / (mix_spec + eps), 0.0, 1.0)

        # Normalize mix spectrogram
        mix_max = mix_spec.max() + eps
        mix_spec_norm = mix_spec / mix_max

        # Convert to tensors with channel dim
        mix_tensor = torch.from_numpy(mix_spec_norm).unsqueeze(0)    # (1, F, T)
        mask_tensor = torch.from_numpy(vocal_mask).unsqueeze(0)      # (1, F, T)

        return mix_tensor, mask_tensor


if __name__ == "__main__":
    print("Testing dataset loader...")
    try:
        ds = MUSDB18Dataset(samples_per_epoch=2)
        mix, mask = ds[0]
        print(f"Mix spectrogram: {mix.shape}, Vocal mask: {mask.shape}")
        print(f"Mix range: [{mix.min():.4f}, {mix.max():.4f}]")
        print(f"Mask range: [{mask.min():.4f}, {mask.max():.4f}]")
    except ImportError as e:
        print(f"MUSDB18 not available: {e}")
        print("Install with: pip install musdb")
