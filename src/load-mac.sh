#!/bin/bash
# Mac workstation setup script
# Usage: curl -fsSL https://raw.githubusercontent.com/lucuma13/load/main/src/load-mac.sh | bash -s -- --full

set -euo pipefail

PROGRESS_DIR="$HOME/Downloads/.load-mac"
mkdir -p "$PROGRESS_DIR"

mark_done() { touch "$PROGRESS_DIR/$1"; }
is_done()   { [ -f "$PROGRESS_DIR/$1" ]; }

brew_prefix() {
  if [ -n "${HOMEBREW_PREFIX:-}" ]; then
    echo "$HOMEBREW_PREFIX"
  elif [ -f "/opt/homebrew/bin/brew" ]; then
    echo "/opt/homebrew"
  else
    echo "/usr/local"
  fi
}

# ── Preflight ──────────────────────────────────────────────────────────────────

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
BREW_PKGS_OK=false;  is_done "brew_packages"                                                             && BREW_PKGS_OK=true
BREW_FULL_OK=false;  is_done "brew_packages_full"                                                        && BREW_FULL_OK=true
PVF_OK=false
{ [ -d "/Library/Apple/System/Library/CoreServices/ProVideoFormats.bundle" ] || \
  pkgutil --pkg-info com.apple.pkg.ProVideoFormats &>/dev/null 2>&1; } && PVF_OK=true

would_run()  { echo "  🚀  $1"; }
would_skip() { echo "  ⏭️  $1"; }
already_done(){ echo "  ✅  $1"; }

echo ""

# Premiere shortcuts
if $PREMIERE_OK; then
  would_run  "Premiere shortcuts"
else
  would_skip "Premiere shortcuts — not installed"
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

  [ -n "$PKGS_DONE" ] && already_done "managed packages: $(echo $PKGS_DONE | tr ' ' ',')"
  [ -n "$PKGS_TODO" ] && would_run    "managed packages: $(echo $PKGS_TODO | tr ' ' ',')"
fi

# Pro Video Formats
if $PVF_OK; then
  already_done "Pro Video Formats"
elif $FAST; then
  would_skip "Pro Video Formats (--fast)"
else
  would_run "Pro Video Formats"
fi

echo ""
$DRY_RUN && exit 0

# Cache sudo credentials once, silently, and keep them alive
sudo -v
while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done 2>/dev/null &

# ── Premiere Pro shortcuts ─────────────────────────────────────────────────────

if $PREMIERE_OK; then
  for dir in "$HOME/Documents/Adobe/Premiere Pro"/*/; do
    if ls "$dir"Profile-*/Win &>/dev/null 2>&1; then
      (cd "$dir" && curl -fsSL -O "https://raw.githubusercontent.com/lucuma13/load/main/src/data/Luis_Mengo_25.1.kys")
    fi
  done
fi

# ── System preferences ───–––––––––––––––––––––––───────────────────────────────

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

# ── Finder preferences ─────────────────────────────────────────────────────────

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

# ── TextEdit preferences ───────────────────────────────────────────────────────

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

# ── Install Homebrew ───────────────────────────────────────────────────────────

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

# ── Managed packages ──────────────────────────────────────────────────────────

if ! $BREW_PKGS_OK && ! $FAST; then
  brew install --adopt media-info exiftool ffmpeg uv
  brew install --cask --adopt vlc caffeine mediainfo
  uv tool install triplecheck
  mark_done "brew_packages"
fi

if $FULL && ! $BREW_FULL_OK && ! $FAST; then
  brew install --adopt atomicparsley bento4 wget git
  brew install --cask --adopt google-chrome mediahuman-audio-converter audacity appcleaner
  mark_done "brew_packages_full"
fi

# ── Pro Video Formats ──────────────────────────────────────────────────────────

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

# ── Done ───────────────────────────────────────────────────────────────────────

echo ""
echo "  done ✅"
echo ""
echo "  ⚠️  please restart the computer for system prefs to take effect"
echo ""