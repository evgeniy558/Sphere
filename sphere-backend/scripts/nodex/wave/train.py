"""
NodeX Wave — training script.

Usage:
    python3 train.py --db-url "postgres://..." --output ./checkpoints/ --epochs 50
    python3 train.py --synthetic --epochs 5  # smoke test with synthetic data
"""

import argparse
import os
import time

import numpy as np
import torch
import torch.nn as nn
import torch.optim as optim
from torch.utils.data import DataLoader, TensorDataset, random_split

from model import NodeXWaveNet, TOTAL_FEATURES, count_parameters


def generate_synthetic_data(n=5000):
    """Generate synthetic training data for smoke testing."""
    features = np.random.randn(n, TOTAL_FEATURES).astype(np.float32)

    # Synthetic label: tracks with high energy + evening context get high scores
    energy = features[:, 0]
    evening_flag = features[:, 26]  # is_evening (approx position)
    base = 0.5 + 0.2 * energy + 0.15 * evening_flag
    noise = np.random.randn(n) * 0.1
    labels = np.clip(base + noise, 0, 1).astype(np.float32)

    return features, labels


def train_epoch(model, loader, criterion, optimizer, device):
    model.train()
    total_loss, count = 0.0, 0
    for feats, labels in loader:
        feats, labels = feats.to(device), labels.to(device).unsqueeze(1)
        optimizer.zero_grad()
        preds = model(feats)
        loss = criterion(preds, labels)
        loss.backward()
        optimizer.step()
        total_loss += loss.item() * feats.size(0)
        count += feats.size(0)
    return total_loss / max(count, 1)


def validate(model, loader, criterion, device):
    model.eval()
    total_loss, count = 0.0, 0
    with torch.no_grad():
        for feats, labels in loader:
            feats, labels = feats.to(device), labels.to(device).unsqueeze(1)
            loss = criterion(model(feats), labels)
            total_loss += loss.item() * feats.size(0)
            count += feats.size(0)
    return total_loss / max(count, 1)


def main():
    parser = argparse.ArgumentParser(description="Train NodeX Wave model")
    parser.add_argument("--db-url", type=str, default="")
    parser.add_argument("--epochs", type=int, default=50)
    parser.add_argument("--batch-size", type=int, default=256)
    parser.add_argument("--lr", type=float, default=3e-4)
    parser.add_argument("--output", type=str, default="./checkpoints")
    parser.add_argument("--synthetic", action="store_true")
    args = parser.parse_args()

    device = torch.device("cuda" if torch.cuda.is_available() else
                          "mps" if torch.backends.mps.is_available() else "cpu")
    print(f"NodeX Wave Training — device: {device}")

    if args.synthetic or not args.db_url:
        print("Using synthetic data.")
        features, labels = generate_synthetic_data(5000)
    else:
        from features import extract_training_data
        print("Extracting from DB...")
        features, labels = extract_training_data(args.db_url)
        if len(features) == 0:
            print("No data. Falling back to synthetic.")
            features, labels = generate_synthetic_data(5000)

    print(f"Samples: {len(features)}")

    model = NodeXWaveNet().to(device)
    print(f"Parameters: {count_parameters(model):,}")

    dataset = TensorDataset(torch.from_numpy(features), torch.from_numpy(labels))
    val_size = max(1, int(len(dataset) * 0.2))
    train_ds, val_ds = random_split(dataset, [len(dataset) - val_size, val_size])
    train_loader = DataLoader(train_ds, batch_size=args.batch_size, shuffle=True)
    val_loader = DataLoader(val_ds, batch_size=args.batch_size)

    criterion = nn.BCELoss()
    optimizer = optim.Adam(model.parameters(), lr=args.lr)
    scheduler = optim.lr_scheduler.ReduceLROnPlateau(optimizer, patience=10, factor=0.5)

    os.makedirs(args.output, exist_ok=True)
    best_val = float("inf")

    for epoch in range(1, args.epochs + 1):
        t0 = time.time()
        tl = train_epoch(model, train_loader, criterion, optimizer, device)
        vl = validate(model, val_loader, criterion, device)
        scheduler.step(vl)
        print(f"Epoch {epoch:3d}/{args.epochs} | train={tl:.5f} | val={vl:.5f} | {time.time()-t0:.1f}s")

        if vl < best_val:
            best_val = vl
            torch.save({"epoch": epoch, "model_state_dict": model.state_dict(),
                         "val_loss": vl}, os.path.join(args.output, "nodex_wave_best.pth"))
            print(f"  -> Best model saved (val={vl:.5f})")

    print(f"\nDone. Best val_loss={best_val:.5f}")


if __name__ == "__main__":
    main()
