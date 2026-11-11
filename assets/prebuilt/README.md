# Prebuilt binaries

These binaries are used by setup profiles that do **not** include the `build`
feature, so a C/C++ toolchain is not required.

## `tmux-mem-cpu-load-linux-x86_64`

- Source: `app-forks/tmux-mem-cpu-load` (upstream v3.8.3, Apache-2.0).
- Built on Ubuntu 22.04 with:

  ```bash
  cmake -S app-forks/tmux-mem-cpu-load -B /tmp/tmux-build \
    -DCMAKE_BUILD_TYPE=MinSizeRel \
    -DCMAKE_EXE_LINKER_FLAGS="-static-libstdc++ -static-libgcc"
  cmake --build /tmp/tmux-build --parallel 2
  strip /tmp/tmux-build/tmux-mem-cpu-load
  ```

- Links against glibc 2.34+ only (`libstdc++` is linked statically).
- SHA-256: `5e75a9bfed2a863425696c9d1a58315fa8310bd6c27348a179e715abd6eff5f2`.

When replacing the binary, update:

1. `tmux-mem-cpu-load-linux-x86_64.sha256` in this directory.
2. `TMUX_MEM_CPU_LOAD_PREBUILT` in `provision/migrations/tmux.py`.
3. The SHA-256 in this README.

Only x86_64 has a committed prebuilt. On other architectures setup asks the
user to enable the `build` feature (or install the helper manually).

The `.github/workflows/publish-prebuilt.yml` workflow publishes these files as
the `tmux-mem-cpu-load-v2` GitHub release. Setup prefers that release asset and
falls back to the committed copy, so a fresh machine works even before a
release is published.
