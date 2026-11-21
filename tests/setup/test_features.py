from __future__ import annotations

import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from provision.features import (
    FEATURES,
    KIND_ORDER,
    can_disable,
    dependency_closure,
    load_selection,
    normalize_selection,
    resolve_profile,
    save_selection,
)
from provision.manifest import ALIASES, DETAILS, KINDS, LEGACY_CORE_IMPLIES, PROFILES


class ManifestTests(unittest.TestCase):
    def test_kinds_are_consistent(self) -> None:
        self.assertEqual(KIND_ORDER, KINDS)
        for feature in FEATURES.values():
            self.assertIn(feature.kind, KINDS, feature.id)

    def test_dependencies_exist(self) -> None:
        for feature in FEATURES.values():
            for dep in feature.depends:
                self.assertIn(dep, FEATURES, f"{feature.id} depends on {dep}")
                self.assertNotEqual(dep, feature.id)

    def test_profiles_and_aliases_reference_real_features(self) -> None:
        for name, features in PROFILES.items():
            for feature in features:
                self.assertIn(feature, FEATURES, f"profile {name} -> {feature}")
        for alias, features in ALIASES.items():
            self.assertNotIn(alias, FEATURES, f"alias {alias} shadows a feature")
            for feature in features:
                self.assertIn(feature, FEATURES, f"alias {alias} -> {feature}")
        for feature in LEGACY_CORE_IMPLIES:
            self.assertIn(feature, FEATURES)

    def test_full_includes_every_non_auto_feature(self) -> None:
        expected = {feature.id for feature in FEATURES.values() if not feature.auto}
        self.assertEqual(expected, set(PROFILES["full"]))

    def test_every_feature_has_os_and_nvim_details(self) -> None:
        self.assertEqual(set(DETAILS), set(FEATURES))
        for fid, feature in FEATURES.items():
            self.assertTrue(feature.os_details, fid)
            self.assertTrue(feature.nvim_details, fid)
            self.assertEqual(set(DETAILS[fid]), {"os", "nvim"})
            for item in feature.os_details + feature.nvim_details:
                self.assertTrue(item.strip(), f"{fid}: empty detail line")

    def test_core_details_list_every_package(self) -> None:
        details = " ".join(FEATURES["core"].os_details)
        for package in (
            "tmux",
            "git",
            "gcc",
            "neovim",
            "bat",
            "fastfetch",
            "vim",
            "wget",
            "curl",
            "xz",
            "xz-utils",
            "gawk",
            "unzip",
        ):
            self.assertIn(package, details)


class FeatureTests(unittest.TestCase):
    def test_dependency_closure_pulls_core(self) -> None:
        self.assertEqual(dependency_closure({"copilot"}), {"copilot", "core", "node"})
        self.assertEqual(dependency_closure({"riscv-asm"}), {"riscv-asm", "core"})
        self.assertEqual(dependency_closure({"clangd"}), {"clangd", "core", "nvim"})
        self.assertEqual(dependency_closure({"gef"}), {"gef", "core"})
        self.assertEqual(dependency_closure({"frontend"}), {"frontend", "core", "node", "nvim"})
        self.assertEqual(dependency_closure({"docker"}), {"docker", "tmux"})

    def test_dependency_closure_is_transitive(self) -> None:
        self.assertIn("core", dependency_closure({"dotnet"}))
        self.assertIn("node", dependency_closure({"copilot-usage"}))

    def test_profiles_are_subsets_of_full(self) -> None:
        with patch("provision.features.is_wsl", return_value=False):
            full = resolve_profile("full")
            minimal = resolve_profile("minimal")
            frontend = resolve_profile("frontend")
        self.assertTrue(
            {
                "core",
                "nvim",
                "build",
                "shell",
                "tmux",
                "docker",
                "git",
                "node",
                "copilot",
                "claude",
                "copilot-usage",
                "frontend",
                "dotnet",
                "riscv-asm",
                "clangd",
                "gef",
            }
            <= full
        )
        self.assertTrue(minimal <= full)
        self.assertTrue(frontend <= full)

    def test_frontend_profile_has_node_but_not_ai(self) -> None:
        frontend = resolve_profile("frontend")
        self.assertTrue({"core", "frontend", "node"} <= frontend)
        self.assertFalse({"copilot", "claude", "copilot-usage"} & frontend)
        self.assertNotIn("build", frontend)

    def test_embedded_profile_includes_build_tools(self) -> None:
        embedded = resolve_profile("embedded")
        self.assertTrue({"riscv-asm", "clangd", "build", "gef"} <= embedded)
        self.assertNotIn("frontend", embedded)

    def test_profiles_include_nvim_and_docker_panel(self) -> None:
        for name in ("minimal", "work", "frontend", "embedded", "dotnet", "full"):
            profile = resolve_profile(name)
            self.assertIn("nvim", profile)
            self.assertIn("docker", profile)

    def test_can_disable_respects_dependents(self) -> None:
        self.assertFalse(can_disable("core", {"core", "copilot"}))
        self.assertFalse(can_disable("core", {"core"}))
        self.assertFalse(can_disable("node", {"core", "node", "copilot"}))
        self.assertFalse(can_disable("node", {"core", "node", "frontend"}))
        self.assertFalse(can_disable("tmux", {"tmux", "docker"}))
        self.assertTrue(can_disable("node", {"core", "node"}))
        self.assertTrue(can_disable("copilot", {"core", "copilot"}))
        self.assertTrue(can_disable("copilot-usage", {"core", "copilot-usage"}))
        self.assertTrue(can_disable("docker", {"tmux", "docker"}))
        self.assertTrue(can_disable("gef", {"core", "gef"}))

    def test_normalize_adds_core(self) -> None:
        self.assertIn("core", normalize_selection({"shell"}))

    def test_normalize_expands_legacy_aliases(self) -> None:
        self.assertTrue(
            {"copilot", "claude", "copilot-usage", "node", "core"}
            <= normalize_selection({"ai"})
        )
        self.assertTrue({"riscv-asm", "clangd", "core"} <= normalize_selection({"embedded"}))
        with patch("provision.features.is_wsl", return_value=True):
            self.assertTrue(
                {"wsl-fonts", "wsl-clipboard", "wsl-interop", "core"}
                <= normalize_selection({"wsl"})
            )

    def test_normalize_drops_wsl_features_outside_wsl(self) -> None:
        selected = normalize_selection({"core", "wsl-fonts", "wsl-clipboard"})
        self.assertFalse({"wsl-fonts", "wsl-clipboard", "wsl-interop"} & selected)

    def test_selection_round_trip(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "features"
            save_selection(path, "work", {"core", "shell", "copilot", "claude"})
            profile, features = load_selection(path)
            self.assertEqual(profile, "work")
            self.assertTrue({"core", "shell", "copilot", "claude"} <= features)
            self.assertNotIn("dotnet", features)

    def test_custom_selection_does_not_inherit_new_features(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "features"
            path.write_text("profile=custom\ncore=on\nshell=on\n", encoding="utf-8")
            profile, features = load_selection(path)
            self.assertEqual(profile, "custom")
            self.assertTrue({"core", "shell", "nvim"} <= features)
            self.assertNotIn("build", features)
            self.assertNotIn("frontend", features)
            self.assertNotIn("docker", features)
            self.assertNotIn("gef", features)

    def test_custom_selection_can_disable_nvim(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "features"
            path.write_text("profile=custom\ncore=on\nnvim=off\n", encoding="utf-8")
            _, features = load_selection(path)
            self.assertNotIn("nvim", features)

    def test_custom_selection_expands_legacy_ai(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "features"
            path.write_text(
                "profile=custom\ncore=on\nai=on\nembedded=on\n",
                encoding="utf-8",
            )
            _, features = load_selection(path)
            self.assertTrue(
                {"copilot", "claude", "copilot-usage", "riscv-asm", "clangd"} <= features
            )
            self.assertFalse({"ai", "embedded"} & features)

    def test_wsl_profile_enables_platform_features(self) -> None:
        with patch("provision.features.is_wsl", return_value=True):
            features = resolve_profile("minimal")
        self.assertTrue({"wsl-fonts", "wsl-clipboard", "wsl-interop"} <= features)

    def test_custom_wsl_selection_can_disable_one_platform_feature(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "features"
            path.write_text(
                "profile=custom\ncore=on\nnvim=on\nwsl-fonts=off\n",
                encoding="utf-8",
            )
            with patch("provision.features.is_wsl", return_value=True):
                _, features = load_selection(path)
            self.assertNotIn("wsl-fonts", features)
            self.assertTrue({"wsl-clipboard", "wsl-interop"} <= features)


if __name__ == "__main__":
    unittest.main()
