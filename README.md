# BENDY

Ports the bendy plugin to macOS. This plugin lets you use FL's slide 
and portamento notes on every VST

Build

```sh
cmake -S . -B build-macos -DCMAKE_BUILD_TYPE=Release -DCMAKE_OSX_ARCHITECTURES="arm64;x86_64"
cmake --build build-macos --parallel
ctest --test-dir build-macos --output-on-failure
```

Insall

```sh
./scripts/install-macos.sh "/Applications/FL Studio 2026.app"
```

Original repo
https://github.com/superjoebob/bendy_redo 