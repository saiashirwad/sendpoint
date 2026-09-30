#!/bin/bash
# Run from repository root after: python3 docs/research/odin-stt/prepare.py
# Modes: native | sherpa [cpu|coreml] | direct | fluid (last-resort reference)
set -euo pipefail
src="$PWD/docs/research/odin-stt"
work="$PWD/.build/odin-research"
model="$work/sherpa-onnx-nemo-parakeet-unified-en-0.6b-int8-streaming-240ms"
cache="${COREML_CACHE:-$HOME/Library/Application Support/FluidAudio/Models/parakeet-unified-en-0.6b}"
mkdir -p "$work"
case "${1:-native}" in
  native)
    odin run "$src/objc-probe.odin" -file -out:"$work/objc-probe"
    odin run "$src/audio-probe.odin" -file -out:"$work/audio-probe"
    odin run "$src/coreml-probe.odin" -file -out:"$work/coreml-probe" -- "$cache/parakeet_unified_decoder.mlmodelc" decoder
    ;;
  sherpa)
    lib="$work/sherpa-onnx-v1.13.8-osx-arm64-shared-no-tts-lib/lib"
    odin build "$src/sherpa-probe.odin" -file -out:"$work/sherpa-probe" -extra-linker-flags:"-L$lib -Wl,-rpath,$lib"
    /usr/bin/time -l "$work/sherpa-probe" "$model/encoder.int8.onnx" "$model/decoder.int8.onnx" "$model/joiner.int8.onnx" "$model/tokens.txt" "$model/test_wavs/0.wav" "${2:-cpu}"
    ;;
  direct)
    odin build "$src/coreml-stream.odin" -file -o:speed -out:"$work/coreml-stream"
    /usr/bin/time -l "$work/coreml-stream" "$cache" "$work/preprocessor.mlmodelc" "$work/sample.f32le"
    ;;
  fluid)
    swift build --package-path "$src/fluid-bridge" --scratch-path "$work/fluid-build" -c release --product OdinFluidProbe
    lib="$work/fluid-build/release"
    odin build "$src/fluid-probe.odin" -file -out:"$work/fluid-probe" -extra-linker-flags:"-L$lib -Wl,-rpath,$lib"
    /usr/bin/time -l "$work/fluid-probe" "$cache" "$model/test_wavs/0.wav"
    ;;
  *) echo 'Expected native | sherpa [cpu|coreml] | direct | fluid' >&2; exit 2 ;;
esac
