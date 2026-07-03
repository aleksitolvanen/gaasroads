#!/usr/bin/env python3
"""Bake the chiptune tracks to Music/*.ogg.

Port of the original runtime synth from Scripts/music.gd (pre-bake version).
Each track is a seamless 64-step loop; all voices retrigger at step 0.
Requires ffmpeg on PATH for OGG encoding.

Usage: python bake_music.py
"""
import math
import subprocess
import tempfile
import wave
from pathlib import Path

MIX_RATE = 44100
STEPS = 64

MEL_GAIN = 0.22
BASS_GAIN = 0.18
ARP_GAIN = 0.13

# fmt: off
TRACKS = {
    "cosmic": {  # Eerie but adventurous - E minor, 115 BPM
        "step_length": 60.0 / 115.0 / 4.0,
        "types": (2, 1, 0),
        "decays": (0.99996, 0.99998, 0.99993),
        "melody": [
            64, -1, 0, 0, 71, -1, -1, 0, 67, -1, 69, 0, 71, -1, -1, 0,
            74, -1, 72, 0, 71, -1, 69, 0, 67, -1, -1, 0, 64, -1, -1, 0,
            64, -1, 0, 67, 71, -1, 0, 74, 76, -1, -1, 0, 74, -1, 71, 0,
            72, -1, 69, 0, 67, -1, 64, 0, 62, -1, -1, 0, 64, -1, -1, -1,
        ],
        "bass": [
            40, -1, -1, -1, 47, -1, -1, -1, 43, -1, -1, -1, 47, -1, -1, -1,
            40, -1, -1, -1, 45, -1, -1, -1, 43, -1, -1, -1, 40, -1, -1, -1,
            40, -1, -1, -1, 47, -1, -1, -1, 43, -1, -1, -1, 50, -1, -1, -1,
            48, -1, -1, -1, 45, -1, -1, -1, 43, -1, -1, -1, 40, -1, -1, -1,
        ],
        "arp": [
            52, 55, 59, 64, 59, 55, 52, 0,
            48, 52, 55, 60, 55, 52, 48, 0,
            45, 48, 52, 57, 52, 48, 45, 0,
            47, 50, 54, 59, 54, 50, 47, 0,
        ],
    },
    "nebula": {  # Mysterious, ethereal - A minor, 110 BPM
        "step_length": 60.0 / 110.0 / 4.0,
        "types": (2, 1, 0),
        "decays": (0.99996, 0.99998, 0.99993),
        "melody": [
            69, 0, 0, 72, 0, 0, 76, 0, 0, 0, 81, 0, 79, 0, 0, 0,
            68, 0, 0, 71, 0, 0, 76, 0, 0, 0, 74, 0, 72, 0, 0, 0,
            69, 0, 0, 0, 76, 0, 0, 0, 81, 0, 79, 0, 76, 0, 72, 0,
            68, 0, 0, 0, 71, 0, 0, 0, 76, 0, 74, 0, 72, 0, 0, 0,
        ],
        "bass": [
            45, -1, -1, -1, -1, -1, -1, -1, 52, -1, -1, -1, -1, -1, -1, -1,
            44, -1, -1, -1, -1, -1, -1, -1, 50, -1, -1, -1, -1, -1, -1, -1,
            45, -1, -1, -1, -1, -1, -1, -1, 52, -1, -1, -1, -1, -1, -1, -1,
            44, -1, -1, -1, -1, -1, -1, -1, 50, -1, -1, -1, -1, -1, -1, -1,
        ],
        "arp": [
            57, 0, 60, 0, 64, 0, 69, 0,
            56, 0, 59, 0, 64, 0, 68, 0,
        ],
    },
    "solar": {  # Intense, driving - D minor, 160 BPM
        "step_length": 60.0 / 160.0 / 4.0,
        "types": (1, 0, 2),
        "decays": (0.99993, 0.99996, 0.99991),
        "melody": [
            74, 0, 74, 0, 77, 0, 77, 0, 81, 0, 81, 0, 86, 0, 84, 0,
            82, 0, 81, 0, 79, 0, 77, 0, 74, 0, 72, 0, 74, 0, 0, 0,
            86, 0, 84, 0, 82, 0, 81, 0, 79, 0, 77, 0, 74, 0, 72, 0,
            74, 0, 77, 0, 81, 0, 84, 0, 86, 0, 0, 0, 86, 0, 0, 0,
        ],
        "bass": [
            50, -1, 0, 50, -1, 0, 50, -1, 46, -1, 0, 46, -1, 0, 45, -1,
            50, -1, 0, 50, -1, 0, 50, -1, 46, -1, 0, 46, -1, 0, 45, -1,
            50, -1, 0, 50, -1, 0, 50, -1, 46, -1, 0, 46, -1, 0, 45, -1,
            50, -1, 0, 50, -1, 0, 50, -1, 48, -1, 0, 48, -1, 0, 50, -1,
        ],
        "arp": [
            62, 65, 69, 74, 62, 65, 69, 74,
            58, 62, 65, 70, 57, 62, 65, 69,
        ],
    },
    "dark": {  # Ominous, creepy - chromatic, 90 BPM
        "step_length": 60.0 / 90.0 / 4.0,
        "types": (0, 1, 2),
        "decays": (0.99995, 0.99998, 0.99994),
        "melody": [
            64, 0, 0, 0, 65, 0, 0, 64, 0, 0, 63, 0, 0, 0, 0, 0,
            62, 0, 0, 0, 63, 0, 0, 62, 0, 0, 60, 0, 0, 0, 0, 0,
            59, 0, 0, 0, 60, 0, 0, 59, 0, 0, 58, 0, 0, 0, 0, 0,
            57, 0, 0, 0, 58, 0, 0, 57, 0, 0, 55, 0, 0, 0, 0, 0,
        ],
        "bass": [
            40, -1, -1, -1, -1, -1, -1, -1, 0, 0, 0, 0, 40, -1, -1, -1,
            39, -1, -1, -1, -1, -1, -1, -1, 0, 0, 0, 0, 38, -1, -1, -1,
            40, -1, -1, -1, -1, -1, -1, -1, 0, 0, 0, 0, 40, -1, -1, -1,
            37, -1, -1, -1, -1, -1, -1, -1, 0, 0, 0, 0, 36, -1, -1, -1,
        ],
        "arp": [
            52, 0, 0, 0, 55, 0, 0, 0,
            51, 0, 0, 0, 54, 0, 0, 0,
        ],
    },
}
# fmt: on


def wave_sample(wtype: int, phase: float) -> float:
    if wtype == 0:
        return 1.0 if phase < 0.5 else -1.0
    if wtype == 1:
        return 2.0 * phase - 1.0
    return 4.0 * abs(phase - 0.5) - 1.0


def note_freq(midi: int) -> float:
    return 440.0 * 2.0 ** ((midi - 69) / 12.0)


class Voice:
    def __init__(self, pattern, wtype, decay, gain):
        self.pattern = pattern
        self.wtype = wtype
        self.decay = decay
        self.gain = gain
        self.freq = 0.0
        self.vol = 0.0
        self.phase = 0.0

    def trigger(self, step: int):
        n = self.pattern[step % len(self.pattern)]
        if n > 0:
            self.freq = note_freq(n)
            self.vol = 1.0
        elif n == 0:
            self.vol = 0.0

    def sample(self) -> float:
        if self.freq <= 0.0 or self.vol <= 0.005:
            return 0.0
        self.phase = (self.phase + self.freq / MIX_RATE) % 1.0
        s = wave_sample(self.wtype, self.phase) * self.vol * self.gain
        self.vol *= self.decay
        return s


def bake(spec: dict) -> bytes:
    voices = [
        Voice(spec["melody"], spec["types"][0], spec["decays"][0], MEL_GAIN),
        Voice(spec["bass"], spec["types"][1], spec["decays"][1], BASS_GAIN),
        Voice(spec["arp"], spec["types"][2], spec["decays"][2], ARP_GAIN),
    ]
    sps = spec["step_length"] * MIX_RATE
    out = bytearray()
    for step in range(STEPS):
        for v in voices:
            v.trigger(step)
        n_samples = round((step + 1) * sps) - round(step * sps)
        for _ in range(n_samples):
            s = sum(v.sample() for v in voices)
            val = int(max(-1.0, min(1.0, s)) * 32767)
            out += val.to_bytes(2, "little", signed=True)
    return bytes(out)


def main():
    out_dir = Path(__file__).parent / "Music"
    out_dir.mkdir(exist_ok=True)
    for name, spec in TRACKS.items():
        pcm = bake(spec)
        with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as tmp:
            tmp_path = Path(tmp.name)
        with wave.open(str(tmp_path), "wb") as wf:
            wf.setnchannels(1)
            wf.setsampwidth(2)
            wf.setframerate(MIX_RATE)
            wf.writeframes(pcm)
        ogg_path = out_dir / f"{name}.ogg"
        subprocess.run(
            ["ffmpeg", "-y", "-loglevel", "error", "-i", str(tmp_path),
             "-c:a", "libvorbis", "-q:a", "4", str(ogg_path)],
            check=True,
        )
        tmp_path.unlink()
        secs = len(pcm) / 2 / MIX_RATE
        print(f"{ogg_path.name}: {secs:.2f}s loop, {ogg_path.stat().st_size // 1024} KB")


if __name__ == "__main__":
    main()
