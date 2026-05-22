"""
NodeX Wave — MLP neural network for context-aware track recommendation.

Takes 50 features (track audio features, user context, preferences)
and outputs a score [0, 1] predicting how well the track fits the user right now.
"""

import torch
import torch.nn as nn


# Feature group sizes
TRACK_FEATURES = 12     # energy, valence, tempo, danceability + 8-dim genre vector
CONTEXT_FEATURES = 16   # time encoding, recent mood, session stats
USER_FEATURES = 22      # preferences, match scores, history signals
TOTAL_FEATURES = TRACK_FEATURES + CONTEXT_FEATURES + USER_FEATURES  # 50


class NodeXWaveNet(nn.Module):
    """
    Context-aware track scoring MLP.

    ~50K parameters, ~200KB ONNX.
    Input:  (batch, 50) — feature vector
    Output: (batch, 1)  — score [0, 1]
    """

    def __init__(self, input_dim=TOTAL_FEATURES):
        super().__init__()
        self.net = nn.Sequential(
            nn.Linear(input_dim, 128),
            nn.BatchNorm1d(128),
            nn.ReLU(inplace=True),
            nn.Dropout(0.3),

            nn.Linear(128, 64),
            nn.BatchNorm1d(64),
            nn.ReLU(inplace=True),
            nn.Dropout(0.2),

            nn.Linear(64, 32),
            nn.BatchNorm1d(32),
            nn.ReLU(inplace=True),

            nn.Linear(32, 1),
            nn.Sigmoid(),
        )

    def forward(self, x):
        return self.net(x)


def count_parameters(model):
    return sum(p.numel() for p in model.parameters() if p.requires_grad)


if __name__ == "__main__":
    net = NodeXWaveNet()
    print(f"NodeX Wave — {count_parameters(net):,} trainable parameters")
    dummy = torch.randn(16, TOTAL_FEATURES)
    out = net(dummy)
    print(f"Input: {dummy.shape} → Output: {out.shape}")
    assert out.shape == (16, 1), "Shape mismatch!"
    assert (out >= 0).all() and (out <= 1).all(), "Output out of [0,1] range!"
    print("Model OK.")
