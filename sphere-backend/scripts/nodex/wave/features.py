"""
NodeX Wave — feature extraction from database.

Extracts the 50-dimensional feature vector from:
- Track metadata (energy, valence, tempo, genre)
- User context (time, mood, session)
- User preferences (genre weights, history, favorites)
"""

import math
from dataclasses import dataclass, field
from typing import Optional

import numpy as np

# Genre vocabulary (8 canonical genres)
GENRE_VOCAB = ["pop", "rock", "hiphop", "electronic", "rnb", "jazz", "classical", "other"]
GENRE_TO_IDX = {g: i for i, g in enumerate(GENRE_VOCAB)}

# Provider vocabulary
PROVIDER_VOCAB = ["spotify", "youtube", "deezer", "soundcloud"]
PROVIDER_TO_IDX = {p: i for i, p in enumerate(PROVIDER_VOCAB)}


@dataclass
class TrackFeatures:
    energy: float = 0.5
    valence: float = 0.5
    tempo: float = 120.0
    danceability: float = 0.5
    genres: list = field(default_factory=list)


@dataclass
class UserContext:
    hour: int = 12
    day_of_week: int = 3  # 0=Monday
    recent_energy_avg: float = 0.5
    recent_valence_avg: float = 0.5
    recent_tempo_avg: float = 120.0
    session_skip_rate: float = 0.0
    session_length: int = 0
    hours_since_last_listen: float = 1.0
    tracks_today_count: int = 0


@dataclass
class UserPreferences:
    genre_weights: dict = field(default_factory=dict)  # genre → weight [0,1]
    energy_pref: float = 0.5
    valence_pref: float = 0.5
    tempo_pref: float = 120.0
    provider_weights: dict = field(default_factory=dict)  # provider → weight [0,1]
    genre_match_score: float = 0.0
    artist_match_score: float = 0.0
    novelty_score: float = 1.0
    peer_score: float = 0.0
    days_since_last_play_artist: float = 30.0
    repeat_count_7d: int = 0
    favorite_flag: bool = False


def encode_genre_vector(genres: list) -> np.ndarray:
    """Convert genre list to 8-dim vector."""
    vec = np.zeros(len(GENRE_VOCAB), dtype=np.float32)
    if not genres:
        return vec
    for g in genres:
        g_lower = g.lower().replace("-", "").replace(" ", "")
        for vocab_g, idx in GENRE_TO_IDX.items():
            if vocab_g in g_lower or g_lower in vocab_g:
                vec[idx] = 1.0
                break
        else:
            vec[GENRE_TO_IDX["other"]] = 1.0
    # Normalize
    total = vec.sum()
    if total > 0:
        vec /= total
    return vec


def encode_time(hour: int, day_of_week: int) -> dict:
    """Cyclical encoding for time features."""
    h_sin = math.sin(2 * math.pi * hour / 24)
    h_cos = math.cos(2 * math.pi * hour / 24)
    d_sin = math.sin(2 * math.pi * day_of_week / 7)
    d_cos = math.cos(2 * math.pi * day_of_week / 7)
    is_weekend = 1.0 if day_of_week >= 5 else 0.0
    # Time-of-day one-hot: morning(6-12), afternoon(12-18), evening(18-23), night(23-6)
    morning = 1.0 if 6 <= hour < 12 else 0.0
    afternoon = 1.0 if 12 <= hour < 18 else 0.0
    evening = 1.0 if 18 <= hour < 23 else 0.0
    night = 1.0 if hour >= 23 or hour < 6 else 0.0
    return {
        "h_sin": h_sin, "h_cos": h_cos,
        "d_sin": d_sin, "d_cos": d_cos,
        "is_weekend": is_weekend,
        "morning": morning, "afternoon": afternoon,
        "evening": evening, "night": night,
    }


def build_feature_vector(
    track: TrackFeatures,
    context: UserContext,
    prefs: UserPreferences,
) -> np.ndarray:
    """Build the 50-dimensional feature vector."""
    features = []

    # --- Track features (12) ---
    features.append(track.energy)
    features.append(track.valence)
    features.append(track.tempo / 200.0)  # normalize tempo to ~[0, 1]
    features.append(track.danceability)
    genre_vec = encode_genre_vector(track.genres)
    features.extend(genre_vec.tolist())  # 8 values

    # --- Context features (16) ---
    time_enc = encode_time(context.hour, context.day_of_week)
    features.append(time_enc["h_sin"])
    features.append(time_enc["h_cos"])
    features.append(time_enc["d_sin"])
    features.append(time_enc["d_cos"])
    features.append(context.recent_energy_avg)
    features.append(context.recent_valence_avg)
    features.append(context.recent_tempo_avg / 200.0)
    features.append(min(context.session_skip_rate, 1.0))
    features.append(min(context.session_length / 50.0, 1.0))  # normalize
    features.append(min(context.hours_since_last_listen / 24.0, 1.0))
    features.append(min(context.tracks_today_count / 100.0, 1.0))
    features.append(time_enc["is_weekend"])
    features.append(time_enc["morning"])
    features.append(time_enc["afternoon"])
    features.append(time_enc["evening"])
    features.append(time_enc["night"])

    # --- User preference features (22) ---
    # Genre weights (8)
    for g in GENRE_VOCAB:
        features.append(prefs.genre_weights.get(g, 0.0))
    # Audio prefs (3)
    features.append(prefs.energy_pref)
    features.append(prefs.valence_pref)
    features.append(prefs.tempo_pref / 200.0)
    # Match scores (2)
    features.append(prefs.genre_match_score)
    features.append(prefs.artist_match_score)
    # Provider weights (4)
    for p in PROVIDER_VOCAB:
        features.append(prefs.provider_weights.get(p, 0.0))
    # Signals (5)
    features.append(prefs.novelty_score)
    features.append(prefs.peer_score)
    features.append(min(prefs.days_since_last_play_artist / 30.0, 1.0))
    features.append(min(prefs.repeat_count_7d / 10.0, 1.0))
    features.append(1.0 if prefs.favorite_flag else 0.0)

    assert len(features) == 50, f"Expected 50 features, got {len(features)}"
    return np.array(features, dtype=np.float32)


if __name__ == "__main__":
    track = TrackFeatures(energy=0.8, valence=0.6, tempo=128, danceability=0.7,
                          genres=["pop", "electronic"])
    ctx = UserContext(hour=22, day_of_week=5, recent_energy_avg=0.7,
                      recent_valence_avg=0.6, session_skip_rate=0.1, session_length=5)
    prefs = UserPreferences(
        genre_weights={"pop": 0.8, "electronic": 0.6},
        energy_pref=0.7, valence_pref=0.5, tempo_pref=130,
        provider_weights={"spotify": 0.7, "youtube": 0.3},
        genre_match_score=0.9, artist_match_score=0.5,
    )

    vec = build_feature_vector(track, ctx, prefs)
    print(f"Feature vector: {vec.shape}")
    print(f"Values: {vec}")
    print("Features OK.")
