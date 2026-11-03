# Forked/vendored code (`plugin-forks/` and `app-forks/`)

Both directories hold third-party code copied into this repo instead of being
pulled from a remote. They are plain source trees — no `.git` directory and no
upstream remote — so updating one means re-copying the upstream source and
re-applying any local patches listed below.

## `plugin-forks/`

Lua plugins vendored here are loaded with `dir = ...` in a `lua/plugins/*.lua`
spec rather than lazy.nvim's normal git-clone flow.

| Fork | Loaded from | Based on | Why it's vendored |
|---|---|---|---|
| `last-file-rec` | `lua/plugins/last-file-recorder.lua` | custom, not based on an upstream plugin | Small plugin that records the last real (non-`term://`/`oil://`/etc.) file buffer opened, to `stdpath("cache")/last_file.txt`. Actively used (loads on `VeryLazy`; writes the cache once on `VimLeavePre`). |

## `app-forks/`

Non-plugin tools and scripts used by the shell/tmux setup.

| Item | Used by | Based on | Notes |
|---|---|---|---|
| `tmux-mem-cpu-load` | `.tmux.conf` status-right; built and installed by `setup.sh` (`install_tmux_mem_cpu_load`) | [thewtex/tmux-mem-cpu-load](https://github.com/thewtex/tmux-mem-cpu-load) v3.8.2 | Local edits in `common/powerline.cc` and `common/load.cc`. Built in place, so CMake artifacts (`CMakeCache.txt`, `CMakeFiles/`, binaries) are present in the directory. |
| `spinner.sh` | `.bash_profile_yf` (`ask`/`codo` helpers) | Dave Eddy's `spinner.sh`; spinners from [sindresorhus/cli-spinners](https://github.com/sindresorhus/cli-spinners) | Executable, invoked as-is (MIT). |

## Removed forks

Removed in November 2026, along with their `lua/plugins/*.lua` specs and
dependent configuration:

- `nvim-dbee` — SQL client fork (Azure AD auth); was disabled.
- `dotbee` — .NET debug-message UI experiment; was disabled and stubbed out.
- `neotest` / `neotest-dotnet` — vendored test runner and .NET adapter; the
  `lazyvim.plugins.extras.test.core` extra was disabled at the same time.
