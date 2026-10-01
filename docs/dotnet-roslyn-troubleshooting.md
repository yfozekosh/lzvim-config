# .NET SDK, NuGet auth, and Roslyn troubleshooting

This documents a real debugging session where C# LSP features (workspace
symbols, cross-project go-to-definition) silently returned empty results in
nvim, and the layered causes behind it. If Roslyn/`gd`/workspace symbols
misbehave again, read this before re-diagnosing from scratch, and try
`:RoslynDoctor` first (see [below](#roslyndoctor-and-notifications)).

## The four layered issues

Symptoms can look identical ("no results", empty pickers) but come from
different causes that often compound:

1. **Stale `PATH`/`DOTNET_ROOT` in already-running shells/processes.**
   `dotnet-install.sh` installs to `~/.dotnet`, but if `~/.dotnet` isn't
   ahead of the system package manager's `dotnet` (e.g. `/usr/bin/dotnet`)
   on `PATH`, the wrong SDK gets resolved. Any shell/terminal/nvim process
   started *before* fixing `PATH` keeps the old, broken environment for its
   entire lifetime - reloading `.bashrc` in a new shell doesn't fix
   already-running processes.

2. **The Roslyn daemon is a long-lived, shared background process.**
   `roslyn-language-server` (the per-nvim stdio client) connects to a
   separate `Microsoft.CodeAnalysis.LanguageServer --daemon --pipe <fixed
   name>` process that does the actual MSBuild project loading. This daemon
   is **not** restarted when you `:qa` and reopen nvim - every nvim
   instance on the machine reuses the *same* daemon (same pipe name), and it
   keeps whatever environment (`PATH`, `DOTNET_ROOT`, `nugetPAT`, ...) it had
   when it was first spawned. If you fix your environment but nothing
   changes, the daemon itself needs to be killed:

   ```bash
   pgrep -af 'CodeAnalysis.LanguageServer --daemon'
   pgrep -af 'roslyn-language-server'   # stdio clients attached to it
   kill <daemon_pid> <client_pids...>   # it gets respawned fresh next :edit
   ```

   After killing it, quit and reopen nvim (or open any `.cs` file) so a new
   daemon spawns with your current (fixed) environment.

3. **Private NuGet feed auth (`nugetPAT`).** If `~/.nuget/NuGet.Config` (or
   a repo-local `NuGet.Config`) references a package source credential like
   `%nugetPAT%`, that environment variable must be exported *before* nvim
   starts. Without it, every project that (transitively) depends on a
   package from that feed fails to restore with a 401, and Roslyn can't
   fully load those projects - same-file features (syntax, same-file
   go-to-definition) still work, but anything needing another project's
   symbols (go-to-definition into a referenced project, workspace symbols
   across projects) silently returns nothing.

   `nugetPAT` is expected to live in `~/.nugetPAT` and gets exported from
   `.bashrc`:

   ```bash
   if [ -f "$HOME/.nugetPAT" ]; then
     export nugetPAT="$(cat "$HOME/.nugetPAT" | tr -d '[:space:]')"
   fi
   ```

4. **NuGet's HTTP cache remembers 401s.** Even after fixing `nugetPAT`, a
   daemon that already saw a 401 for a package source may have cached that
   failure (`~/.local/share/NuGet/http-cache` and/or in-process). Clear it
   and restart the daemon once more:

   ```bash
   dotnet nuget locals http-cache --clear
   ```

### How to tell same-file vs cross-project LSP failures apart

If `gd` works when the target is in the *same file* but not when it's in
another project/file, that's almost always cause (3)/(4) above (NuGet auth),
not (1)/(2). You can confirm by checking `~/.local/state/nvim/lsp.log` for
lines like:

```
[ERROR] ... [LanguageServerProjectSystem] Error while loading .../Foo.csproj: ...
```

- `hostfxr_resolve_sdk2` / "compatible .NET SDK was not found" -> cause (1).
- "401 (Unauthorized)" / "Unable to load the service index" -> cause (3)/(4).

## `:RoslynDoctor` and notifications

`lua/roslyn_diagnostics.lua` (wired up from `lua/plugins/roslyn.lua`) adds
two things so these failures aren't silently buried in `:LspLog` again:

- **`:RoslynDoctor`** - a synchronous command that checks: `dotnet` resolves
  and its version, whether `DOTNET_ROOT`/`nugetPAT` are set, whether a
  `roslyn` client is attached to the current buffer, and whether the Mason
  `roslyn` package is installed. Run it any time C# LSP features seem off.
- **Automatic `vim.notify`** - the plugin wraps Roslyn's `window/logMessage`
  handler. Project-load failures (`Error while loading ...` /
  `Unauthorized`) are classified against known patterns (SDK not found,
  NuGet 401, NuGet feed unreachable) and batched into a single notification
  per failure category (e.g. "NuGet auth failed (401) (12 projects
  affected)") after a short debounce, instead of one popup per project or
  nothing at all.

Because of cause (2) above, note that killing/respawning the shared daemon
mid-session can make old failures notify again even after you've fixed the
underlying issue - that's expected; just wait for the fresh daemon to finish
loading and check `:RoslynDoctor` again.
