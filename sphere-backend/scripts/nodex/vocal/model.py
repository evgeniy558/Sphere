"""
NodeX Vocal — U-Net neural network for vocal removal (karaoke mode).

Architecture: spectrogram masking U-Net.
Input:  magnitude spectrogram (1, freq_bins, time_frames)
Output: vocal mask [0, 1] of the same shape.
Instrumental = magnitude * (1 - mask), then ISTFT with original phase.
"""

import torch
import torch.nn as nn


# STFT parameters (shared across training and inference)
SAMPLE_RATE = 44100
N_FFT = 2048
HOP_LENGTH = 512
FREQ_BINS = N_FFT // 2 + 1  # 1025


class EncoderBlock(nn.Module):
    def __init__(self, in_ch, out_ch, kernel=5, stride=2, padding=2):
        super().__init__()
        self.conv = nn.Conv2d(in_ch, out_ch, kernel, stride=stride, padding=padding)
        self.bn = nn.BatchNorm2d(out_ch)
        self.act = nn.LeakyReLU(0.2, inplace=True)

    def forward(self, x):
        return self.act(self.bn(self.conv(x)))


class DecoderBlock(nn.Module):
    def __init__(self, in_ch, out_ch, kernel=5, stride=2, padding=2,
                 output_padding=1, dropout=0.0):
        super().__init__()
        self.deconv = nn.ConvTranspose2d(
            in_ch, out_ch, kernel, stride=stride,
            padding=padding, output_padding=output_padding,
        )
        self.bn = nn.BatchNorm2d(out_ch)
        self.act = nn.ReLU(inplace=True)
        self.drop = nn.Dropout2d(dropout) if dropout > 0 else nn.Identity()

    def forward(self, x, skip):
        out = self.act(self.bn(self.deconv(x)))
        out = self.drop(out)
        if out.shape != skip.shape:
            diff_h = skip.shape[2] - out.shape[2]
            diff_w = skip.shape[3] - out.shape[3]
            out = nn.functional.pad(out, [0, diff_w, 0, diff_h])
        return torch.cat([out, skip], dim=1)


class NodeXVocalNet(nn.Module):
    """
    U-Net for spectrogram vocal masking.

    ~8M parameters, ~30MB ONNX.
    Input:  (batch, 1, 1025, T)   — magnitude spectrogram
    Output: (batch, 1, 1025, T)   — vocal mask [0, 1]
    """

    def __init__(self):
        super().__init__()

        # Encoder
        self.enc1 = EncoderBlock(1, 16)
        self.enc2 = EncoderBlock(16, 32)
        self.enc3 = EncoderBlock(32, 64)
        self.enc4 = EncoderBlock(64, 128)
        self.enc5 = EncoderBlock(128, 256)
        self.enc6 = EncoderBlock(256, 512)

        # Bottleneck
        self.bottleneck = nn.Sequential(
            nn.Conv2d(512, 512, 5, padding=2),
            nn.BatchNorm2d(512),
            nn.LeakyReLU(0.2, inplace=True),
        )

        # Decoder (input channels are doubled because of skip concatenation)
        self.dec6 = DecoderBlock(512, 256, dropout=0.5)
        self.dec5 = DecoderBlock(512, 128, dropout=0.5)
        self.dec4 = DecoderBlock(256, 64)
        self.dec3 = DecoderBlock(128, 32)
        self.dec2 = DecoderBlock(64, 16)

        # Final layer — no skip concat, just upsample to original size
        self.dec1 = nn.ConvTranspose2d(32, 1, 5, stride=2, padding=2, output_padding=1)
        self.sigmoid = nn.Sigmoid()

    def forward(self, x):
        # Pad input to be divisible by 2^6 = 64
        _, _, h, w = x.shape
        pad_h = (64 - h % 64) % 64
        pad_w = (64 - w % 64) % 64
        if pad_h > 0 or pad_w > 0:
            x = nn.functional.pad(x, [0, pad_w, 0, pad_h])

        # Encoder
        e1 = self.enc1(x)
        e2 = self.enc2(e1)
        e3 = self.enc3(e2)
        e4 = self.enc4(e3)
        e5 = self.enc5(e4)
        e6 = self.enc6(e5)

        # Bottleneck
        b = self.bottleneck(e6)

        # Decoder with skip connections
        d6 = self.dec6(b, e5)
        d5 = self.dec5(d6, e4)
        d4 = self.dec4(d5, e3)
        d3 = self.dec3(d4, e2)
        d2 = self.dec2(d3, e1)

        # Final
        out = self.sigmoid(self.dec1(d2))

        # Remove padding
        if pad_h > 0 or pad_w > 0:
            out = out[:, :, :h, :w]

        return out


def count_parameters(model):
    return sum(p.numel() for p in model.parameters() if p.requires_grad)


if __name__ == "__main__":
    net = NodeXVocalNet()
    print(f"NodeX Vocal — {count_parameters(net):,} trainable parameters")
    dummy = torch.randn(1, 1, FREQ_BINS, 256)
    out = net(dummy)
    print(f"Input: {dummy.shape} → Output: {out.shape}")
    assert out.shape == dummy.shape, "Shape mismatch!"
    print("Model OK.")
