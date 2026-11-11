# Agent instructions for this repo

This repo is a personal dotfiles/Neovim config (LazyVim-based). If you are
an AI agent making changes here, follow these conventions.

## Maintaining `setup.sh` migrations

`setup.sh` is a thin bash bootstrap: it ensures `python3` exists, then execs
`python3 -m provision.main`. The orchestrator and migrations live in
`provision/` (stdlib-only Python). The migration log at
`~/.yf_setup_migrationlog` is a state log (`apply`/`undo` records); a migration
is applied only when its most recent record is `apply`.

When you add, remove, or change a migration:

1. **Always update the migrations table in `README.md`** (under
   "`setup.sh` details") in the same commit. Every migration must have a row
   with its feature and what it does. Keep the table in the same order the
   migrations run in `provision/main.py` (`core`, `build`, `shell`, `tmux`, `git`,
   `node`, `ai`, `dotnet`, `embedded`, `wsl`).
2. Add a `Migration` object in the matching `provision/migrations/<feature>.py`
   module with `up`, `down`, and `check` callables. `up` must start with an
   external-install guard (`cmd_exists`, a file check, or an exact config
   grep) so an existing target is recorded without overwriting it. `down`
   must remove exactly what `up` added; remove shared OS packages only when
   `ctx.purge` is true (the `--purge` flag). Feature-owned packages (for
   example the .NET SDK) may be removed when their feature is unchecked.
3. Branch on `ctx.distro` (Fedora vs Debian/Ubuntu) when the install method
   differs. For unsupported distros, print a warning with manual install
   instructions and return rather than aborting the whole run - unless the
   missing dependency is required by every subsequent migration.
4. Document feature dependencies in `provision/features.py`. If a migration
   depends on something installed by an earlier migration (e.g. needing
   `npm`), place it after that migration and mention the dependency in a
   comment. `core` deliberately keeps `gcc` for Treesitter but leaves C++,
   `make`, and CMake to `build`; `node` is shared by `ai` and `frontend`.
5. Never commit or install secrets/credentials as part of a migration.
   Credential/session files for tools like the Copilot usage scraper live
   outside the repo (e.g. `~/.config/copilot-usage/`), never inside it.
6. Add or update tests under `tests/setup/` for state parsing, feature
   resolution, dependency closure, and reconciliation. Run:
   - `python3 -m unittest discover -s tests/setup`
   - `nvim --headless -u NONE -l tests/profile/run.lua`
   - `python3 -m compileall provision`
   - `bash -n setup.sh`
7. On your own already-configured machine, update
   `~/.yf_setup_migrationlog` (add the new `apply <name> ...` line) so the
   next `./setup.sh` run doesn't redundantly re-apply it.

## Git commits in this repo

- Local git identity is `yfozekosh <yfozekosh@gmail.com>` (repo-local
  config, not global) - see "Committing & pushing" in `README.md`.
- Do not add a `Co-authored-by: Copilot` trailer (see the global
  `~/.copilot/copilot-instructions.md`, itself tracked as
  `copilot-instructions.md` in this repo).
- Push via the Docker + deploy-key method documented in `README.md`
  (`~/github_deploy_key`, never `~/.ssh`).

## General

- Keep `README.md` as the source of truth for anything a fresh machine setup
  depends on. If you add a new top-level tool/config (e.g. a new
  `tmux-scripts/*` widget, a new Windows setup step), document it in
  `README.md` in the same change.
