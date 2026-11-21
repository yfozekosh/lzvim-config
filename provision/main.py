"""Entry point for the provisioning orchestrator."""

from __future__ import annotations

import argparse
import os
import sys
from pathlib import Path

from .common import distro_id
from .features import (
    FEATURES,
    all_feature_ids,
    expand_aliases,
    load_selection,
    save_selection,
    resolve_profile,
    normalize_selection,
)
from .manifest import PROFILES
from .models import Migration, MigrationLog, SetupContext
from .tui import FeatureSelector


def purge_default() -> bool:
    """Purge OS packages on undo unless SETUP_PURGE explicitly disables it."""
    value = os.environ.get("SETUP_PURGE")
    if value is None:
        return True
    return value.strip().lower() not in {"0", "false", "no", "off"}


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Yurii's config setup")
    parser.add_argument(
        "--profile",
        choices=list(PROFILES),
        help="profile preset",
    )
    parser.add_argument("--features", help="comma-separated feature list")
    parser.add_argument("--all", action="store_true", help="enable all applicable features")
    parser.add_argument("--interactive", action="store_true", help="force interactive TUI")
    parser.add_argument("--noninteractive", action="store_true", help="never prompt")
    parser.add_argument(
        "--purge",
        action=argparse.BooleanOptionalAction,
        default=purge_default(),
        help=(
            "remove OS packages when undoing migrations "
            "(default: on; use --no-purge or SETUP_PURGE=0 to keep them)"
        ),
    )
    return parser.parse_args(argv)


def determine_distro() -> str:
    return os.environ.get("YF_DISTRO") or distro_id()


def should_prompt(args: argparse.Namespace, stdin_is_tty: bool) -> bool:
    """Prompt on a TTY unless the caller made an explicit selection."""
    explicit_selection = args.all or bool(args.profile) or bool(args.features)
    return args.interactive or (
        not explicit_selection and stdin_is_tty and not args.noninteractive
    )


def desired_features(args: argparse.Namespace, state_dir: Path) -> tuple[str, set[str]]:
    selection_path = state_dir / "features"
    if args.all:
        return "full", normalize_selection(set(all_feature_ids()))
    if args.features:
        requested = {item.strip() for item in args.features.split(",") if item.strip()}
        unknown = expand_aliases(requested) - FEATURES.keys()
        if unknown:
            raise SystemExit(f"unknown feature(s): {', '.join(sorted(unknown))}")
        return "custom", normalize_selection(requested)
    if args.profile:
        return args.profile, normalize_selection(resolve_profile(args.profile))
    return load_selection(selection_path)


def build_migrations(ctx: SetupContext) -> list[Migration]:
    from .migrations import ai, build, core, dotnet, embedded, gef, git, node, nvim, shell, tmux, wsl

    # nvim runs after core installs neovim; build must precede tmux (it
    # compiles tmux-mem-cpu-load when selected); node must precede ai/frontend.
    modules = [core, nvim, build, shell, tmux, git, node, ai, dotnet, embedded, gef, wsl]
    result = []
    for module in modules:
        result.extend(module.build(ctx))
    return result


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv if argv is not None else sys.argv[1:])
    repo = Path(__file__).resolve().parent.parent
    home = Path.home()
    state_dir = home / ".config" / "yf-nvim"
    state_dir.mkdir(parents=True, exist_ok=True)
    distro = determine_distro()
    log = MigrationLog(home / ".yf_setup_migrationlog")
    profile_name, features = desired_features(args, state_dir)
    features = normalize_selection(features)

    # Interactive selection. Explicit --profile/--features/--all selections
    # must win; otherwise a TTY always gets the selector, including re-runs.
    selection_path = state_dir / "features"
    if should_prompt(args, sys.stdin.isatty()):
        selector = FeatureSelector(features)
        features = normalize_selection(selector.run())
        profile_name = "custom"

    save_selection(selection_path, profile_name, features)
    (state_dir / "profile").write_text(profile_name + "\n", encoding="utf-8")

    ctx = SetupContext(
        repo=repo,
        home=home,
        distro=distro,
        purge=args.purge,
        desired=set(features),
        log=log,
        profile_name=profile_name,
    )

    migrations = build_migrations(ctx)
    reconcile(migrations, ctx.desired, log)

    print("Setup complete.")
    return 0


def reconcile(migrations: list[Migration], desired: set[str], log: MigrationLog) -> None:
    """Apply selected migrations and undo unselected ones."""
    for migration in migrations:
        desired_on = migration.feature in desired
        applied = log.is_applied(migration.name)
        if not desired_on:
            if applied or migration.check():
                print(f"Undoing migration: {migration.name}")
                migration.run_down(log)
            else:
                print(f"Migration {migration.name} not selected; skipping.")
            continue
        # desired on
        if migration.always:
            print(f"Running migration: {migration.name}")
            migration.up()
            if not applied:
                log.apply(migration.name)
            continue
        if not applied:
            print(f"Applying migration: {migration.name}")
            migration.run_up(log)
        else:
            # Already applied: re-run up idempotently so externally removed
            # targets get repaired without writing another apply record.
            print(f"Ensuring migration: {migration.name}")
            migration.up()


if __name__ == "__main__":
    raise SystemExit(main())
