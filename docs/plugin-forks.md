# Forked/vendored plugins (`plugin-forks/`)

`plugin-forks/` holds plugin source vendored directly into this repo (via
`dir = ...` in the corresponding `lua/plugins/*.lua` spec, not lazy.nvim's
normal git-clone-from-a-remote flow) instead of being pulled from upstream.
This is used either to patch/extend an existing plugin, or for small
fully custom plugins that aren't published anywhere.

| Fork | Loaded from | Based on | Why it's vendored here |
|---|---|---|---|
| `nvim-dbee` | `lua/plugins/dbee.lua` | [kndndrj/nvim-dbee](https://github.com/kndndrj/nvim-dbee) | Adds Azure AD/SQL authentication support (see its `AZURE_SQL_AUTH.md`) and a Go-based install method; on WSL its backend needs to be built as a native Windows binary (see [build instructions](#building-nvim-dbee-for-wsl-users) below). Currently `enabled = false`. |
| `dotbee` | `lua/plugins/dotnet-msg-test.lua` | custom, not based on an upstream plugin | Early/WIP experiment for a floating UI to surface .NET debug messages. Currently `enabled = false`, mostly stubbed out (`vim.notify` placeholders). |
| `neotest` | `lua/plugins/test.lua` | [nvim-neotest/neotest](https://github.com/nvim-neotest/neotest) | Vendored copy used together with the `neotest-dotnet` fork below; actively used (`lazy = false`). |
| `neotest-dotnet` | `lua/plugins/test.lua` | [Issafalcon/neotest-dotnet](https://github.com/Issafalcon/neotest-dotnet) | Vendored copy of the neotest .NET adapter; actively used (`lazy = false`). |
| `last-file-rec` | `lua/plugins/last-file-recorder.lua` | custom, not based on an upstream plugin | Small plugin that records the last real (non-`term://`/`oil://`/etc.) file buffer opened, to `stdpath("cache")/last_file.txt`. Actively used (`lazy = false`). |

## Building nvim-dbee (for WSL users)

If you're using WSL, the dbee backend needs to be built and run on Windows due to Azure authentication requirements. A build script is provided in `plugin-forks/nvim-dbee/build-for-wsl.sh`.

To build the dbee backend:

```bash
cd plugin-forks/nvim-dbee
./build-for-wsl.sh
```

**Note:** This script must be run manually. It builds the Windows executable and places it in `/mnt/c/__Projects/dbee.exe`.
