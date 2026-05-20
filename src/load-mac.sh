#!/bin/bash
# Mac workstation setup script
# Usage: curl -fsSL https://raw.githubusercontent.com/lucuma13/load/main/src/load-mac.sh | bash

set -euo pipefail

PROGRESS_DIR="$HOME/Downloads/.mac_setup"
mkdir -p "$PROGRESS_DIR"

mark_done() { touch "$PROGRESS_DIR/$1"; }
is_done()   { [ -f "$PROGRESS_DIR/$1" ]; }

header() {
  echo ""
  echo "  · $1"
}

brew_prefix() {
  if [ -f "/opt/homebrew/bin/brew" ]; then
    echo "/opt/homebrew"
  else
    echo "/usr/local"
  fi
}

# ── Preflight ──────────────────────────────────────────────────────────────────

SHELL_OK=false;   [ "$SHELL" = "/bin/bash" ]                                                         && SHELL_OK=true
PREMIERE_OK=false; ls "$HOME/Documents/Adobe/Premiere Pro"/*/Profile-*/Win &>/dev/null 2>&1          && PREMIERE_OK=true
BREW_OK=false;    command -v brew &>/dev/null                                                         && BREW_OK=true
BREW_PKGS_OK=false; is_done "brew_packages"                                                           && BREW_PKGS_OK=true
PVF_OK=false;     system_profiler SPInstallHistoryDataType 2>/dev/null | grep -q "Pro Video Formats" && PVF_OK=true

echo ""
echo "  $( $SHELL_OK     && echo "✅" || echo "·" ) shell"
echo "  $( $PREMIERE_OK  && echo "✅" || echo "⚠️ adobe not found, skipping") premiere shortcuts"
echo "  ·  keyboard / trackpad / battery"
echo "  ·  finder"
echo "  ·  textedit"
echo "  $( $BREW_OK      && echo "✅" || echo "·" ) homebrew"
echo "  $( $BREW_PKGS_OK && echo "✅" || echo "·" ) brew packages"
echo "  $( $PVF_OK       && echo "✅" || echo "·" ) pro video formats"
echo ""

# Cache sudo credentials once, silently, and keep them alive
sudo -v
while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done 2>/dev/null &

# ── Change default shell to bash ───────────────────────────────────────────────

if ! $SHELL_OK; then
  header "shell → bash"
  chsh -s /bin/bash
  echo 'export BASH_SILENCE_DEPRECATION_WARNING=1' >> "$HOME/.bash_profile"
fi

# Ensure we're running in bash regardless
if [ -z "${BASH_VERSION:-}" ]; then
  exec /bin/bash "$0" "$@"
fi

# ── Premiere Pro shortcuts ─────────────────────────────────────────────────────

if $PREMIERE_OK; then
  header "premiere pro shortcuts"
  for dir in "$HOME/Documents/Adobe/Premiere Pro"/*/; do
    if ls "$dir"Profile-*/Win &>/dev/null 2>&1; then
      (cd "$dir" && curl -fsSL -O "https://raw.githubusercontent.com/lucuma13/load/main/src/data/Luis_Mengo_25.1.kys")
    fi
  done
fi

# ── Keyboard / Trackpad / Battery preferences ──────────────────────────────────

header "keyboard / trackpad / battery"
defaults write NSGlobalDomain KeyRepeat -int 2
defaults write NSGlobalDomain InitialKeyRepeat -int 15
defaults write NSGlobalDomain com.apple.trackpad.scaling -float 2
defaults write com.apple.controlcenter BatteryShowPercentage -bool true

# ── Finder preferences ─────────────────────────────────────────────────────────

header "finder"
defaults write com.apple.finder ShowPathbar -bool true
defaults write com.apple.finder ShowStatusBar -bool true

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

header "textedit"
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

if ! $BREW_OK; then
  header "homebrew"
  echo | /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

  PREFIX="$(brew_prefix)"
  SHELLENV_LINE="eval \"\$(${PREFIX}/bin/brew shellenv bash)\""
  echo >> "$HOME/.bash_profile"
  echo "$SHELLENV_LINE" >> "$HOME/.bash_profile"
  eval "$("${PREFIX}/bin/brew" shellenv bash)"
fi

# Ensure brew is in PATH even if already installed
PREFIX="$(brew_prefix)"
eval "$("${PREFIX}/bin/brew" shellenv bash)" 2>/dev/null || true

# ── Brew formulas, casks & uv tools ───────────────────────────────────────────

if ! $BREW_PKGS_OK; then
  header "brew"
  brew install git media-info exiftool ffmpeg atomicparsley bento4 wget uv
  brew install --cask --adopt google-chrome vlc caffeine audacity mediainfo mediahuman-audio-converter appcleaner
  uv tool install triplecheck
  mark_done "brew_packages"
fi

# ── Pro Video Formats ──────────────────────────────────────────────────────────

if ! $PVF_OK; then
  header "pro video formats"
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
echo "  ⚠️  log out and back in for keyboard / trackpad / battery prefs to take effect"
echo ""