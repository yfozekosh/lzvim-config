# Windows setup script (run in a normal PowerShell window on Windows, NOT
# inside WSL) - installs Alacritty + the Nerd Font used by this dotfiles
# repo, and links Alacritty's config to the copy tracked in this repo
# (windows/alacritty.toml) so future edits made from WSL apply automatically.
#
# Usage (from PowerShell):
#   powershell -ExecutionPolicy Bypass -File .\setup.ps1
# or, if you can reach this file via \\wsl$\... :
#   powershell -ExecutionPolicy Bypass -File \\wsl$\Fedora\home\<user>\.config\nvim\windows\setup.ps1

$ErrorActionPreference = "Stop"

function Test-Command($name) {
    return $null -ne (Get-Command $name -ErrorAction SilentlyContinue)
}

if (-not (Test-Command "winget")) {
    Write-Error "winget not found. Install 'App Installer' from the Microsoft Store, then re-run this script."
    exit 1
}

Write-Host "== Installing Alacritty ==" -ForegroundColor Cyan
$alacritty = winget list --id Alacritty.Alacritty -e 2>$null | Select-String "Alacritty.Alacritty"
if ($alacritty) {
    Write-Host "Alacritty already installed, skipping."
} else {
    winget install -e --id Alacritty.Alacritty --accept-package-agreements --accept-source-agreements
}

Write-Host "== Installing JetBrainsMono Nerd Font ==" -ForegroundColor Cyan
$font = winget list --id DEVCOM.JetBrainsMonoNerdFont -e 2>$null | Select-String "DEVCOM.JetBrainsMonoNerdFont"
if ($font) {
    Write-Host "JetBrainsMono Nerd Font already installed, skipping."
} else {
    winget install -e --id DEVCOM.JetBrainsMonoNerdFont --accept-package-agreements --accept-source-agreements
}

Write-Host "== Linking Alacritty config ==" -ForegroundColor Cyan

# Resolve the default WSL distro name (ignoring Docker Desktop's own
# docker-desktop/docker-desktop-data distros) so we can build the
# \\wsl.localhost\... path to this repo's tracked copy of alacritty.toml.
# `wsl -l -v` marks the default distro with a leading '*'; output comes
# back as UTF-16 with embedded nulls through PowerShell's pipeline, so
# strip those before parsing lines.
$wslListRaw = (wsl.exe -l -v 2>$null) -replace "`0", ""
$distroLines = $wslListRaw | Select-Object -Skip 1 | Where-Object { $_.Trim() -ne "" }

$distro = $null
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

    if ($isDefault) { $distro = $name }
    elseif (-not $fallbackDistro) { $fallbackDistro = $name }
}
if (-not $distro) { $distro = $fallbackDistro }

if (-not $distro) {
    Write-Error "Could not detect a WSL distro. Pass the repo path manually and edit `$repoConfig` below."
    exit 1
}

$wslWhoami = (wsl.exe -d $distro -- whoami).Trim()
$repoConfig = "\\wsl.localhost\$distro\home\$wslWhoami\.config\nvim\windows\alacritty.toml"

if (-not (Test-Path $repoConfig)) {
    Write-Error "Could not find $repoConfig - is the nvim config repo cloned to ~/.config/nvim in WSL ($distro)?"
    exit 1
}

$alacrittyDir = Join-Path $env:APPDATA "alacritty"
New-Item -ItemType Directory -Force -Path $alacrittyDir | Out-Null
$target = Join-Path $alacrittyDir "alacritty.toml"

if (Test-Path $target) {
    Remove-Item $target -Force
}

try {
    New-Item -ItemType SymbolicLink -Path $target -Value $repoConfig | Out-Null
    Write-Host "Linked $target -> $repoConfig"
    Write-Host "Future edits to windows/alacritty.toml in the repo (from WSL) will apply automatically."
} catch {
    Write-Warning "Could not create a symlink (needs admin rights or Developer Mode enabled). Copying the file instead."
    Copy-Item $repoConfig $target -Force
    Write-Host "Copied $repoConfig -> $target (re-run this script after editing the repo config to re-sync)."
}

Write-Host "`nDone. Restart Alacritty to pick up the font/config." -ForegroundColor Green
