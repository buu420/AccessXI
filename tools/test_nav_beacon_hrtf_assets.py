#!/usr/bin/env python3
"""Validate the shipped AccessXI HRTF navigation-beacon bank."""

from __future__ import annotations

import argparse
import csv
import hashlib
import math
from pathlib import Path
import re
import struct
import wave


EXPECTED_VERSION = "accessxi-nav-beacon-hrtf-v1"
EXPECTED_DATASET_SHA256 = (
    "bb5980288fc5c990c821e02c5ddfa274759079b723973cd6ca47ac577243aa0c"
)
EXPECTED_APACHE_LICENSE_SHA256 = (
    "8c6db340475136df3c1201d458fa5755698eace76e510471ecc9d857d6083dac"
)


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def read_pcm16(path: Path, channels: int, frames: int) -> tuple[list[float], list[float]]:
    with wave.open(str(path), "rb") as stream:
        assert stream.getnchannels() == channels, f"{path.name}: unexpected channel count"
        assert stream.getsampwidth() == 2, f"{path.name}: expected PCM16"
        assert stream.getframerate() == 48_000, f"{path.name}: expected 48 kHz"
        assert stream.getnframes() == frames, f"{path.name}: unexpected frame count"
        assert stream.getcomptype() == "NONE", f"{path.name}: expected uncompressed PCM"
        payload = stream.readframes(frames)
    values = struct.unpack(f"<{frames * channels}h", payload)
    if channels == 1:
        return [float(value) for value in values], []
    return (
        [float(values[index]) for index in range(0, len(values), 2)],
        [float(values[index]) for index in range(1, len(values), 2)],
    )


def rms(values: list[float]) -> float:
    return math.sqrt(sum(value * value for value in values) / len(values))


def correlation(left: list[float], right: list[float]) -> float:
    left_mean = sum(left) / len(left)
    right_mean = sum(right) / len(right)
    numerator = sum(
        (left_value - left_mean) * (right_value - right_mean)
        for left_value, right_value in zip(left, right)
    )
    left_energy = sum((value - left_mean) ** 2 for value in left)
    right_energy = sum((value - right_mean) ** 2 for value in right)
    return numerator / math.sqrt(left_energy * right_energy)


def validate(bank: Path, generator: Path) -> None:
    manifest_path = bank / "manifest.tsv"
    notice_path = bank / "NOTICE.txt"
    license_path = bank / "LICENSE-Apache-2.0.txt"
    source_path = bank / "source_mono.wav"
    assert manifest_path.is_file(), "HRTF manifest is missing"
    assert notice_path.is_file(), "HRTF provenance notice is missing"
    assert license_path.is_file(), "full Apache 2.0 license is missing"
    assert source_path.is_file(), "HRTF source cue is missing"

    with manifest_path.open("r", encoding="utf-8", newline="") as stream:
        rows = list(csv.DictReader(stream, delimiter="\t"))
    expected_files = {
        f"{prefix}_{bin_number:02d}.wav"
        for prefix in ("front", "rear")
        for bin_number in range(13)
    }
    assert len(rows) == 26, f"expected 26 HRTF assets, found {len(rows)}"
    assert {row["file"] for row in rows} == expected_files, "HRTF selector coverage is incomplete"
    assert all(row["format_version"] == EXPECTED_VERSION for row in rows), (
        "HRTF manifest format version drifted"
    )

    pcm: dict[str, tuple[list[float], list[float]]] = {}
    hashes: set[str] = set()
    for row in rows:
        path = bank / row["file"]
        assert path.is_file(), f"missing HRTF asset: {row['file']}"
        actual_hash = sha256(path)
        assert actual_hash == row["output_sha256"], f"hash mismatch: {row['file']}"
        hashes.add(actual_hash)
        left, right = read_pcm16(path, channels=2, frames=6000)
        combined_rms = math.sqrt((rms(left) ** 2 + rms(right) ** 2) / 2.0)
        assert 2600.0 <= combined_rms <= 3900.0, f"unexpected loudness: {row['file']}"
        assert (
            max(max(abs(value) for value in left), max(abs(value) for value in right)) <= 25560
        ), f"peak normalization failed: {row['file']}"
        pcm[row["file"]] = (left, right)
    assert len(hashes) == 26, "two selector directions unexpectedly have identical audio"

    source, empty = read_pcm16(source_path, channels=1, frames=5040)
    assert not empty and rms(source) > 1000.0, "source cue is silent"
    notice = notice_path.read_text(encoding="utf-8")
    source_match = re.search(r"Source cue SHA-256: ([0-9a-f]{64})", notice)
    assert source_match and source_match.group(1) == sha256(source_path), (
        "source cue provenance hash is missing or wrong"
    )
    assert EXPECTED_DATASET_SHA256 in notice, "SADIE dataset hash is absent from NOTICE"
    assert "University of York" in notice and "Apache License, Version 2.0" in notice, (
        "SADIE attribution or license is absent from NOTICE"
    )
    assert "10.3390/app8112029" in notice, "SADIE II citation is absent from NOTICE"
    assert sha256(license_path) == EXPECTED_APACHE_LICENSE_SHA256, (
        "bundled Apache 2.0 license is incomplete or modified"
    )
    license_text = license_path.read_text(encoding="utf-8")
    assert "TERMS AND CONDITIONS FOR USE, REPRODUCTION, AND DISTRIBUTION" in license_text
    assert "APPENDIX: How to apply the Apache License to your work." in license_text

    generator_match = re.search(r"Generator SHA-256: ([0-9a-f]{64})", notice)
    assert generator_match and generator_match.group(1) == sha256(generator), (
        "generator provenance hash is missing or wrong"
    )
    assert "numpy: 2.3.5" in notice and "h5py: 3.14.0" in notice, (
        "pinned generator dependency versions are absent from NOTICE"
    )

    by_name = {row["file"]: row for row in rows}
    assert abs(float(by_name["front_06.wav"]["selector_angle_degrees"])) < 0.001
    assert abs(abs(float(by_name["rear_06.wav"]["selector_angle_degrees"])) - 180.0) < 0.001
    assert float(by_name["front_00.wav"]["selector_angle_degrees"]) > 80.0
    assert float(by_name["front_12.wav"]["selector_angle_degrees"]) < -80.0

    for left_name, right_name in (("front_00.wav", "front_12.wav"), ("rear_00.wav", "rear_12.wav")):
        leftward = pcm[left_name]
        rightward = pcm[right_name]
        assert rms(leftward[0]) > 1.5 * rms(leftward[1]), f"{left_name} is not leftward"
        assert rms(rightward[1]) > 1.5 * rms(rightward[0]), f"{right_name} is not rightward"
    for centered in ("front_06.wav", "rear_06.wav"):
        left, right = pcm[centered]
        balance = rms(left) / rms(right)
        assert 0.70 <= balance <= 1.40, f"{centered} is not centered"
        assert correlation(left, right) < 0.995, f"{centered} collapsed to simple mono panning"
    assert sha256(bank / "front_06.wav") != sha256(bank / "rear_06.wav"), (
        "front and rear center cues are identical"
    )

    generator_text = generator.read_text(encoding="utf-8")
    assert EXPECTED_DATASET_SHA256 in generator_text, "generator does not pin the SADIE dataset"
    assert "np.convolve" in generator_text and "Data.IR" in generator_text, (
        "generator no longer applies ear-specific HRIR convolution"
    )


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("bank", type=Path)
    parser.add_argument("generator", type=Path)
    args = parser.parse_args()
    validate(args.bank.resolve(), args.generator.resolve())
    print("navigation beacon HRTF assets passed")


if __name__ == "__main__":
    main()
