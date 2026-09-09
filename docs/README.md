# Docs

Deeper write-ups that would clutter `README.md` but are worth keeping around
for future reference.

- [`clipboard.md`](clipboard.md) - how Alacritty + tmux + nvim + the Copilot
  CLI all share the real Windows clipboard on WSL (win32yank bridge, OSC 52
  interception, the tmux-passthrough gotcha, and the `WSLInterop`
  binfmt_misc persistence fix).
- [`nvim-dbee.md`](nvim-dbee.md) - building the nvim-dbee backend on WSL.
