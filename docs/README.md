# Docs

Deeper write-ups that would clutter `README.md` but are worth keeping around
for future reference.

- [`asm.md`](asm.md) - GNU as/RISC-V and ld-script support: tree-sitter
  parsers and highlight queries, `asm-lsp` plus the local RISC-V
  pseudo-instruction/register/CSR supplement, the patched `rvfmt` formatter,
  and how to enable per-project compiler diagnostics.
- [`clipboard.md`](clipboard.md) - how Alacritty + tmux + nvim + the Copilot
  CLI all share the real Windows clipboard on WSL (win32yank bridge, OSC 52
  interception, the tmux-passthrough gotcha, and the `WSLInterop`
  binfmt_misc persistence fix).
- [`plugin-forks.md`](plugin-forks.md) - what's in `plugin-forks/`, what
  each fork is based on and why, including nvim-dbee's WSL build step.
- [`dotnet-roslyn-troubleshooting.md`](dotnet-roslyn-troubleshooting.md) -
  why C# LSP features (go-to-definition, workspace symbols) can silently
  return nothing: stale `PATH`/`DOTNET_ROOT`, the shared long-lived Roslyn
  daemon, `nugetPAT`/private NuGet feed auth, and NuGet's HTTP cache. Also
  covers `:RoslynDoctor` and the automatic failure notifications in
  `lua/roslyn_diagnostics.lua`.
