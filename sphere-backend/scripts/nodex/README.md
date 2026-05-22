# NodeX — Sphere AI Engine

Two neural networks powering Sphere's intelligent features.

## NodeX Vocal (Karaoke)

U-Net spectrogram masking network for vocal removal.
- Architecture: 6-layer encoder/decoder with skip connections
- ~8M parameters, ~30MB ONNX model
- Input: magnitude spectrogram → Output: vocal mask [0, 1]
- Instrumental = spectrogram × (1 - mask)

### Training

```bash
cd scripts/nodex/vocal
pip install -r requirements.txt
# Download MUSDB18 dataset (150 multi-track songs)
python3 train.py --musdb-root ./musdb18 --epochs 100 --output ./checkpoints/
python3 export_onnx.py --checkpoint ./checkpoints/nodex_vocal_best.pth --output ../../models/nodex_vocal.onnx
```

### Inference

```bash
python3 inference.py --input track.mp3 --output instrumental.mp3 --model ../../models/nodex_vocal.onnx
```

## NodeX Wave (Recommendations)

Context-aware MLP for personalized track scoring.
- Architecture: 4-layer MLP (50 → 128 → 64 → 32 → 1)
- ~50K parameters, ~200KB ONNX model
- Input: 50-dim feature vector (track + context + user prefs)
- Output: score [0, 1] predicting track relevance

### Features (50 dimensions)

| Group | Count | Description |
|-------|-------|-------------|
| Track | 12 | energy, valence, tempo, danceability, 8-dim genre vector |
| Context | 16 | time encoding, recent mood, session stats, day period |
| User | 22 | genre weights, audio prefs, match scores, provider weights |

### Training

```bash
cd scripts/nodex/wave
pip install -r requirements.txt
# With real data:
python3 train.py --db-url "postgres://..." --epochs 50 --output ./checkpoints/
# Smoke test with synthetic data:
python3 train.py --synthetic --epochs 5
python3 export_onnx.py --checkpoint ./checkpoints/nodex_wave_best.pth --output ../../models/nodex_wave.onnx
```
