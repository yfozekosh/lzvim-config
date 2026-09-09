# Shared clipboard (Alacritty + tmux + nvim, WSL)

On WSL, Alacritty runs as a native Windows process, but tmux and nvim run
inside Linux, so a mouse-selection copy or a `y` in nvim only lands in an
internal Linux buffer (tmux's paste buffer / nvim's default register) unless
something explicitly bridges it to the real Windows clipboard.

## The win32yank bridge

`setup.sh`'s `install_win32yank` migration installs
[`win32yank.exe`](https://github.com/equalsraf/win32yank) to `~/.local/bin`
(it runs as a native Windows process via WSL interop, no X server or
`wl-copy` needed). Two things then use it to read/write the real Windows
clipboard:

- `.tmux.conf` sets `copy-command` to `win32yank.exe -i --crlf`, so both
  mouse-drag copies and `prefix + [` copy-mode `y` write straight to the
  Windows clipboard.
- `lua/config/options.lua` sets `vim.g.clipboard` to use `win32yank.exe` for
  the `+`/`*` registers (only on WSL, only if the binary is found), plus
  `clipboard=unnamedplus`, so nvim yank/paste/delete use the Windows
  clipboard by default.

Since Alacritty is already a native Windows app, its own mouse-selection
copy/paste already uses the Windows clipboard directly - no extra config
needed there.

## OSC 52 (apps like the Copilot CLI's own click-to-copy)

Some tools write to the clipboard via an OSC 52 escape sequence instead of
tmux's copy-command path. Relaying that straight through Alacritty doesn't
work on WSL - OSC 52 gets silently dropped somewhere in the WSL<->Windows
conpty layer that Alacritty's `wsl.exe` integration goes through. This is a
known, unfixable-from-here Windows limitation (see
[alacritty/alacritty#7962](https://github.com/alacritty/alacritty/issues/7962)).
`windows/alacritty.toml` still sets `terminal.osc52 = "CopyPaste"` since
it's correct/harmless, it just doesn't help here.

Instead, `.tmux.conf` sets `set-clipboard on` plus a `pane-set-clipboard`
hook that pipes any OSC 52 write tmux sees straight into `win32yank.exe`,
bypassing Alacritty's relay entirely:

```tmux
set-option -g set-clipboard on
set-hook -g pane-set-clipboard 'run-shell "tmux save-buffer - | win32yank.exe -i --crlf"'
```

This only catches *plain* OSC 52 sequences though. If the writing app
detects it's inside tmux (`$TMUX` set), it may instead wrap the sequence in
tmux's raw passthrough format (`\ePtmux;...\e\\`), which tells tmux to
relay it untouched to the outer terminal, skipping tmux's own interception
and hitting the same dead end.

The Copilot CLI does exactly this: it checks `process.env.TMUX` /
`process.env.TERM` to decide whether to wrap its OSC 52 clipboard write in
tmux passthrough format before emitting it. So `.bash_profile_yf` defines a
`copilot() (...)` wrapper function that unsets `$TMUX` just for that one
process, making it emit the plain (non-wrapped) form instead:

```bash
copilot() (
  unset TMUX
  command copilot "$@"
)
```

`$TERM` is left untouched (`screen-256color`, which doesn't start with
`tmux`), so tmux's own terminal-capability detection for the pane is
unaffected - only Copilot's own tmux self-detection changes. This has one
other minor, expected side effect: the Copilot CLI only probes for/enables
"synchronized output" screen updates (to reduce redraw flicker) when it
thinks it's *not* in tmux. With detection disabled, Copilot now runs that
probe; tmux 3.7c already supports and forwards synchronized-output escape
codes, so this is expected to be neutral-to-positive, not a regression, and
the probe itself no-ops safely on failure.

After all pieces are in place, copying in any of the apps (nvim, tmux
mouse-drag/copy-mode, Copilot CLI's click-to-copy) and pasting in any other
(including into Windows applications) should just work.

## WSL interop persistence (`WSLInterop` / binfmt_misc)

All of the above depends on WSL being able to execute native `.exe`
binaries (`win32yank.exe`, `clip.exe`, `powershell.exe`, ...) at all, which
requires the `WSLInterop` entry to be registered in
`/proc/sys/fs/binfmt_misc/`.

Fedora's official WSL rootfs image ships with `[boot] systemd=true` in
`/etc/wsl.conf` by default. Normally WSL's own `/init` registers
`WSLInterop` before systemd takes over as PID 1. But systemd's own
`systemd-binfmt.service` only recognizes formats declared in
`/etc|/usr/lib/binfmt.d/*.conf` - it doesn't know about `WSLInterop` - and
during its own boot-time binfmt initialization it can end up clearing
entries it doesn't recognize, wiping out WSL's earlier registration. When
this happens, every `.exe` call fails with `cannot execute binary file:
Exec format error`, breaking clipboard sharing entirely.

`setup.sh`'s `fix_wsl_interop_persistence` migration adds a `[boot]
command=` line to `/etc/wsl.conf` (WSL's own native boot-time hook, runs as
root before any user session, independent of systemd) that re-registers
`WSLInterop` on every boot:

```
[boot]
command="echo ':WSLInterop:M::MZ::/init:PF' > /proc/sys/fs/binfmt_misc/register 2>/dev/null || true"
```

It also applies the fix immediately when the migration runs, so the
current boot doesn't need a restart. `systemd=true` is left in place -
disabling systemd was considered and explicitly rejected (useful for other
things, e.g. Docker), so this fix works around the interaction instead of
removing systemd.
