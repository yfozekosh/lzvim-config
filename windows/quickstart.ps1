# Fresh-Windows-machine bootstrap for this dotfiles repo. Meant to be
# fetched and run directly (see README.md's "Quick start (Windows + WSL)"
# section for the curl one-liner) - it doesn't assume the repo is cloned
# anywhere yet.
#
# What it does, in order:
#   1. Installs PowerShell 7 via winget (if missing).
#   2. Installs Alacritty via winget (if missing).
#   3. Installs the JetBrainsMono Nerd Font via winget (if missing).
#   4. Detects the default WSL distro (ignoring Docker Desktop's
#      docker-desktop/docker-desktop-data distros) and its default user.
#   5. Asks for confirmation before touching anything inside WSL.
#   6. If confirmed: clones this repo into ~/.config/nvim in that distro and
#      runs setup.sh there, then runs windows/setup.ps1 from the
#      newly-cloned repo to link Alacritty's config.
#
# Usage (from a normal Windows PowerShell, NOT inside WSL):
#   curl -fsSL https://raw.githubusercontent.com/yfozekosh/lzvim-config/main/windows/quickstart.ps1 -o quickstart.ps1
#   powershell -ExecutionPolicy Bypass -File .\quickstart.ps1

$ErrorActionPreference = "Stop"

function Test-Command($name) {
    return $null -ne (Get-Command $name -ErrorAction SilentlyContinue)
}

if (-not (Test-Command "winget")) {
    Write-Error "winget not found. Install 'App Installer' from the Microsoft Store, then re-run this script."
    exit 1
}

function Install-WingetPackage($id, $friendlyName) {
    Write-Host "== Installing $friendlyName ==" -ForegroundColor Cyan
    $installed = winget list --id $id -e 2>$null | Select-String ([regex]::Escape($id))
    if ($installed) {
        Write-Host "$friendlyName already installed, skipping."
    } else {
        winget install -e --id $id --accept-package-agreements --accept-source-agreements
    }
}

Install-WingetPackage "Microsoft.PowerShell" "PowerShell 7"
Install-WingetPackage "Alacritty.Alacritty" "Alacritty"
Install-WingetPackage "DEVCOM.JetBrainsMonoNerdFont" "JetBrainsMono Nerd Font"

# ---- Detect the default WSL distro (excluding Docker Desktop's distros) ----
Write-Host "`n== Detecting default WSL distro ==" -ForegroundColor Cyan

# `wsl -l -v` marks the default distro with a leading '*' and includes
# STATE/VERSION columns; output comes back as UTF-16 with embedded nulls
# through PowerShell's pipeline, so strip those before parsing lines.
$wslListRaw = (wsl.exe -l -v 2>$null) -replace "`0", ""
$distroLines = $wslListRaw | Select-Object -Skip 1 | Where-Object { $_.Trim() -ne "" }

$defaultDistro = $null
$fallbackDistro = $null
foreach ($line in $distroLines) {
    $tokens = $line.Trim() -split "\s+"
    if ($tokens.Count -eq 0) { continue }

    $isDefault = $false
    $name = $tokens[0]
    if ($name -eq "*") {
        $isDefault = $true
        $name = $tokens[1]
    }

    if ($name -match "^docker-desktop") { continue } # skip Docker Desktop's own distros

    if ($isDefault) { $defaultDistro = $name }
    elseif (-not $fallbackDistro) { $fallbackDistro = $name }
}

$distro = $defaultDistro
if (-not $distro) { $distro = $fallbackDistro }

if (-not $distro) {
    Write-Error "Could not find a non-Docker WSL distro. Install one first, e.g.: wsl --install -d FedoraLinux-44"
    exit 1
}

$wslUser = (wsl.exe -d $distro -- whoami).Trim()

Write-Host "`nDetected WSL distro '$distro' (user '$wslUser')." -ForegroundColor Yellow
$confirm = Read-Host "Clone lzvim-config into ~/.config/nvim and run setup.sh there? (y/N)"
if ($confirm -notmatch "^[Yy]") {
    Write-Host "Aborted - nothing else was changed."
    exit 0
}

Write-Host "`n== Cloning repo and running setup.sh inside WSL ($distro) ==" -ForegroundColor Cyan
wsl.exe -d $distro -- bash -lc "sudo dnf install -y git && git clone https://github.com/yfozekosh/lzvim-config.git ~/.config/nvim && cd ~/.config/nvim && bash setup.sh"

Write-Host "`n== Linking Alacritty config ==" -ForegroundColor Cyan
$repoSetupPs1 = "\\wsl.localhost\$distro\home\$wslUser\.config\nvim\windows\setup.ps1"
if (Test-Path $repoSetupPs1) {
    powershell -ExecutionPolicy Bypass -File $repoSetupPs1
} else {
    Write-Warning "Could not find $repoSetupPs1 - run windows/setup.ps1 from the cloned repo manually to link Alacritty's config."
}

Write-Host "`nDone." -ForegroundColor Green
