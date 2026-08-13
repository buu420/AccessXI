#!/usr/bin/env python3
"""Bake AccessXI navigation beacon WAVs through the SADIE II KEMAR HRIRs."""

from __future__ import annotations

import argparse
import csv
import hashlib
import math
import os
from pathlib import Path
import struct
import urllib.request
import wave

try:
    import h5py
    import numpy as np
except ImportError as exc:  # pragma: no cover - dependency error is user-facing
    raise SystemExit("generate_nav_beacon_hrtf.py requires numpy and h5py") from exc


DATASET_NAME = "SADIE II D2 KEMAR 48 kHz 256-tap diffuse-field-equalized HRIR"
DATASET_URL = (
    "https://sofacoustics.org/data/database/sadie/"
    "D2_48K_24bit_256tap_FIR_SOFA.sofa"
)
DATASET_SHA256 = "bb5980288fc5c990c821e02c5ddfa274759079b723973cd6ca47ac577243aa0c"
FORMAT_VERSION = "accessxi-nav-beacon-hrtf-v1"


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def acquire_dataset(path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    if not path.exists():
        temporary = path.with_suffix(path.suffix + ".tmp")
        urllib.request.urlretrieve(DATASET_URL, temporary)
        os.replace(temporary, path)
    actual = sha256(path)
    if actual != DATASET_SHA256:
        raise SystemExit(
            f"SADIE dataset SHA-256 mismatch: expected {DATASET_SHA256}, got {actual}"
        )


def selector_key(delta: float) -> tuple[str, int]:
    pan = max(-1.0, min(1.0, -math.sin(delta)))
    bin_number = max(0, min(12, math.floor(((pan + 1.0) * 6.0) + 0.5)))
    return ("rear" if math.cos(delta) < -0.35 else "front", bin_number)


def canonical_selector_angles() -> dict[tuple[str, int], float]:
    samples: dict[tuple[str, int], list[float]] = {
        (prefix, bin_number): []
        for prefix in ("front", "rear")
        for bin_number in range(13)
    }
    for index in range(360_000):
        delta = -math.pi + ((index + 0.5) * 2.0 * math.pi / 360_000)
        samples[selector_key(delta)].append(delta)

    result: dict[tuple[str, int], float] = {}
    for key, angles in samples.items():
        if not angles:
            raise SystemExit(f"selector has no angle coverage for {key[0]}_{key[1]:02d}")
        sine = sum(math.sin(value) for value in angles)
        cosine = sum(math.cos(value) for value in angles)
        result[key] = math.atan2(sine, cosine)
    return result


def make_source(sample_rate: int) -> np.ndarray:
    frame_count = round(sample_rate * 0.105)
    t = np.arange(frame_count, dtype=np.float64) / sample_rate
    phase = 2.0 * np.pi * (650.0 * t + (0.5 * ((6200.0 - 650.0) / 0.105) * t * t))
    chirp = np.sin(phase)
    body = (
        0.48 * np.sin(2.0 * np.pi * 980.0 * t)
        + 0.32 * np.sin(2.0 * np.pi * 1470.0 * t + 0.35)
        + 0.20 * np.sin(2.0 * np.pi * 2940.0 * t + 0.9)
    )
    rng = np.random.default_rng(0xA11CE55)
    noise = rng.standard_normal(frame_count)
    spectrum = np.fft.rfft(noise)
    frequencies = np.fft.rfftfreq(frame_count, 1.0 / sample_rate)
    spectrum[(frequencies < 700.0) | (frequencies > 9000.0)] = 0.0
    broadband = np.fft.irfft(spectrum, frame_count)
    broadband /= max(1e-12, float(np.max(np.abs(broadband))))

    attack = np.minimum(1.0, t / 0.004)
    envelope = attack * np.exp(-18.0 * t)
    fade_frames = max(1, round(sample_rate * 0.014))
    envelope[-fade_frames:] *= np.linspace(1.0, 0.0, fade_frames, endpoint=True)
    source = ((0.50 * chirp) + (0.30 * body) + (0.20 * broadband)) * envelope
    source -= float(np.mean(source))
    source *= 0.72 / max(1e-12, float(np.max(np.abs(source))))
    return source


def write_pcm16(path: Path, samples: np.ndarray, sample_rate: int) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    clipped = np.clip(samples, -1.0, 1.0)
    pcm = np.rint(clipped * 32767.0).astype("<i2")
    with wave.open(str(path), "wb") as output:
        output.setnchannels(1 if pcm.ndim == 1 else pcm.shape[1])
        output.setsampwidth(2)
        output.setframerate(sample_rate)
        output.writeframes(pcm.tobytes(order="C"))


def nearest_measurement(positions: np.ndarray, angle_degrees: float) -> int:
    azimuth_error = ((positions[:, 0] - angle_degrees + 180.0) % 360.0) - 180.0
    score = (azimuth_error * azimuth_error) + (positions[:, 1] * positions[:, 1])
    return int(np.argmin(score))


def render(sofa_path: Path, output_dir: Path) -> None:
    acquire_dataset(sofa_path)
    with h5py.File(sofa_path, "r") as sofa:
        sample_rate = int(round(float(sofa["Data.SamplingRate"][0])))
        if sample_rate != 48_000:
            raise SystemExit(f"unexpected SADIE sample rate: {sample_rate}")
        positions = np.asarray(sofa["SourcePosition"][:], dtype=np.float64)
        impulse_responses = np.asarray(sofa["Data.IR"][:], dtype=np.float64)
        license_value = sofa.attrs["License"]
        license_text = (
            license_value.decode("utf-8")
            if isinstance(license_value, bytes)
            else str(license_value)
        )

    source = make_source(sample_rate)
    output_dir.mkdir(parents=True, exist_ok=True)
    source_path = output_dir / "source_mono.wav"
    write_pcm16(source_path, source, sample_rate)
    source_hash = sha256(source_path)
    angles = canonical_selector_angles()
    rows: list[dict[str, str]] = []

    for prefix in ("front", "rear"):
        for bin_number in range(13):
            angle = angles[(prefix, bin_number)]
            angle_degrees = math.degrees(angle) % 360.0
            measurement = nearest_measurement(positions, angle_degrees)
            channels = [np.convolve(source, impulse_responses[measurement, ear]) for ear in range(2)]
            stereo = np.column_stack(channels)
            target_frames = max(stereo.shape[0], round(sample_rate * 0.125))
            if stereo.shape[0] < target_frames:
                stereo = np.pad(stereo, ((0, target_frames - stereo.shape[0]), (0, 0)))
            rms = math.sqrt(float(np.mean(stereo * stereo)))
            gain = 0.105 / max(1e-12, rms)
            peak = float(np.max(np.abs(stereo))) * gain
            if peak > 0.78:
                gain *= 0.78 / peak
            stereo *= gain

            filename = f"{prefix}_{bin_number:02d}.wav"
            output_path = output_dir / filename
            write_pcm16(output_path, stereo, sample_rate)
            rows.append(
                {
                    "format_version": FORMAT_VERSION,
                    "file": filename,
                    "selector_angle_degrees": f"{math.degrees(angle):.6f}",
                    "sofa_measurement": str(measurement),
                    "sofa_azimuth_degrees": f"{positions[measurement, 0]:.6f}",
                    "sofa_elevation_degrees": f"{positions[measurement, 1]:.6f}",
                    "output_sha256": sha256(output_path),
                }
            )

    manifest_path = output_dir / "manifest.tsv"
    with manifest_path.open("w", encoding="utf-8", newline="") as manifest:
        fields = list(rows[0])
        writer = csv.DictWriter(manifest, fieldnames=fields, delimiter="\t", lineterminator="\n")
        writer.writeheader()
        writer.writerows(rows)

    notice = (
        "AccessXI navigation beacon HRTF bank\n\n"
        f"Format: {FORMAT_VERSION}\n"
        f"Source cue SHA-256: {source_hash}\n"
        f"HRTF dataset: {DATASET_NAME}\n"
        f"Dataset URL: {DATASET_URL}\n"
        f"Dataset SHA-256: {DATASET_SHA256}\n\n"
        f"Generator SHA-256: {sha256(Path(__file__).resolve())}\n"
        f"Python: {'.'.join(map(str, __import__('sys').version_info[:3]))}\n"
        f"numpy: {np.__version__}\n"
        f"h5py: {h5py.__version__}\n\n"
        "SADIE Database Copyright 2018 The University of York. This product includes data\n"
        "developed at The Audio Lab, University of York, UK (Cal Armstrong, Lewis Thresh,\n"
        "Gavin Kearney) as part of the SADIE Project. The SADIE II dataset is licensed\n"
        "under the Apache License, Version 2.0. Reference: https://doi.org/10.3390/app8112029\n\n"
        f"Dataset license metadata:\n{license_text}\n"
    )
    (output_dir / "NOTICE.txt").write_text(notice, encoding="utf-8", newline="\n")


def main() -> None:
    repo_root = Path(__file__).resolve().parents[1]
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--sofa",
        type=Path,
        default=repo_root / "build" / "hrtf" / Path(DATASET_URL).name,
    )
    parser.add_argument(
        "--output-dir",
        type=Path,
        default=repo_root / "ashita" / "addons" / "accessxi_reader" / "sounds" / "nav_beacon_hrtf",
    )
    args = parser.parse_args()
    render(args.sofa.resolve(), args.output_dir.resolve())


if __name__ == "__main__":
    main()
