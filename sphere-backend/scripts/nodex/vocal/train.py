"""
NodeX Vocal — training script.

Usage:
    python3 train.py --epochs 100 --output ./checkpoints/
    python3 train.py --epochs 1 --quick-test  # fast smoke test
"""

import argparse
import os
import time

import torch
import torch.nn as nn
import torch.optim as optim
from torch.utils.data import DataLoader, random_split

from model import NodeXVocalNet, FREQ_BINS, count_parameters
from dataset import MUSDB18Dataset


class SyntheticVocalDataset(torch.utils.data.Dataset):
    """Generates synthetic spectrogram pairs for training without MUSDB18.

    Simulates a mix spectrogram and a vocal mask. Useful for validating
    the full training pipeline and exporting a working ONNX model.
    """

    def __init__(self, size=500, time_frames=256):
        self.size = size
        self.time_frames = time_frames

    def __len__(self):
        return self.size

    def __getitem__(self, idx):
        # Simulate mix spectrogram: random noise + harmonic structure
        t = torch.linspace(0, 1, self.time_frames).unsqueeze(0)  # (1, T)
        f = torch.linspace(0, 1, FREQ_BINS).unsqueeze(1)          # (F, 1)
        harmonic = 0.3 * torch.sin(2 * 3.14159 * 4 * f) * torch.cos(2 * 3.14159 * 2 * t)
        noise = 0.1 * torch.randn(FREQ_BINS, self.time_frames)
        mix = (harmonic + noise + 0.5).clamp(0, 1).unsqueeze(0)   # (1, F, T)

        # Simulate vocal mask: concentrated in mid-frequencies (200-4000 Hz range)
        center = FREQ_BINS // 4
        width = FREQ_BINS // 6
        gaussian = torch.exp(-((torch.arange(FREQ_BINS).float() - center) ** 2) / (2 * width ** 2))
        vocal_mask = gaussian.unsqueeze(1).expand(-1, self.time_frames)
        # Add time variation
        vocal_mask = vocal_mask * (0.5 + 0.5 * torch.sin(2 * 3.14159 * 1.5 * t.squeeze()))
        vocal_mask = vocal_mask.clamp(0, 1).unsqueeze(0)  # (1, F, T)

        return mix.float(), vocal_mask.float()


def train_epoch(model, loader, criterion, optimizer, device):
    model.train()
    total_loss = 0.0
    count = 0
    for mix_spec, vocal_mask in loader:
        mix_spec = mix_spec.to(device)
        vocal_mask = vocal_mask.to(device)

        optimizer.zero_grad()
        predicted_mask = model(mix_spec)

        # Ensure shapes match (handle any padding differences)
        min_h = min(predicted_mask.shape[2], vocal_mask.shape[2])
        min_w = min(predicted_mask.shape[3], vocal_mask.shape[3])
        predicted_mask = predicted_mask[:, :, :min_h, :min_w]
        vocal_mask = vocal_mask[:, :, :min_h, :min_w]

        loss = criterion(predicted_mask, vocal_mask)
        loss.backward()
        optimizer.step()

        total_loss += loss.item() * mix_spec.size(0)
        count += mix_spec.size(0)

    return total_loss / max(count, 1)


def validate(model, loader, criterion, device):
    model.eval()
    total_loss = 0.0
    count = 0
    with torch.no_grad():
        for mix_spec, vocal_mask in loader:
            mix_spec = mix_spec.to(device)
            vocal_mask = vocal_mask.to(device)

            predicted_mask = model(mix_spec)

            min_h = min(predicted_mask.shape[2], vocal_mask.shape[2])
            min_w = min(predicted_mask.shape[3], vocal_mask.shape[3])
            predicted_mask = predicted_mask[:, :, :min_h, :min_w]
            vocal_mask = vocal_mask[:, :, :min_h, :min_w]

            loss = criterion(predicted_mask, vocal_mask)
            total_loss += loss.item() * mix_spec.size(0)
            count += mix_spec.size(0)

    return total_loss / max(count, 1)


def main():
    parser = argparse.ArgumentParser(description="Train NodeX Vocal model")
    parser.add_argument("--epochs", type=int, default=100)
    parser.add_argument("--batch-size", type=int, default=8)
    parser.add_argument("--lr", type=float, default=1e-4)
    parser.add_argument("--musdb-root", type=str, default="./musdb18")
    parser.add_argument("--output", type=str, default="./checkpoints")
    parser.add_argument("--samples-per-epoch", type=int, default=2000)
    parser.add_argument("--quick-test", action="store_true",
                        help="Run 1 epoch with tiny dataset for smoke testing")
    parser.add_argument("--synthetic", action="store_true",
                        help="Use synthetic spectrogram data (no MUSDB18 needed)")
    args = parser.parse_args()

    device = torch.device("cuda" if torch.cuda.is_available() else
                          "mps" if torch.backends.mps.is_available() else "cpu")
    print(f"NodeX Vocal Training — device: {device}")

    # Model
    model = NodeXVocalNet().to(device)
    print(f"Parameters: {count_parameters(model):,}")

    # Dataset
    if args.synthetic:
        print("Using synthetic spectrogram data for training...")
        samples = 20 if args.quick_test else min(args.samples_per_epoch, 500)
        dataset = SyntheticVocalDataset(samples)
    else:
        samples = 20 if args.quick_test else args.samples_per_epoch
        dataset = MUSDB18Dataset(
            root=args.musdb_root,
            split="train",
            samples_per_epoch=samples,
            augment=not args.quick_test,
        )

    # Split train/val (80/20)
    val_size = max(1, int(len(dataset) * 0.2))
    train_size = len(dataset) - val_size
    train_ds, val_ds = random_split(dataset, [train_size, val_size])

    train_loader = DataLoader(train_ds, batch_size=args.batch_size,
                              shuffle=True, num_workers=0, pin_memory=True)
    val_loader = DataLoader(val_ds, batch_size=args.batch_size,
                            shuffle=False, num_workers=0, pin_memory=True)

    # Training setup
    criterion = nn.L1Loss()
    optimizer = optim.Adam(model.parameters(), lr=args.lr, weight_decay=1e-5)
    scheduler = optim.lr_scheduler.ReduceLROnPlateau(
        optimizer, mode="min", patience=5, factor=0.5,
    )

    os.makedirs(args.output, exist_ok=True)
    best_val_loss = float("inf")
    epochs = 1 if args.quick_test else args.epochs

    for epoch in range(1, epochs + 1):
        t0 = time.time()
        train_loss = train_epoch(model, train_loader, criterion, optimizer, device)
        val_loss = validate(model, val_loader, criterion, device)
        scheduler.step(val_loss)
        elapsed = time.time() - t0

        lr = optimizer.param_groups[0]["lr"]
        print(f"Epoch {epoch:3d}/{epochs} | "
              f"train_loss={train_loss:.5f} | val_loss={val_loss:.5f} | "
              f"lr={lr:.2e} | {elapsed:.1f}s")

        if val_loss < best_val_loss:
            best_val_loss = val_loss
            path = os.path.join(args.output, "nodex_vocal_best.pth")
            torch.save({
                "epoch": epoch,
                "model_state_dict": model.state_dict(),
                "optimizer_state_dict": optimizer.state_dict(),
                "val_loss": val_loss,
            }, path)
            print(f"  -> Saved best model (val_loss={val_loss:.5f})")

    # Save final model
    path = os.path.join(args.output, "nodex_vocal_final.pth")
    torch.save({
        "epoch": epochs,
        "model_state_dict": model.state_dict(),
        "val_loss": val_loss,
    }, path)
    print(f"\nTraining complete. Best val_loss={best_val_loss:.5f}")
    print(f"Checkpoints saved to {args.output}/")


if __name__ == "__main__":
    main()
