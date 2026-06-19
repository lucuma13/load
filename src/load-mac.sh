#!/bin/bash
# Mac workstation setup script
# Usage: curl -fsSL https://raw.githubusercontent.com/lucuma13/load/main/src/load-mac.sh | bash -s -- --full

set -euo pipefail

# Re-exec from a real file when piped (curl | bash). Reading the script from
# stdin lets child processes (e.g. brew's ca-certificates keychain step) drain
# the remaining script out of the pipe, silently skipping later sections such
# as Pro Video Formats. Running from a file makes this impossible. Skipped with
# --fast, which runs none of the stdin-draining steps (brew install, PVF).
SELF_URL="https://raw.githubusercontent.com/lucuma13/load/main/src/load-mac.sh"
case " $* " in *" --fast "*) FAST_ARG=true ;; *) FAST_ARG=false ;; esac
if ! $FAST_ARG && { [ ! -r "${BASH_SOURCE[0]:-}" ] || [ "${BASH_SOURCE[0]:-}" = "bash" ]; }; then
  TMP="$(mktemp -t load-mac).sh"
  curl -fsSL "$SELF_URL" -o "$TMP"
  exec bash "$TMP" "$@"
fi

brew_prefix() {
  if [ -n "${HOMEBREW_PREFIX:-}" ]; then
    echo "$HOMEBREW_PREFIX"
  elif [ -f "/opt/homebrew/bin/brew" ]; then
    echo "/opt/homebrew"
  else
    echo "/usr/local"
  fi
}

# -----------------------------------------------------------------------------
# Preflight
# -----------------------------------------------------------------------------

FULL=false
FAST=false
DRY_RUN=false
for arg in "$@"; do
  [ "$arg" = "--full" ]     && FULL=true
  [ "$arg" = "--fast" ]     && FAST=true
  [ "$arg" = "--dry-run" ]  && DRY_RUN=true
done

PREMIERE_OK=false;   ls "$HOME/Documents/Adobe/Premiere Pro"/*/Profile-*/Mac &>/dev/null 2>&1          && PREMIERE_OK=true
BREW_OK=false;       command -v brew &>/dev/null                                                         && BREW_OK=true
PVF_OK=false
{ [ -d "/Library/Apple/System/Library/CoreServices/ProVideoFormats.bundle" ] || \
  pkgutil --pkg-info com.apple.pkg.ProVideoFormats &>/dev/null 2>&1; } && PVF_OK=true

would_run()  { echo "  🚀  $1"; }
would_skip() { echo "  ⏭️  $1"; }
already_done(){ echo "  ✅  $1"; }

echo ""

# Premiere shortcuts & workspace
if $PREMIERE_OK; then
  would_run  "Premiere shortcuts"
  would_run  "Premiere workspace"
  if $FAST; then would_skip "Premiere plugins (--fast)"
  else           would_run  "Premiere plugins — Animation Composer, Flicker Free"; fi
else
  would_skip "Premiere shortcuts — not installed"
  would_skip "Premiere workspace — not installed"
  would_skip "Premiere plugins — not installed"
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
CORE_UV="triplecheck"
FULL_FORMULAE="atomicparsley bento4 wget git"
FULL_CASKS="google-chrome mediahuman-audio-converter audacity appcleaner"

formula_installed() { $BREW_OK && brew list --formula "$1" &>/dev/null 2>&1; }
cask_installed()    { $BREW_OK && brew list --cask    "$1" &>/dev/null 2>&1; }
uv_installed()      { command -v uv &>/dev/null && uv tool list 2>/dev/null | grep -q "^$1"; }

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
# Premiere Pro shortcuts & workspace
# -----------------------------------------------------------------------------

if $PREMIERE_OK; then
  # Drop the shortcuts
  for dir in "$HOME/Documents/Adobe/Premiere Pro"/*/; do
    if ls "$dir"Profile-*/Mac &>/dev/null 2>&1; then
      (cd "$dir" && curl -fsSL -O "https://raw.githubusercontent.com/lucuma13/load/main/src/data/Luis_Mengo_25.1.kys")
    fi
  done

  # Drop the workspace
  for profile in "$HOME/Documents/Adobe/Premiere Pro"/*/Profile-*/; do
    [ -d "$profile" ] || continue
    mkdir -p "${profile}Layouts"
    (cd "${profile}Layouts" && curl -fsSL -O "https://raw.githubusercontent.com/lucuma13/load/main/src/data/UserWorkspace_LGG.xml")
  done
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
