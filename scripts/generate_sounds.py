"""Generate original short PCM alarm melodies; no copyrighted sampled audio."""
import math
import struct
import wave
from pathlib import Path
root = Path(__file__).resolve().parents[1] / "ios/Svitanok/Resources"
root.mkdir(parents=True, exist_ok=True)
sr = 44100
for name, notes in {"dawn": [523.25, 659.25, 783.99, 1046.5], "pulse": [880, 880, 660, 880]}.items():
    data = []
    for _ in range(4):
        for note in notes:
            for i in range(int(sr * .30)):
                t = i / sr
                env = min(1, t / .015) * max(0, min(1, (.25 - t) / .08))
                sample = .38 * env * (math.sin(2 * math.pi * note * t) + .18 * math.sin(4 * math.pi * note * t))
                data.append(struct.pack("<h", int(sample * 32767)))
    with wave.open(str(root / f"{name}.wav"), "wb") as wav:
        wav.setparams((1, 2, sr, 0, "NONE", "not compressed"))
        wav.writeframes(b"".join(data))
