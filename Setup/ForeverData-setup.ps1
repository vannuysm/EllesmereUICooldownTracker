# Forever Data Protect setup for Windows. Easiest: right-click this file and choose Run with PowerShell.
#
# The Forever beta writes addon settings to disk but does not load them again when the game starts.
# This makes a small folder, Interface\AddOns\!ForeverData, that loads each addon's saved settings file as
# an ordinary addon file, which the game does read; Forever Data Protect then hands the data to each addon
# at the moment the game normally would. The folder holds no code: a junction (a folder link, no admin rights
# needed) to your account's SavedVariables folder, a .toc listing the files, and a list of each addon's saved
# variable names. It is separate from the addons, so updating them never removes it. Run this again after
# installing a new addon. To undo, delete the Interface\AddOns\!ForeverData folder.
#
# Close the game first. Usage: ForeverData-setup.ps1 [-Game "C:\...\World of Warcraft\_classic_beta_"] [-Account name]
param([string]$Game, [string]$Account, [switch]$NoPause)
$ErrorActionPreference = "Stop"

# Run with PowerShell closes the window when the script ends; keep it open so the result can be read.
function Finish([int]$code) {
    if (-not $NoPause) { Read-Host "Press Enter to close" | Out-Null }
    exit $code
}
trap { Write-Host "Setup failed: $_"; Finish 1 }

if (-not $Game) { $Game = (Resolve-Path (Join-Path $PSScriptRoot "..\..\..\..")).Path }
$addons = Join-Path $Game "Interface\AddOns"
$accounts = Join-Path $Game "WTF\Account"
if (-not (Test-Path -LiteralPath $addons) -or -not (Test-Path -LiteralPath $accounts)) {
    Write-Host "Could not find Interface\AddOns and WTF\Account in: $Game"
    Write-Host "Pass the game folder: ForeverData-setup.ps1 -Game `"C:\...\World of Warcraft\_classic_beta_`""
    Finish 1
}

if (-not $Account) {
    # the account whose addon settings were written most recently
    $newest = Get-ChildItem -LiteralPath $accounts -Directory | ForEach-Object {
        $dir = Join-Path $_.FullName "SavedVariables"
        if (Test-Path -LiteralPath $dir) { Get-ChildItem -LiteralPath $dir -Filter "*.lua" | Where-Object { $_.Name -notlike "Blizzard_*" } }
    } | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if (-not $newest) {
        Write-Host "No addon settings found yet. Log in once with your addons enabled, exit the game, and run this again."
        Finish 1
    }
    $Account = $newest.Directory.Parent.Name
}
$sv = Join-Path $accounts (Join-Path $Account "SavedVariables")
if (-not (Test-Path -LiteralPath $sv)) { Write-Host "No SavedVariables folder for account $Account"; Finish 1 }

$target = Join-Path $addons "!ForeverData"
New-Item -ItemType Directory -Force -Path $target | Out-Null
$link = Join-Path $target "SV"
if (Test-Path -LiteralPath $link) {
    $item = Get-Item -LiteralPath $link -Force
    if ($item.LinkType) { $item.Delete() } else { Write-Host "$link exists and is not a link. Remove it and run this again."; Finish 1 }
}
# Windows: a junction (no admin rights needed). PowerShell on macOS or Linux: a symbolic link.
if ($env:OS -eq "Windows_NT") { New-Item -ItemType Junction -Path $link -Target $sv | Out-Null }
else { New-Item -ItemType SymbolicLink -Path $link -Target $sv | Out-Null }

function LuaStr([string]$s) { '"' + $s.Replace('\', '\\').Replace('"', '\"') + '"' }

$names = @()
$entries = @()
foreach ($dir in Get-ChildItem -LiteralPath $addons -Directory) {
    $name = $dir.Name
    if ($name -like "Blizzard_*" -or $name -eq "!ForeverData") { continue }
    if (-not (Test-Path -LiteralPath (Join-Path $sv "$name.lua"))) { continue }
    $vars = @()
    $first = $false
    foreach ($toc in Get-ChildItem -LiteralPath $dir.FullName -Filter "*.toc" -File) {
        foreach ($line in Get-Content -LiteralPath $toc.FullName) {
            if ($line -match '^##\s*SavedVariables\s*:\s*(.*)$') { $vars += $Matches[1].Split(",") | ForEach-Object { $_.Trim() } }
            if ($line -match '^##\s*LoadSavedVariablesFirst\s*:\s*1') { $first = $true }
        }
    }
    $vars = $vars | Where-Object { $_ -match '^[A-Za-z_][A-Za-z0-9_]*$' } | Sort-Object -Unique
    if (-not $vars) { continue }
    $names += $name
    $list = ($vars | ForEach-Object { "`"$_`", " }) -join ""
    $entries += "    [$(LuaStr $name)] = { vars = { $list}, first = $($first.ToString().ToLower()) },"
}

$toc = @("## Interface: 120100, 120105, 16001", "## Title: !ForeverData",
    "## Notes: Loads saved addon settings at startup for Forever Data Protect. Made by its setup; no code of its own.",
    "## Author: Ugge Zen", "")
$toc += $names | ForEach-Object { "SV\$_.lua" }
$toc += "ForeverData.lua"
Set-Content -LiteralPath (Join-Path $target "!ForeverData.toc") -Value $toc -Encoding ASCII
$made = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
$files = ($names | ForEach-Object { (LuaStr $_) + ", " }) -join ""
$lua = @("-- Made by the Forever Data Protect setup: which saved files were loaded, and each addon's saved variable names.",
    "ForeverData = { active = true, account = $(LuaStr $Account), made = $made, addons = {")
$lua += $entries
$lua += "}, files = { $files} }"
Set-Content -LiteralPath (Join-Path $target "ForeverData.lua") -Value $lua -Encoding ASCII

Write-Host "Done. !ForeverData now loads saved settings for account $Account, for $($names.Count) addons:"
$names | ForEach-Object { Write-Host "  $_" }
Write-Host "Start the game. Forever Data Protect's settings page (/fdp) shows each addon's state."
Finish 0
