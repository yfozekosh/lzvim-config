from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

from provision.features import (
    can_disable,
    dependency_closure,
    load_selection,
    normalize_selection,
    resolve_profile,
    save_selection,
)


class FeatureTests(unittest.TestCase):
    def test_dependency_closure_pulls_core(self) -> None:
        self.assertEqual(dependency_closure({"ai"}), {"ai", "core", "node"})
        self.assertEqual(dependency_closure({"embedded"}), {"embedded", "core"})
        self.assertEqual(dependency_closure({"frontend"}), {"frontend", "core", "node"})
        self.assertEqual(dependency_closure({"docker"}), {"docker", "tmux"})

    def test_dependency_closure_is_transitive(self) -> None:
        self.assertIn("core", dependency_closure({"dotnet"}))

    def test_profiles_are_subsets_of_full(self) -> None:
        full = resolve_profile("full")
        self.assertTrue(
            {
                "core",
                "build",
                "shell",
                "tmux",
                "docker",
                "git",
                "node",
                "ai",
                "frontend",
                "dotnet",
                "embedded",
            }
            <= full
        )
        self.assertTrue(resolve_profile("minimal") <= full)
        self.assertTrue(resolve_profile("frontend") <= full)

    def test_frontend_profile_has_node_but_not_ai(self) -> None:
        frontend = resolve_profile("frontend")
        self.assertTrue({"core", "frontend", "node"} <= frontend)
        self.assertNotIn("ai", frontend)
        self.assertNotIn("build", frontend)

    def test_embedded_profile_includes_build_tools(self) -> None:
        embedded = resolve_profile("embedded")
        self.assertTrue({"embedded", "build"} <= embedded)
        self.assertNotIn("frontend", embedded)

    def test_profiles_include_docker_panel(self) -> None:
        for name in ("minimal", "work", "frontend", "embedded", "dotnet", "full"):
            self.assertIn("docker", resolve_profile(name))

    def test_can_disable_respects_dependents(self) -> None:
        self.assertFalse(can_disable("core", {"core", "ai"}))
        self.assertFalse(can_disable("core", {"core"}))
        self.assertFalse(can_disable("node", {"core", "node", "ai"}))
        self.assertFalse(can_disable("node", {"core", "node", "frontend"}))
        self.assertFalse(can_disable("tmux", {"tmux", "docker"}))
        self.assertTrue(can_disable("node", {"core", "node"}))
        self.assertTrue(can_disable("ai", {"core", "ai"}))
        self.assertTrue(can_disable("docker", {"tmux", "docker"}))

    def test_normalize_adds_core(self) -> None:
        self.assertIn("core", normalize_selection({"shell"}))

    def test_selection_round_trip(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "features"
            save_selection(path, "work", {"core", "shell", "ai"})
            profile, features = load_selection(path)
            self.assertEqual(profile, "work")
            self.assertTrue({"core", "shell", "ai"} <= features)
            self.assertNotIn("dotnet", features)

    def test_custom_selection_does_not_inherit_new_features(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "features"
            path.write_text("profile=custom\ncore=on\nshell=on\n", encoding="utf-8")
            profile, features = load_selection(path)
            self.assertEqual(profile, "custom")
            self.assertTrue({"core", "shell"} <= features)
            self.assertNotIn("build", features)
            self.assertNotIn("frontend", features)
            self.assertNotIn("docker", features)


if __name__ == "__main__":
    unittest.main()
