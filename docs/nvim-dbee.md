# Building nvim-dbee (for WSL users)

If you're using WSL, the dbee backend needs to be built and run on Windows due to Azure authentication requirements. A build script is provided in `plugin-forks/nvim-dbee/build-for-wsl.sh`.

To build the dbee backend:

```bash
cd plugin-forks/nvim-dbee
./build-for-wsl.sh
```

**Note:** This script must be run manually. It builds the Windows executable and places it in `/mnt/c/__Projects/dbee.exe`.
