#!/bin/bash
# Mac workstation setup script
# Usage: curl -fsSL https://raw.githubusercontent.com/lucuma13/load/main/setup-mac.sh | bash

set -euo pipefail

PROGRESS_DIR="$HOME/.mac_setup"
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

# Cache sudo credentials once, silently, and keep them alive
sudo -v
while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done 2>/dev/null &

# ── Change default shell to bash ───────────────────────────────────────────────

if is_done "chsh"; then
  echo "  ✅ shell"
else
  header "shell → bash"
  chsh -s /bin/bash
  echo 'export BASH_SILENCE_DEPRECATION_WARNING=1' >> "$HOME/.bash_profile"
  mark_done "chsh"
fi

# Ensure we're running in bash regardless
if [ -z "${BASH_VERSION:-}" ]; then
  exec /bin/bash "$0" "$@"
fi

# ── Premiere Pro shortcuts ─────────────────────────────────────────────────────

if ! ls "$HOME/Documents/Adobe/Premiere Pro"/*/Profile-*/Win &>/dev/null 2>&1; then
  echo "  ⚠️  Premiere Pro not found — skipping shortcuts."
else
  header "Premiere Pro shortcuts"
  for dir in "$HOME/Documents/Adobe/Premiere Pro"/*/; do
    if ls "$dir"Profile-*/Win &>/dev/null 2>&1; then
      (cd "$dir" && curl -fsSL -O "https://raw.githubusercontent.com/lucuma13/load/main/Luis_Mengo_25.1.kys")
    fi
  done
fi

# ── Keyboard / Trackpad / Battery preferences ──────────────────────────────────

if is_done "system_prefs"; then
  echo "  ✅ system prefs"
else
  header "keyboard / trackpad / battery"
  defaults write NSGlobalDomain KeyRepeat -int 2
  defaults write NSGlobalDomain InitialKeyRepeat -int 15
  defaults write NSGlobalDomain com.apple.trackpad.scaling -float 2
  defaults write com.apple.controlcenter BatteryShowPercentage -bool true
  mark_done "system_prefs"
fi

# ── Finder preferences ─────────────────────────────────────────────────────────

if is_done "finder"; then
  echo "  ✅ finder"
else
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
  mark_done "finder"
fi

# ── TextEdit preferences ───────────────────────────────────────────────────────

if is_done "textedit"; then
  echo "  ✅ textedit"
else
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
  mark_done "textedit"
fi

# ── Install Homebrew ───────────────────────────────────────────────────────────

if is_done "homebrew"; then
  echo "  ✅ homebrew"
else
  header "homebrew"
  echo | /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

  PREFIX="$(brew_prefix)"
  SHELLENV_LINE="eval \"\$(${PREFIX}/bin/brew shellenv bash)\""
  echo >> "$HOME/.bash_profile"
  echo "$SHELLENV_LINE" >> "$HOME/.bash_profile"
  eval "$("${PREFIX}/bin/brew" shellenv bash)"
  mark_done "homebrew"
fi

# Ensure brew is in PATH even if step was skipped
PREFIX="$(brew_prefix)"
eval "$("${PREFIX}/bin/brew" shellenv bash)" 2>/dev/null || true

# ── Brew formulas, casks & uv tools ───────────────────────────────────────────

if is_done "brew_packages"; then
  echo "  ✅ brew packages"
else
  header "brew"
  brew install git media-info exiftool ffmpeg atomicparsley bento4 wget uv
  brew install --cask google-chrome vlc caffeine audacity mediainfo mediahuman-audio-converter appcleaner
  uv tool install triplecheck
  mark_done "brew_packages"
fi

# ── Pro Video Formats ──────────────────────────────────────────────────────────

if is_done "pro_video_formats"; then
  echo "  ✅ pro video formats"
else
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
  mark_done "pro_video_formats"
fi

# ── Done ───────────────────────────────────────────────────────────────────────

echo ""
echo "  done ✅"
echo ""
echo "  ⚠️  log out and back in for keyboard / trackpad / battery prefs to take effect"
echo ""
echo "  🗑️  rm -rf ~/.mac_setup"
echo ""