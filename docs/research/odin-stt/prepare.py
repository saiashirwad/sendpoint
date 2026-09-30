#!/usr/bin/env python3
"""Fetch pinned research artifacts into .build/odin-research, never the app cache.
Run from repository root. Requires Python 3; downloads ~510 MB on first use.
Core ML encoder/decoder/joint/vocab are read from Sendpoint's existing cache by run.sh.
"""
import hashlib
import json
import pathlib
import struct
import tarfile
import urllib.request
import wave

ROOT = pathlib.Path('.build/odin-research')
ROOT.mkdir(parents=True, exist_ok=True)
ARTIFACTS = [
    ('sherpa.tar.bz2', 'https://github.com/k2-fsa/sherpa-onnx/releases/download/v1.13.8/sherpa-onnx-v1.13.8-osx-arm64-shared-no-tts-lib.tar.bz2', 'f3e0cbd86cc3f38dad30c97921b40e9a8bcc6f2c943777eb76ad77176993e417'),
    ('model.tar.bz2', 'https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-nemo-parakeet-unified-en-0.6b-int8-streaming-240ms.tar.bz2', 'dead05a9149f6f02d373f3eb4553c74af4f189ff74889b5e210b35ca102655da'),
]
for name, url, expected in ARTIFACTS:
    dest = ROOT / name
    if not dest.exists():
        temporary = dest.with_suffix('.partial')
        print('Downloading', url, flush=True)
        urllib.request.urlretrieve(url, temporary)
        temporary.rename(dest)
    assert hashlib.sha256(dest.read_bytes()).hexdigest() == expected, name
    # Python >=3.12 extraction filter rejects traversal and unsafe links.
    with tarfile.open(dest) as archive:
        archive.extractall(ROOT, filter='data')

HF_REV = 'd32e972dd4315f1dc3f6be28fb2aab0ab3e80358'
BASE = 'https://huggingface.co/FluidInference/parakeet-unified-en-0.6b-coreml/resolve/' + HF_REV
for relative in ['analytics/coremldata.bin', 'coremldata.bin', 'model.mil', 'weights/weight.bin']:
    dest = ROOT / 'preprocessor.mlmodelc' / relative
    dest.parent.mkdir(parents=True, exist_ok=True)
    urllib.request.urlretrieve(BASE + '/parakeet_unified_preprocessor.mlmodelc/' + relative, dest)

wav = ROOT / 'sherpa-onnx-nemo-parakeet-unified-en-0.6b-int8-streaming-240ms/test_wavs/0.wav'
with wave.open(str(wav)) as stream:
    assert (stream.getnchannels(), stream.getsampwidth(), stream.getframerate()) == (1, 2, 16000)
    data = stream.readframes(stream.getnframes())
samples = struct.unpack('<' + 'h' * (len(data)//2), data)
(ROOT / 'sample.f32le').write_bytes(struct.pack('<' + 'f' * len(samples), *(s/32768 for s in samples)))
print('Ready:', ROOT)
