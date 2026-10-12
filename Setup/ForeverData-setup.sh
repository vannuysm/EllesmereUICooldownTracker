#!/usr/bin/env bash
# Forever Data Protect setup for Linux and macOS (Windows: ForeverData-setup.ps1).
#
# The Forever beta writes addon settings to disk but does not load them again when the game starts.
# This makes a small folder, Interface/AddOns/!ForeverData, that loads each addon's saved settings file as
# an ordinary addon file, which the game does read; Forever Data Protect then hands the data to each addon
# at the moment the game normally would. The folder holds no code: a link to your account's SavedVariables
# folder, a .toc listing the files, and a list of each addon's saved variable names. It is separate from the
# addons, so updating them never removes it. Run this again after installing a new addon.
# To undo, delete the Interface/AddOns/!ForeverData folder.
#
# Close the game first. Usage:
#   ForeverData-setup.sh ["/path/to/World of Warcraft/_classic_beta_"] [account folder name]
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -L)"
game="${1:-$(cd "$script_dir/../../../.." && pwd -L)}"
addons="$game/Interface/AddOns"
accounts="$game/WTF/Account"
if [ ! -d "$addons" ] || [ ! -d "$accounts" ]; then
    echo "Could not find Interface/AddOns and WTF/Account in: $game"
    echo "Pass the game folder: $0 \"/path/to/World of Warcraft/_classic_beta_\""
    exit 1
fi

account="${2:-}"
if [ -z "$account" ]; then
    # the account whose addon settings were written most recently
    newest="$(ls -t "$accounts"/*/SavedVariables/*.lua 2>/dev/null | grep -v '/Blizzard_' | head -n 1 || true)"
    if [ -z "$newest" ]; then
        echo "No addon settings found yet. Log in once with your addons enabled, exit the game, and run this again."
        exit 1
    fi
    account="$(basename "$(dirname "$(dirname "$newest")")")"
fi
sv="$accounts/$account/SavedVariables"
if [ ! -d "$sv" ]; then echo "No SavedVariables folder for account $account"; exit 1; fi

target="$addons/!ForeverData"
mkdir -p "$target"
link="$target/SV"
if [ -e "$link" ] && [ ! -L "$link" ]; then echo "$link exists and is not a link. Remove it and run this again."; exit 1; fi
rm -f "$link"
ln -s "../../../WTF/Account/$account/SavedVariables" "$link"   # relative: keeps working if the game folder moves

luastr() { printf '"%s"' "$(printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g')"; }

names=()
entries=""
for dir in "$addons"/*/; do
    name="$(basename "$dir")"
    case "$name" in Blizzard_*|"!ForeverData") continue ;; esac
    [ -f "$sv/$name.lua" ] || continue
    vars=""
    first=false
    for toc in "$dir"*.toc; do
        [ -f "$toc" ] || continue
        line="$(tr -d '\r' < "$toc" | grep -i -m1 '^## *SavedVariables *:' | sed 's/^## *[^:]*: *//' || true)"
        [ -n "$line" ] && vars="$vars,$line"
        if tr -d '\r' < "$toc" | grep -qiE '^## *LoadSavedVariablesFirst *: *1'; then first=true; fi
    done
    varlist="$(printf '%s' "$vars" | tr ',' '\n' | sed 's/^ *//; s/ *$//' | grep -E '^[A-Za-z_][A-Za-z0-9_]*$' | sort -u || true)"
    [ -n "$varlist" ] || continue
    names+=("$name")
    list=""
    while IFS= read -r v; do list="$list\"$v\", "; done <<< "$varlist"
    entries="$entries    [$(luastr "$name")] = { vars = { $list}, first = $first },"$'\n'
done

{
    echo "## Interface: 120100, 120105, 16001"
    echo "## Title: !ForeverData"
    echo "## Notes: Loads saved addon settings at startup for Forever Data Protect. Made by its setup; no code of its own."
    echo "## Author: Ugge Zen"
    echo
    for name in "${names[@]}"; do echo "SV\\$name.lua"; done
    echo "ForeverData.lua"
} > "$target/!ForeverData.toc"
{
    echo "-- Made by the Forever Data Protect setup: which saved files were loaded, and each addon's saved variable names."
    echo "ForeverData = { active = true, account = $(luastr "$account"), made = $(date +%s), addons = {"
    printf '%s' "$entries"
    printf '}, files = { '
    for name in "${names[@]}"; do printf '%s, ' "$(luastr "$name")"; done
    echo "} }"
} > "$target/ForeverData.lua"

echo "Done. !ForeverData now loads saved settings for account $account, for ${#names[@]} addons:"
for name in "${names[@]}"; do echo "  $name"; done
echo "Start the game. Forever Data Protect's settings page (/fdp) shows each addon's state."
