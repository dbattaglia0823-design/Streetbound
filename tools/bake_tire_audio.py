"""Bake original, seamless tire textures offline; no synthesis in the drift loop.

Python standard library only. The assets are synthesized, not field recordings.
"""
import math
import random
import struct
import wave
from pathlib import Path

RATE = 24000
LENGTH = RATE * 4
OVERLAP = RATE // 4
DESTINATION = Path(__file__).resolve().parents[1] / "assets" / "audio"


class BandPass:
    def __init__(self, frequency, q):
        omega = math.tau * frequency / RATE
        alpha = math.sin(omega) / (2 * q)
        divisor = 1 + alpha
        self.b0, self.b2 = alpha / divisor, -alpha / divisor
        self.a1, self.a2 = -2 * math.cos(omega) / divisor, (1 - alpha) / divisor
        self.x1 = self.x2 = self.y1 = self.y2 = 0.0

    def sample(self, value):
        result = self.b0 * value + self.b2 * self.x2 - self.a1 * self.y1 - self.a2 * self.y2
        self.x2, self.x1 = self.x1, value
        self.y2, self.y1 = self.y1, result
        return result


def texture(loose):
    rng = random.Random(713 if loose else 914)
    bands = [BandPass(frequency, q) for frequency, q in
             ([(250, 0.7), (700, 0.9), (1800, 0.7)] if loose else [(760, 2.8), (1350, 2.1), (2450, 1.5)])]
    raw = []
    phase = slow = rough = low = 0.0
    for index in range(LENGTH + OVERLAP + RATE):
        t = index / RATE
        noise = rng.uniform(-1, 1)
        slow += (noise - slow) * 0.0015
        rough += (noise - rough) * 0.035
        low += (noise - low) * 0.09
        filtered = sum(band.sample(noise) * weight for band, weight in zip(bands, [0.65, 0.30, 0.15]))
        if loose:
            # Granular contact noise instead of rubber squeal on grass/gravel.
            value = filtered * 1.5 + low * 0.2
            value *= 0.85 + min(abs(rough) * 2, 0.5)
        else:
            # Broad rubbing resonances with a faint, wandering stick-slip tone.
            # No piercing fixed-frequency oscillator or unfiltered white hiss.
            frequency = 710 + 28 * math.sin(math.tau * 1.75 * t) + slow * 200
            phase += math.tau * frequency / RATE
            tone = math.sin(phase) + 0.23 * math.sin(phase * 2 + 0.3)
            value = filtered * 1.7 + tone * 0.07
            value *= 0.87 + 0.06 * math.sin(math.tau * 6.25 * t) + rough * 0.2
        raw.append(value)
    raw = raw[RATE:]  # Discard filter warm-up.
    loop = raw[:LENGTH]
    for index in range(OVERLAP):
        blend = index / OVERLAP
        blend = blend * blend * (3 - 2 * blend)
        loop[index] = raw[LENGTH + index] * (1 - blend) + raw[index] * blend
    rms = math.sqrt(sum(value * value for value in loop) / len(loop))
    gain = min(0.20 / rms, 0.85 / max(abs(value) for value in loop))
    return [value * gain for value in loop]


def main():
    DESTINATION.mkdir(parents=True, exist_ok=True)
    for name, loose in [("tire_asphalt", False), ("tire_loose", True)]:
        samples = texture(loose)
        with wave.open(str(DESTINATION / (name + ".wav")), "wb") as output:
            output.setnchannels(1)
            output.setsampwidth(2)
            output.setframerate(RATE)
            output.writeframes(struct.pack("<%dh" % len(samples), *(round(value * 32767) for value in samples)))
        print(f"{name}: {len(samples) / RATE:.1f}s, peak {max(abs(value) for value in samples):.3f}, seam delta {abs(samples[-1] - samples[0]):.4f}")


if __name__ == "__main__":
    main()
