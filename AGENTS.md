# Agent instructions for this repo

This repo is a personal dotfiles/Neovim config (LazyVim-based). If you are
an AI agent making changes here, follow these conventions.

## Maintaining `setup.sh` migrations

`setup.sh` installs/configures everything needed on a fresh machine, and is
idempotent (see the `run_migration`/`~/.yf_setup_migrationlog` mechanism at
the top of the file - already-applied migrations are skipped on re-run).

When you add, remove, or change a migration in `setup.sh`:

1. **Always update the migrations table in `README.md`** (under
   "`setup.sh` details") in the same commit. Every migration must have a row
   there describing what it does. Keep the table in the same order the
   migrations run in `setup.sh`.
2. Write each migration as a small, idempotent bash function, registered via
   `run_migration "<name>" <function_name>`. Prefer checks that make re-runs
   a no-op (e.g. skip installing if already present) over relying solely on
   the migration log.
3. Branch on `$DISTRO` (Fedora vs Debian/Ubuntu) when the install method
   differs. For distros you don't support, print a warning with manual
   install instructions and continue rather than calling `exit 1` and
   aborting the whole setup run - unless the missing dependency is required
   by every subsequent migration (existing convention for the base
   `install_packages`/`install_cmake` migrations is to exit for truly
   unsupported distros).
4. If a migration depends on something installed by an earlier migration
   (e.g. needing `npm`), place it after that migration in the file, and
   mention the dependency in a comment.
5. Never commit or install secrets/credentials as part of a migration.
   Credential/session files for tools like the Copilot usage scraper live
   outside the repo (e.g. `~/.config/copilot-usage/`), never inside it.
6. After adding a migration, test it (or at least a syntax check via
   `bash -n setup.sh`) before committing, and manually mark it as applied in
   `~/.yf_setup_migrationlog` on your own already-configured machine so
   `setup.sh` doesn't try to redundantly re-run it there.

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
