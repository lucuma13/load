#!/bin/bash
# Mac workstation setup script
# Usage: curl -fsSL https://raw.githubusercontent.com/lucuma13/load/main/src/load-mac.sh | bash
#   Run with no flag to be prompted for the setup type, or pass one explicitly.
# Flags: --fast  --full  --dry-run

SELF_URL="https://raw.githubusercontent.com/lucuma13/load/main/src/load-mac.sh"

# =============================================================================
# Function library
#
# Everything above the LOAD_LIB guard is side-effect-free definitions, so the
# test suite can `source` this file (with LOAD_LIB=1) to exercise individual
# functions without triggering the installer.
# =============================================================================

brew_prefix() {
  if [ -n "${HOMEBREW_PREFIX:-}" ]; then
    echo "$HOMEBREW_PREFIX"
  elif [ -f "/opt/homebrew/bin/brew" ]; then
    echo "/opt/homebrew"
  else
    echo "/usr/local"
  fi
}

would_run()   { echo "  🚀  $1"; }
would_skip()  { echo "  ⏭️  $1"; }
already_done(){ echo "  ✅  $1"; }

formula_installed() { $BREW_OK && brew list --formula "$1" &>/dev/null 2>&1; }
cask_installed()    { $BREW_OK && brew list --cask    "$1" &>/dev/null 2>&1; }
uv_installed()      { command -v uv &>/dev/null && uv tool list 2>/dev/null | grep -q "^$1"; }

# resolve_mode <args…> — echo the setup flags present, normalised and deduped
# (a space-separated subset of "fast full dryrun"); empty when none were given.
resolve_mode() {
  local arg out=""
  for arg in "$@"; do
    case "$arg" in
      --fast)    case " $out " in *" fast "*)   ;; *) out="$out fast"   ;; esac ;;
      --full)    case " $out " in *" full "*)   ;; *) out="$out full"   ;; esac ;;
      --dry-run) case " $out " in *" dryrun "*) ;; *) out="$out dryrun" ;; esac ;;
    esac
  done
  echo "${out# }"
}

# choose_mode — prompt on the terminal for Fast/Full and echo "fast"/"full".
# Reads /dev/tty (not stdin, which is the piped script under curl | bash).
# Returns 1 when there is no terminal to prompt from.
choose_mode() {
  # Open the terminal on fd 3 (stdin is the piped script under curl | bash).
  # Probe inside a redirected group so a missing tty fails quietly.
  { exec 3<>/dev/tty; } 2>/dev/null || return 1
  local reply
  while true; do
    printf '%s' "  Setup type — [1] Fast (config only)  [2] Full (everything): " >&3
    read -r reply <&3 || { exec 3>&-; return 1; }
    case "$reply" in
      1|fast|Fast) exec 3>&-; echo fast; return 0 ;;
      2|full|Full) exec 3>&-; echo full; return 0 ;;
      *) printf '%s\n' "  Please enter 1 or 2." >&3 ;;
    esac
  done
}

usage() {
  echo "Usage: load-mac.sh [--fast | --full | --dry-run]" >&2
  echo "  Run with no flag in a terminal to be prompted for the setup type." >&2
}

# premiere_workspace_name <workspace.xml> — echo the workspace display name,
# stored inside the file under the UserName key.
premiere_workspace_name() {
  awk '/<key>UserName<\/key>/{getline; gsub(/<\/?ustring>/,""); print; exit}' "$1"
}

# set_pref_node <prefs> <node> <value> — replace an XML leaf node's text in place
# (perl, no BOM). The value is passed via env so it survives spaces and regex/JSON
# specials. Returns 1 WITHOUT touching the file when the node is absent, so callers
# can flag nodes a future Premiere version may have renamed (no edit = no
# corruption).
set_pref_node() {
  local prefs="$1" node="$2"
  grep -q "<$node>" "$prefs" || return 1
  SPN_VAL="$3" perl -i -pe "s{(<\Q$node\E>).*?(</\Q$node\E>)}{\${1}\$ENV{SPN_VAL}\${2}}" "$prefs"
}

# premiere_apply_prefs <prefs> <kys_file> <ws_name> — point Premiere's prefs at
# the keyboard set + workspace, apply the Classic label preset, enable auto-save
# every 5 minutes, and turn on the timeline's Link Selection + Display Settings.
# Every node is matched exactly; any not found (e.g. renamed in a future Premiere
# version) is left untouched and collected into a single "needs revising" warning,
# so the script never crashes or corrupts the prefs on a version bump.
premiere_apply_prefs() {
  local prefs="$1" kys_file="$2" ws_name="$3"
  # Built-in "Classic" label preset: 16 names + 16 colours + a RecentPreset
  # marker (Premiere has no single preset switch, so we write the exact values).
  local label_names=(Violet Iris Caribbean Lavender Cerulean Forest Rose Mango Purple Blue Teal Magenta Tan Green Brown Yellow)
  local label_colors=(14717094 13408882 10016297 14910691 14597935 5814353 10776567 3909357 9896087 16727100 8421376 15151847 9814478 2191389 1262987 6611682)
  local missing=() i tl_node

  # Keyboard set
  set_pref_node "$prefs" "FE.Prefs.Shortcuts.Filename" "$kys_file" || missing+=("FE.Prefs.Shortcuts.Filename")

  # Active workspace (skip if the display name couldn't be read from the file)
  if [ -n "$ws_name" ]; then
    set_pref_node "$prefs" "FE.Application.LastWorkspaceName" "$ws_name" || missing+=("FE.Application.LastWorkspaceName")
  fi

  # Classic label preset (names + colours + preset marker)
  for i in "${!label_names[@]}"; do
    set_pref_node "$prefs" "BE.Prefs.LabelNames.$i"  "${label_names[$i]}"  || missing+=("BE.Prefs.LabelNames.$i")
    set_pref_node "$prefs" "BE.Prefs.LabelColors.$i" "${label_colors[$i]}" || missing+=("BE.Prefs.LabelColors.$i")
  done
  set_pref_node "$prefs" "PPro.LabelColorPresets.RecentPreset" '{"builtIn":true,"name":"Classic"}' || missing+=("PPro.LabelColorPresets.RecentPreset")

  # Auto-save: on, every 5 minutes
  set_pref_node "$prefs" "BE.Prefs.AutoSave.DoSave"   "true" || missing+=("BE.Prefs.AutoSave.DoSave")
  set_pref_node "$prefs" "BE.Prefs.AutoSave.Interval" "5"    || missing+=("BE.Prefs.AutoSave.Interval")

  # Timeline toggles: Link Selection + the Display Settings (wrench menu) —
  # video thumbnails/names, audio waveforms/names, FX/proxy badges, through
  # edits, duplicate-frame markers.
  for tl_node in \
    TL.PREFLinkedSelectionState \
    be.Prefs.Timeline.Show.Video.Thumbnails \
    be.Prefs.Timeline.Show.Video.Names \
    be.Prefs.Timeline.Show.Audio.Waveforms \
    be.Prefs.Timeline.Show.Audio.Names \
    be.Prefs.Timeline.Show.Proxy.Badges \
    TL.PREFShowFXBadges \
    TL.PREFShowThroughEditsState \
    MZ.SQShowDuplicateMarkers; do
    set_pref_node "$prefs" "$tl_node" "true" || missing+=("$tl_node")
  done

  # A missing node almost always means Premiere renamed it in a new version. The
  # file is untouched for those nodes (never corrupted); warn loudly so the
  # script gets revised.
  if [ "${#missing[@]}" -gt 0 ]; then
    echo "  ⚠️  Premiere prefs: ${#missing[@]} preference node(s) not found — Premiere may"
    echo "      have renamed them in this version. These settings were NOT applied; the"
    echo "      script needs revising for the following nodes:"
    printf '        - %s\n' "${missing[@]}"
  fi
}

# premiere_set_media_cache <plist-domain> <cache-dir> — point Premiere's shared
# "Media Cache Files" location (the Adobe Common prefs) at <cache-dir>, stored
# with a trailing slash. -dict-add updates FolderPath in place, preserving the
# sibling DatabasePath (the Media Cache Database location).
premiere_set_media_cache() {
  local domain="$1" cache_dir="$2"
  defaults write "$domain" "Media Cache" -dict-add FolderPath "${cache_dir%/}/"
}

# Sourced as a library (tests set LOAD_LIB=1): stop here, run nothing below.
[ -n "${LOAD_LIB:-}" ] && return 0 2>/dev/null

set -euo pipefail

# -----------------------------------------------------------------------------
# Resolve the setup mode — prompt when run with no flag
# -----------------------------------------------------------------------------

MODES="$(resolve_mode "$@")"
if [ -z "$MODES" ]; then
  CHOSEN="$(choose_mode)" || { usage; exit 1; }
  set -- "--$CHOSEN"
  MODES="$CHOSEN"
fi

FAST=false; FULL=false; DRY_RUN=false
case " $MODES " in *" fast "*)   FAST=true    ;; esac
case " $MODES " in *" full "*)   FULL=true    ;; esac
case " $MODES " in *" dryrun "*) DRY_RUN=true ;; esac

# Re-exec from a real file when piped (curl | bash) for non-fast runs. Reading
# the script from stdin lets child processes (e.g. brew's ca-certificates
# keychain step) drain the remaining script out of the pipe, silently skipping
# later sections such as Pro Video Formats. Running from a file makes this
# impossible. --fast runs none of the stdin-draining steps, so it stays on stdin.
if ! $FAST && { [ ! -r "${BASH_SOURCE[0]:-}" ] || [ "${BASH_SOURCE[0]:-}" = "bash" ]; }; then
  TMP="$(mktemp -t load-mac).sh"
  curl -fsSL "$SELF_URL" -o "$TMP"
  exec bash "$TMP" "$@"
fi

# -----------------------------------------------------------------------------
# Preflight
# -----------------------------------------------------------------------------

PREMIERE_OK=false;      ls "$HOME/Documents/Adobe/Premiere Pro"/*/Profile-*/Mac &>/dev/null 2>&1 && PREMIERE_OK=true
# Premiere rewrites its prefs on exit — activating a set while it's running would get clobbered.
# Match the process name (version-agnostic) rather than full args, which would hit our own perl call.
PREMIERE_RUNNING=false; $PREMIERE_OK && pgrep "Adobe Premiere Pro" &>/dev/null 2>&1             && PREMIERE_RUNNING=true
BREW_OK=false;          command -v brew &>/dev/null                                              && BREW_OK=true
PVF_OK=false
{ [ -d "/Library/Apple/System/Library/CoreServices/ProVideoFormats.bundle" ] || \
  pkgutil --pkg-info com.apple.pkg.ProVideoFormats &>/dev/null 2>&1; } && PVF_OK=true
SCRATCH="$(ls -d /Volumes/SCRATCH* 2>/dev/null | head -1 || true)"

echo ""

# Premiere Pro
if $PREMIERE_OK; then
  would_run  "Premiere Pro shortcuts & workspace"
  if $PREMIERE_RUNNING; then would_skip "Premiere Pro preferences — Premiere Pro is open"
  else                       would_run  "Premiere Pro preferences"; fi
  if [ -n "$SCRATCH" ]; then would_run  "Premiere media cache → $SCRATCH/Cache"
  else                       would_skip "Premiere media cache — no SCRATCH drive"; fi
  if $FAST; then would_skip "Premiere Pro plugins (--fast)"
  else           would_run  "Premiere Pro plugins — Animation Composer, Flicker Free"; fi
else
  would_skip "Premiere Pro shortcuts & workspace — not installed"
  would_skip "Premiere Pro preferences — not installed"
  would_skip "Premiere Pro plugins — not installed"
fi

# System / Finder / TextEdit — always run
would_run "System preferences"
would_run "Finder preferences"
would_run "TextEdit preferences"

# Homebrew
if $BREW_OK; then
  already_done "Homebrew"
elif $FAST; then
  would_skip "Homebrew (--fast)"
else
  would_run "Homebrew"
fi

# Managed packages
CORE_FORMULAE="media-info exiftool ffmpeg uv"
CORE_CASKS="vlc caffeine mediainfo"
CORE_UV="triplecheck mhl-suite"
FULL_FORMULAE="git"  # add these if needed: atomicparsley, bento4, wget
FULL_CASKS="google-chrome adobe-acrobat-reader audacity mediahuman-audio-converter appcleaner"

if $FAST; then
  ALL_PKGS="$CORE_FORMULAE $CORE_CASKS $CORE_UV"
  $FULL && ALL_PKGS="$ALL_PKGS $FULL_FORMULAE $FULL_CASKS"
  would_skip "managed packages (--fast) — $(echo $ALL_PKGS | tr ' ' ', ')"
else
  FORMULAE_LIST="$CORE_FORMULAE"; $FULL && FORMULAE_LIST="$FORMULAE_LIST $FULL_FORMULAE"
  CASKS_LIST="$CORE_CASKS";       $FULL && CASKS_LIST="$CASKS_LIST $FULL_CASKS"

  PKGS_DONE=""
  PKGS_TODO=""

  for pkg in $FORMULAE_LIST; do
    if formula_installed "$pkg"; then PKGS_DONE="$PKGS_DONE $pkg"; else PKGS_TODO="$PKGS_TODO $pkg"; fi
  done
  for pkg in $CASKS_LIST; do
    if cask_installed "$pkg"; then PKGS_DONE="$PKGS_DONE $pkg"; else PKGS_TODO="$PKGS_TODO $pkg"; fi
  done
  for pkg in $CORE_UV; do
    if uv_installed "$pkg"; then PKGS_DONE="$PKGS_DONE $pkg"; else PKGS_TODO="$PKGS_TODO $pkg"; fi
  done

  PKGS_DONE="${PKGS_DONE# }"; PKGS_TODO="${PKGS_TODO# }"

  [ -n "$PKGS_DONE" ] && would_run "update managed packages: $(echo $PKGS_DONE | tr ' ' ',')"
  [ -n "$PKGS_TODO" ] && would_run "install managed packages: $(echo $PKGS_TODO | tr ' ' ',')"
fi

# Pro Video Formats
if $PVF_OK; then
  already_done "Pro Video Formats"
elif $FAST; then
  would_skip "Pro Video Formats (--fast)"
else
  would_run "Pro Video Formats"
fi

# LUTs
if $FAST; then
  would_skip "LUTs (--fast)"
else
  would_run "LUTs"
fi

echo ""
$DRY_RUN && exit 0

# The lightweight config below runs before any slow download/install so that an
# interrupted run still leaves the quick preference changes applied. Finder is
# the exception — it needs python3 (Command Line Tools), so it follows CLT.

# -----------------------------------------------------------------------------
# System preferences
# -----------------------------------------------------------------------------

defaults write NSGlobalDomain KeyRepeat -int 2
defaults write NSGlobalDomain InitialKeyRepeat -int 15
defaults write NSGlobalDomain com.apple.trackpad.scaling -float 2
defaults write com.apple.controlcenter BatteryShowPercentage -bool true

defaults write com.apple.dock autohide -bool true
defaults write com.apple.dock tilesize -int 50
defaults write com.apple.dock magnification -bool false
defaults write com.apple.dock orientation -string "bottom"
defaults write com.apple.dock mru-spaces -bool false
defaults write com.apple.dock show-recents -bool false
killall Dock

# -----------------------------------------------------------------------------
# TextEdit preferences
# -----------------------------------------------------------------------------

defaults write com.apple.TextEdit RichText -int 0
defaults write com.apple.TextEdit CorrectSpellingAutomatically -bool false
defaults write com.apple.TextEdit SmartDashes -bool false
defaults write NSGlobalDomain NSAutomaticDashSubstitutionEnabled -bool false
defaults write com.apple.TextEdit TextReplacement -bool false
defaults write NSGlobalDomain NSAutomaticTextCompletionEnabled -bool false
defaults write com.apple.TextEdit ShowRuler -bool false
killall cfprefsd
killall AppleSpell 2>/dev/null || true
killall TextEdit 2>/dev/null || true

# -----------------------------------------------------------------------------
# Premiere Pro shortcuts, workspace & labels
# -----------------------------------------------------------------------------

if $PREMIERE_OK; then
  KYS_FILE="Luis_Mengo_25.1.kys"
  WS_FILE="UserWorkspace_LGG.xml"

  for profile in "$HOME/Documents/Adobe/Premiere Pro"/*/Profile-*/; do
    [ -d "$profile" ] || continue
    prefs="${profile}Adobe Premiere Pro Prefs"

    # Drop the shortcuts into the Profile's Mac folder (where Premiere reads custom sets)
    mkdir -p "${profile}Mac"
    (cd "${profile}Mac" && curl -fsSL -O "https://raw.githubusercontent.com/lucuma13/load/main/src/data/$KYS_FILE")

    # Drop the workspace into Layouts. Premiere auto-registers it on launch.
    mkdir -p "${profile}Layouts"
    (cd "${profile}Layouts" && curl -fsSL -O "https://raw.githubusercontent.com/lucuma13/load/main/src/data/$WS_FILE")
    ws_name="$(premiere_workspace_name "${profile}Layouts/$WS_FILE")"

    if $PREMIERE_RUNNING; then
      echo "  ⚠️  Premiere Pro is running — files dropped but not activated"
    elif [ -f "$prefs" ]; then
      premiere_apply_prefs "$prefs" "$KYS_FILE" "$ws_name"
    fi
  done

  # Media cache — relocate the "Media Cache Files" location to a SCRATCH drive
  # when one is attached. The setting lives in the shared Adobe "Common" prefs
  # (com.Adobe.Common <ver>), not the Premiere prefs; skip if no SCRATCH drive.
  if [ -n "$SCRATCH" ]; then
    mkdir -p "$SCRATCH/Cache"
    if $PREMIERE_RUNNING; then
      echo "  ⚠️  Premiere Pro is running — media cache not changed"
    else
      for plist in "$HOME/Library/Preferences/com.Adobe.Common "*.plist; do
        [ -f "$plist" ] || continue
        premiere_set_media_cache "$(basename "$plist" .plist)" "$SCRATCH/Cache"
      done
    fi
  fi
fi

# -----------------------------------------------------------------------------
# Command Line Tools (provides git/python3; required by Homebrew)
# -----------------------------------------------------------------------------
# Skipped with --fast, which assumes an already-provisioned machine. Without
# this, a fresh Mac triggers the Xcode CLT dialog mid-run and aborts, forcing a
# manual re-run. We pop the installer and wait for it to finish.

if ! $FAST && ! xcode-select -p &>/dev/null; then
  echo "  🚀  Command Line Tools — installing (accept the dialog; this can take a few minutes)…"
  xcode-select --install &>/dev/null || true
  until xcode-select -p &>/dev/null; do sleep 10; done
fi

# -----------------------------------------------------------------------------
# Finder preferences (needs python3 from Command Line Tools)
# -----------------------------------------------------------------------------

defaults write com.apple.finder ShowPathbar -bool true
defaults write com.apple.finder ShowStatusBar -bool true
defaults write com.apple.finder FXDefaultSearchScope -string "SCcf"
defaults write com.apple.finder NewWindowTarget -string "PfLo"
defaults write com.apple.finder NewWindowTargetPath -string "file://${HOME}/Downloads/"

osascript -e 'tell application "Finder" to quit'
sleep 2
plutil -convert xml1 ~/Library/Preferences/com.apple.finder.plist
python3 -c "
import plistlib, os
path = os.path.expanduser('~/Library/Preferences/com.apple.finder.plist')
p = plistlib.load(open(path,'rb'))
def f(o):
    if isinstance(o,dict):
        for k,v in o.items():
            if k=='calculateAllSizes':
                o[k]=True
            else:
                f(v)
    elif isinstance(o,list):
        for i in o:
            f(i)
f(p)
plistlib.dump(p,open(path,'wb'))
"
sleep 1
open -a Finder

# -----------------------------------------------------------------------------
# Cache sudo credentials (only the steps below need root) and keep them alive
# -----------------------------------------------------------------------------

if ! $FAST; then
  sudo -v
  while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done 2>/dev/null &
fi

# -----------------------------------------------------------------------------
# Homebrew & Managed Packages
# -----------------------------------------------------------------------------

if ! $BREW_OK && ! $FAST; then
  echo | /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

  PREFIX="$(brew_prefix)"
  SHELLENV_LINE="eval \"\$(${PREFIX}/bin/brew shellenv)\""
  echo >> "$HOME/.zprofile"
  echo "$SHELLENV_LINE" >> "$HOME/.zprofile"
  eval "$("${PREFIX}/bin/brew" shellenv)"
fi

# Ensure brew is in PATH even if already installed
PREFIX="$(brew_prefix)"
eval "$("${PREFIX}/bin/brew" shellenv)" 2>/dev/null || true


if ! $FAST; then
  brew install --adopt        $CORE_FORMULAE
  brew install --cask --adopt $CORE_CASKS
  for pkg in $CORE_UV; do uv tool install "$pkg" --upgrade; done
fi

# Ensure uv-installed CLI tools (~/.local/bin) are on PATH. `uv tool
# update-shell` detects the active shell and updates the right profile (safer
# than hardcoding ~/.zprofile). Idempotent. Export covers the current session.
if command -v uv &>/dev/null; then
  uv tool update-shell || true
fi
export PATH="$HOME/.local/bin:$PATH"

if $FULL && ! $FAST; then
  brew install --adopt        $FULL_FORMULAE
  brew install --cask --adopt $FULL_CASKS
fi

# -----------------------------------------------------------------------------
# Premiere plugins
# -----------------------------------------------------------------------------
# Mister Horse's Product Manager is the app that installs & updates Animation
# Composer (and the rest of the Mister Horse plugins) into Premiere/After
# Effects. We download the Product Manager installer and run it; Animation
# Composer itself is then installed from within the app on first launch.

if $PREMIERE_OK && ! $FAST; then
  PM_DMG="$HOME/Downloads/MisterHorseProductManager.dmg"
  curl -fsSL -o "$PM_DMG" "https://misterhorse.com/downloads/product-manager/osx"
  VOL="$(hdiutil attach "$PM_DMG" -nobrowse | grep -o '/Volumes/.*' | head -1 || true)"
  PM_APP="$(find "$VOL" -maxdepth 1 -name '*.app' 2>/dev/null | head -1 || true)"
  [ -n "$PM_APP" ] && sudo cp -R "$PM_APP" /Applications/
  [ -n "$VOL" ] && hdiutil detach "$VOL" -quiet

  # Flicker Free — Digital Anarchy's deflicker plugin. The DMG holds a .pkg we
  # install straight to the system; the plugin then shows up in Premiere/AE.
  FF_DMG="$HOME/Downloads/flickerfree_229_AE.dmg"
  curl -fsSL -o "$FF_DMG" "https://www.digitalanarchy.com/downloads/flickerfree_229_AE.dmg"
  FF_VOL="$(hdiutil attach "$FF_DMG" -nobrowse | grep -o '/Volumes/.*' | head -1 || true)"
  FF_PKG="$(find "$FF_VOL" -maxdepth 1 -name '*.pkg' 2>/dev/null | head -1 || true)"
  [ -n "$FF_PKG" ] && sudo installer -pkg "$FF_PKG" -target /
  [ -n "$FF_VOL" ] && hdiutil detach "$FF_VOL" -quiet
fi

# -----------------------------------------------------------------------------
# Pro Video Formats
# -----------------------------------------------------------------------------

if ! $PVF_OK && ! $FAST; then
  DMG_URL="https://updates.cdn-apple.com/2026/macos/072-84099-20260127-5022F0FE-82CF-44E9-B96D-430E73501EBA/ProVideoFormats.dmg"
  DMG_PATH="$HOME/Downloads/ProVideoFormats.dmg"

  if [ ! -f "$DMG_PATH" ]; then
    curl -o "$DMG_PATH" "$DMG_URL"
  fi

  hdiutil attach "$DMG_PATH" -nobrowse
  sudo installer -pkg "/Volumes/Pro Video Formats/ProVideoFormats.pkg" -target /
  hdiutil detach "/Volumes/Pro Video Formats" -quiet
  rm "$DMG_PATH"
fi

# -----------------------------------------------------------------------------
# LUTs
# -----------------------------------------------------------------------------
# Download every LUT in src/data/LUTs into ~/Downloads/LUTs (skipped --fast).
# The file list comes from the GitHub contents API, so new LUTs are picked up
# automatically without editing this script.

if ! $FAST; then
  LUT_DIR="$HOME/Downloads/LUTs"
  LUT_API="https://api.github.com/repos/lucuma13/load/contents/src/data/LUTs?ref=main"
  mkdir -p "$LUT_DIR"
  LUT_URLS="$(curl -fsSL "$LUT_API" | grep -o 'https://raw.githubusercontent.com/[^"]*' || true)"
  for url in $LUT_URLS; do
    (cd "$LUT_DIR" && curl -fsSL -O "$url")
  done
fi

# -----------------------------------------------------------------------------
# Homebrew maintenance — refresh catalog, upgrade everything, prune old versions
# -----------------------------------------------------------------------------

if ! $FAST && command -v brew &>/dev/null; then
  brew update
  brew upgrade
  brew cleanup
fi

# -----------------------------------------------------------------------------
# Summary
# -----------------------------------------------------------------------------


echo ""
echo "  You're ready to roll! 🛼"
echo ""
echo "  ⚠️  Please restart the computer for system prefs to take effect"
echo ""
