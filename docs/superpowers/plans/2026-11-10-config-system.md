# Sophisticated config system implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn the flat config + append-only migration log into a feature-gated, reversible, interactive setup with nvim profiles.

**Architecture:** Introduce a feature registry shared (by convention) between bash setup modules and Lua config. Group migrations by feature under `setup/migrations/`, group nvim plugins under `lua/plugins/<feature>/`. Replace the append-only log with apply/undo records. Add `lua/config/profile.lua` so nvim omits disabled features' plugins entirely.

**Tech Stack:** bash 5, Neovim 0.12 Lua, lazy.nvim, existing plain-Lua test harness.

**Spec:** `docs/superpowers/specs/2026-11-10-config-system-design.md`

## Global constraints

- Keep `setup.sh` idempotent and safe to re-run.
- Default profile `full` must reproduce today's behaviour exactly.
- Never delete the migration log; append `undo` records.
- Down migrations must not remove OS packages unless `--purge`/`SETUP_PURGE=1`.
- Config removals in `down` only touch artifacts pointing at this repo.
- Every migration change keeps the README migration table in sync.
- Tests run headlessly: `nvim --headless -u NONE -l tests/<name>/run.lua`.

## Review focus

- A disabled feature's plugins must be absent from `:Lazy`, not merely disabled.
- Re-running with a changed selection appends `undo`/`apply` records; no log lines are deleted.
- `up` on an externally installed tool records the migration without overwriting.
- WSL features auto-enable on WSL and are hidden otherwise.
- Dependency constraints prevent disabling a feature while a dependent is on.

---

### Task 1: Migration log v2 (apply/undo state)

Files:
- Modify: setup.sh (or setup/lib/migrations.sh after Task 3)
- Create: tests/setup/migration_log.sh

Interfaces:
- has_migration <name> true only if last record for <name> is apply.
- log_apply <name>, log_undo <name>.
- Back-compat: lines without leading verb count as apply.

- [ ] Step 1: Write failing bash test for state parsing.
- [ ] Step 2: Implement migration_state() and update has_migration.
- [ ] Step 3: Add log_apply/log_undo; keep log_migration as alias for log_apply.
- [ ] Step 4: Run bash -n and the test.

### Task 2: Feature registry and selection persistence

Files:
- Create: setup/lib/features.sh
- Create: ~/.config/yf-nvim/features (runtime, outside repo)

Interfaces:
- feature_enabled <name> reads desired state (default from profile).
- resolve_profile <name> expands a profile to a feature set.
- save_selection, load_selection.
- Dependency enforcement.

- [ ] Step 1: Define feature list, dependencies, profiles in bash arrays.
- [ ] Step 2: Implement resolve_profile.
- [ ] Step 3: Implement load/save with defaults.
- [ ] Step 4: Implement dependency closure + conflict checks.

### Task 3: Split setup.sh into area modules

Files:
- Create: setup/lib/common.sh, setup/lib/tui.sh, setup/lib/migrations.sh
- Create: setup/migrations/{core,shell,tmux,git,ai,dotnet,embedded,wsl}.sh
- Modify: setup.sh -> entrypoint sourcing modules

Interfaces:
- register_migration <name> <feature> <up_fn> <down_fn>
- reconcile_all iterates registered migrations.

- [ ] Step 1: Extract common helpers (distro, ensure_symlink, cmd_exists, pkg_installed).
- [ ] Step 2: Move each migration into its area file, preserving bodies.
- [ ] Step 3: Add down functions (conservative policy).
- [ ] Step 4: Make setup.sh source modules and call reconcile_all.
- [ ] Step 5: bash -n everything.

### Task 4: Interactive TUI and CLI flags

Files:
- Modify: setup/lib/tui.sh, setup.sh

Interfaces:
- Flags: --profile, --features, --all, --noninteractive, --purge, --interactive.
- Interactive menu toggles features; d done.

- [ ] Step 1: Argument parsing.
- [ ] Step 2: Noninteractive resolution (persisted -> profile -> full).
- [ ] Step 3: Interactive loop with dependency-aware toggling.
- [ ] Step 4: Persist selection; print summary.

### Task 5: Reconcile up/down on re-run

Files:
- Modify: setup/lib/migrations.sh

Interfaces:
- reconcile_migration <name> runs up/down per desired state and logs.

- [ ] Step 1: Implement reconcile with state checks.
- [ ] Step 2: Ensure up external-install guards (Task 6) are called.
- [ ] Step 3: Test toggling a feature twice and inspect log.

### Task 6: External-install awareness in up

Files:
- Modify: all setup/migrations/*.sh up functions

- [ ] Step 1: Add cmd_exists/pkg_installed/git_clone_present helpers.
- [ ] Step 2: Guard each up function; print "already installed (external)" when applicable.
- [ ] Step 3: Ensure guards return 0 so the migration records as applied.

### Task 7: Nvim profile module

Files:
- Create: lua/config/profile.lua
- Create: tests/profile/run.lua

Interfaces:
- require("config.profile").current() -> string.
- .has(feature) -> boolean.
- Reads NVIM_PROFILE env, then ~/.config/yf-nvim/profile, default full.
- Reads feature overrides from ~/.config/yf-nvim/features.

- [ ] Step 1: Write failing Lua test.
- [ ] Step 2: Implement profile resolution + feature loading.
- [ ] Step 3: Run test headlessly.

### Task 8: Reorganize nvim plugins by feature

Files:
- Move: lua/plugins/*.lua -> lua/plugins/{core,ai,dotnet,embedded}/
- Modify: lua/config/lazy.lua

- [ ] Step 1: Create directories and move files (git mv).
- [ ] Step 2: Update lazy.lua to explicit, conditional imports.
- [ ] Step 3: Remove auto-import of plugins.
- [ ] Step 4: Verify headless nvim starts with NVIM_PROFILE=minimal.

### Task 9: Guard options/autocmds/keymaps by feature

Files:
- Modify: lua/config/options.lua, lua/config/autocmds.lua, lua/config/keymaps.lua

- [ ] Step 1: Wrap roslyn lsp config in has("dotnet").
- [ ] Step 2: Wrap PlatformIO autocmds in has("embedded").
- [ ] Step 3: Wrap dotnet/build keymap requires in feature checks.

### Task 10: LazyVim extras gating

Files:
- Modify: init.lua
- Create: lazyvim.base.json if needed

- [ ] Step 1: Decide extras strategy (Lua imports preferred).
- [ ] Step 2: Move profile-gated extras into lazy.lua conditional imports.
- [ ] Step 3: Keep lazyvim.json for always-on extras only.

### Task 11: Documentation and migration table

Files:
- Modify: README.md, AGENTS.md

- [ ] Step 1: Update README migration table with feature column and down notes.
- [ ] Step 2: Document profiles, TUI, env vars, purge.
- [ ] Step 3: Update AGENTS.md conventions (down migrations, feature tags).

### Task 12: End-to-end smoke test

- [ ] Step 1: bash -n all scripts.
- [ ] Step 2: Run Lua profile test.
- [ ] Step 3: Manual: fresh-ish run with --features core --noninteractive, then toggle ai on and verify undo/apply log.
- [ ] Step 4: Manual: NVIM_PROFILE=minimal nvim and check :Lazy.

## Open follow-ups

- Auto-detect feature parity between bash and Lua (lint).
- Package removal safety heuristics for --purge.
- Per-feature docs under docs/.

---

### Task 0: Decide and bootstrap the setup language

Files:
- Modify: setup.sh (convert to bootstrap shim)
- Create: setup/main.py, setup/features.py, setup/migrations.py, setup/tui.py

- [ ] Step 1: Record the decision in the spec (done: Python 3 stdlib orchestrator).
- [ ] Step 2: Write a bash shim that ensures python3 (install via package manager if missing) and execs setup/main.py with forwarded args.
- [ ] Step 3: Port the migration log state logic to Python first (highest value, easiest to test) and add pytest/unittest tests under tests/setup/.
- [ ] Step 4: Port feature registry + dependency resolution.
- [ ] Step 5: Port migrations incrementally, keeping their shell bodies via subprocess initially.
- [ ] Step 6: Remove the old bash migration modules once parity is reached.

### Bootstrap detail (added to Task 0)

- [ ] Step 0a: Implement distro detection + python3 install in the shim before
      exec, with manual-instruction fallback for unsupported distros.
- [ ] Step 0b: Export `YF_DISTRO` and forwarded args; Python reads these.
- [ ] Step 0c: Add a smoke test: run the shim on a container without python3
      and confirm it installs + delegates.
