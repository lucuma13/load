#!/bin/bash
# Mac workstation setup script
# Copyright (c) 2026 Luis Gómez Gutiérrez
#
# Usage:
# bash <(curl -fsSL https://raw.githubusercontent.com/lucuma13/load/main/src/load-mac.sh)
#
# Process substitution is the recommended form — flags pass straight through, e.g.
# `bash <(curl -fsSL …) --full`. The script's work is wrapped in main() and invoked
# on the last line, so bash reads and parses the whole script before running anything:
# a truncated download can't half-execute, and a piped (`curl | bash`) download can't
# have its tail drained by a child process (e.g. brew's ca-certificates keychain step).

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

would_run() { echo "  🚀  $1"; }
would_skip() { echo "  ⏭️  $1"; }
already_done() { echo "  ✅  $1"; }
checking() { echo "  🔎  $1"; }

# quiet_run <cmd…> — run a command fully silent on success: buffer its combined
# output and echo it only if the command fails, then propagate the failure (so
# set -e still aborts). Used to keep brew truly quiet (--quiet only trims "some"
# output and still streams install progress).
quiet_run() {
  local out rc
  out="$("$@" 2>&1)" && rc=0 || rc=$?
  [ "$rc" -eq 0 ] || printf '%s\n' "$out"
  return "$rc"
}

formula_installed() { $BREW_OK && brew list --formula "$1" &>/dev/null 2>&1; }
cask_installed() { $BREW_OK && brew list --cask "$1" &>/dev/null 2>&1; }
uv_installed() { command -v uv &>/dev/null && uv tool list 2>/dev/null | grep -q "^$1"; }

# resolve_mode <args…> — echo the setup flags present, normalised and deduped
# (a space-separated subset of "fast full dryrun"); empty when none were given.
resolve_mode() {
  local arg out=""
  for arg in "$@"; do
    case "$arg" in
    --fast) case " $out " in *" fast "*) ;; *) out="$out fast" ;; esac ;;
    --full) case " $out " in *" full "*) ;; *) out="$out full" ;; esac ;;
    --dry-run) case " $out " in *" dryrun "*) ;; *) out="$out dryrun" ;; esac ;;
    esac
  done
  echo "${out# }"
}

usage() {
  echo "Usage: load-mac.sh [--fast | --full | --dry-run]" >&2
  echo "  Run with no flag in a terminal to run Fast, then continue on Full." >&2
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

# customise_premiere_pro <prefs> <kys_file> <ws_name> <version> — point Premiere's prefs at
# the keyboard set + workspace, apply the Classic label preset, enable auto-save
# every 5 minutes, and turn on the timeline's Link Selection + Display Settings.
# Every node is matched exactly; any not found is left untouched and collected into
# a single warning, so the script never crashes or corrupts the prefs on a version bump.
#
# A missing-node warning can mean one of two things:
#   (a) Fresh Premiere install — Premiere only writes certain nodes to disk after
#       a user first manually changes them. Warning is harmless; the setting is
#       already at the correct value.
#   (b) Adobe renamed the node in this Premiere version — the setting was NOT
#       applied and the script needs updating.
# Either way the file is left untouched for that node.
customise_premiere_pro() {
  local prefs="$1" kys_file="$2" ws_name="$3" version="$4"
  # "Classic" label colour preset: 16 names + 16 colours + a RecentPreset marker
  # (Premiere has no single preset switch, so we write the exact values).
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
    set_pref_node "$prefs" "BE.Prefs.LabelNames.$i" "${label_names[$i]}" || missing+=("BE.Prefs.LabelNames.$i")
    set_pref_node "$prefs" "BE.Prefs.LabelColors.$i" "${label_colors[$i]}" || missing+=("BE.Prefs.LabelColors.$i")
  done
  set_pref_node "$prefs" "PPro.LabelColorPresets.RecentPreset" '{"builtIn":true,"name":"Classic"}' || missing+=("PPro.LabelColorPresets.RecentPreset")

  # Auto-save: on, every 5 minutes
  set_pref_node "$prefs" "BE.Prefs.AutoSave.DoSave" "true" || missing+=("BE.Prefs.AutoSave.DoSave")
  set_pref_node "$prefs" "BE.Prefs.AutoSave.Interval" "5" || missing+=("BE.Prefs.AutoSave.Interval")

  # Timeline toggles: Link Selection + Display Settings (wrench menu).
  # The Display Settings nodes below are commented out for now because they are not
  # written to the preference file until the default behaviour has changed:
  #   be.Prefs.Timeline.Show.Video.Thumbnails
  #   be.Prefs.Timeline.Show.Video.Names
  #   be.Prefs.Timeline.Show.Audio.Waveforms
  #   be.Prefs.Timeline.Show.Audio.Names
  #   be.Prefs.Timeline.Show.Proxy.Badges
  #   TL.PREFShowFXBadges
  for tl_node in \
    TL.PREFLinkedSelectionState \
    TL.PREFShowThroughEditsState \
    MZ.SQShowDuplicateMarkers; do
    set_pref_node "$prefs" "$tl_node" "true" || missing+=("$tl_node")
  done

  # A missing node leaves the file untouched for that node (never corrupted). It's
  # expected on a fresh install (nodes default to the preferred value and are only
  # written by Premiere after a manual change); otherwise Adobe may have renamed
  # the node and the script needs revising.
  if [ "${#missing[@]}" -gt 0 ]; then
    echo "  ⚠️  Premiere prefs on version ${version}: ${#missing[@]} preference node(s) not found and skipped (file untouched for those nodes):"
    printf '        - %s\n' "${missing[@]}"
    echo "      This is expected on a fresh install (nodes default to the correct value"
    echo "      and are only written by Premiere after a manual change). Otherwise,"
    echo "      Adobe may have renamed these nodes — check and update the script."
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

# Managed package lists. Kept above the guard so the test suite can source them
# and confirm every formula/cask still resolves (catches renames/delisting/typos).
CORE_FORMULAE="media-info exiftool ffmpeg uv"
CORE_CASKS="vlc caffeine mediainfo"
CORE_UV="triplecheck mhl-suite"
FULL_FORMULAE="git" # add these if needed: atomicparsley, bento4, wget
FULL_CASKS="google-chrome adobe-acrobat-reader audacity mediahuman-audio-converter appcleaner"

# Friendly display names for the brew/uv ids (used by the checklist). Anything
# without a mapping passes through unchanged (uv tool names are already readable).
pkg_alias() {
  case "$1" in
  media-info) echo "MediaInfo CLI" ;;
  mediainfo) echo "MediaInfo GUI" ;;
  exiftool) echo "ExifTool" ;;
  ffmpeg) echo "FFmpeg" ;;
  vlc) echo "VLC" ;;
  caffeine) echo "Caffeine" ;;
  google-chrome) echo "Google Chrome" ;;
  adobe-acrobat-reader) echo "Adobe Acrobat Reader" ;;
  audacity) echo "Audacity" ;;
  appcleaner) echo "AppCleaner" ;;
  *) echo "$1" ;;
  esac
}

# Sourced as a library (tests set LOAD_LIB=1): stop here, run nothing below.
[ -n "${LOAD_LIB:-}" ] && return 0 2>/dev/null

set -euo pipefail

# -----------------------------------------------------------------------------
# Resolve the setup mode — prompt when run with no flag
# -----------------------------------------------------------------------------

MODES="$(resolve_mode "$@")"

FAST=false
FULL=false
DRY_RUN=false
case " $MODES " in *" fast "*) FAST=true ;; esac
case " $MODES " in *" full "*) FULL=true ;; esac
case " $MODES " in *" dryrun "*) DRY_RUN=true ;; esac

# No flag given — run the Fast pass inline now (quick config), then pause and
# continue into the Full pass in this same process (see the Dispatch section). We
# need a terminal to prompt for that hand-off; under process substitution stdin may
# be redirected, so probe /dev/tty rather than stdin. Bail if there is none (e.g.
# CI) so we don't run a heavy install unattended.
AUTO=false
if [ -z "$MODES" ]; then
  { exec 3<>/dev/tty; } 2>/dev/null || {
    usage
    exit 1
  }
  exec 3>&-
  AUTO=true
  FAST=true
fi

# Phase gates. run_fast applies lightweight config; run_slow does the
# downloads/installs. Both run in this one process: the bare command runs Fast
# inline then continues into Slow; --fast runs Fast only; --full runs both.
RUN_FAST=true
RUN_SLOW=true
$FAST && RUN_SLOW=false

# -----------------------------------------------------------------------------
# Preflight
# -----------------------------------------------------------------------------

PREMIERE_OK=false
[ -d "$HOME/Documents/Adobe/Premiere Pro" ] && PREMIERE_OK=true
# Premiere rewrites its prefs on exit — activating a set while it's running would get clobbered.
# Match the process name (version-agnostic) rather than full args, which would hit our own perl call.
PREMIERE_RUNNING=false
$PREMIERE_OK && pgrep "Adobe Premiere Pro" &>/dev/null 2>&1 && PREMIERE_RUNNING=true
BREW_OK=false
command -v brew &>/dev/null && BREW_OK=true
PVF_OK=false
pkgutil --pkg-info com.apple.pkg.ProVideoFormats &>/dev/null 2>&1 && PVF_OK=true
# First mounted SCRATCH* volume, or "" if none.
scratch_vols=(/Volumes/SCRATCH*)
SCRATCH=""
[ -d "${scratch_vols[0]}" ] && SCRATCH="${scratch_vols[0]}"

# Work dir — every download (the LUT pack and the plugin installers) goes here, so
# all our temp files live under one folder instead of scattering across ~/Downloads
# (mirrors $WorkDir in load-win.ps1). Created lazily by the phase that downloads, so
# a --dry-run leaves the disk untouched.
WORKDIR="$HOME/Downloads/load-mac"

# Premiere shortcut set + workspace we distribute (used by run_fast and the
# "is it applied?" checklist detector).
KYS_FILE="LGG_25.1.kys"
WS_FILE="UserWorkspace_LGG.xml"

# -----------------------------------------------------------------------------
# Checklist — the live state of every action, derived from the real current state
# plus the run mode. The same call works as a preview (a --dry-run, nothing done
# yet) or as a post-install summary at the end (state reflects what ran). Mirrors
# the sections and merged categories of the checklist in load-win.ps1.
# -----------------------------------------------------------------------------

# premiere_applied — true once our shortcut set is active in any Premiere profile
# (the prefs' Shortcuts.Filename points at our .kys).
premiere_applied() {
  $PREMIERE_OK || return 1
  local profile prefs
  for profile in "$HOME/Documents/Adobe/Premiere Pro"/*/Profile-*/; do
    prefs="${profile}Adobe Premiere Pro Prefs"
    [ -f "$prefs" ] || continue
    if grep -qF "<FE.Prefs.Shortcuts.Filename>$KYS_FILE</FE.Prefs.Shortcuts.Filename>" "$prefs"; then
      return 0
    fi
  done
  return 1
}

# luts_present — true once at least one LUT has been downloaded.
luts_present() { ls "$WORKDIR/LUTs/"* >/dev/null 2>&1; }

# prefs_applied — true once the lightweight System/Finder/TextEdit config is in
# place (probe a representative key, mirroring the Windows keyboard check).
prefs_applied() {
  [ "$(defaults read NSGlobalDomain KeyRepeat 2>/dev/null)" = "2" ] &&
    [ "$(defaults read com.apple.dock autohide 2>/dev/null)" = "1" ]
}

# Premiere plugins already on the machine (detected by install path). Mister Horse's
# Product Manager lands in /Applications; Flicker Free drops its .plugin under the
# shared Adobe MediaCore tree (nested in a "Digital Anarchy/Flicker Free AE <ver>"
# folder), so we search the tree rather than assuming a fixed depth.
misterhorse_installed() { ls -d /Applications/*[Mm]ister*[Hh]orse* >/dev/null 2>&1; }
flickerfree_installed() {
  find "/Library/Application Support/Adobe/Common/Plug-ins" -iname "*flicker*free*" -print -quit 2>/dev/null | grep -q .
}

# mediainfo_gui_external — true when a MediaInfo.app is present but NOT managed by
# Homebrew, i.e. installed another way (e.g. the better-integrated Mac App Store
# build; the cask and the App Store build share the same /Applications path). We
# leave that one alone: skip the cask entirely rather than override or adopt it.
mediainfo_gui_external() { [ -d "/Applications/MediaInfo.app" ] && ! cask_installed mediainfo; }

checklist() {
  echo ""

  # Premiere Pro — shortcuts, workspace, preferences, media cache and the LUT pack
  # are the editing setup, so they show as one line and all require Premiere
  # installed. (When Premiere is open the files are dropped but not activated.)
  local items="shortcuts, workspace, preferences"
  [ -n "$SCRATCH" ] && items="$items, media cache"
  items="$items, LUTs"
  local premiere_line="Premiere Pro ($items)"
  if ! $PREMIERE_OK; then
    would_skip "$premiere_line — not installed"
  elif $PREMIERE_RUNNING; then
    would_skip "$premiere_line — Premiere Pro is open"
  elif premiere_applied && luts_present; then
    already_done "$premiere_line"
  else
    would_run "$premiere_line"
  fi

  # System, Finder & TextEdit preferences — the lightweight config.
  if prefs_applied; then
    already_done "System, Finder & TextEdit preferences"
  else
    would_run "System, Finder & TextEdit preferences"
  fi

  # Pro Video Formats
  if $PVF_OK; then
    already_done "Pro Video Formats"
  elif $FAST; then
    would_skip "Pro Video Formats (--fast)"
  else
    would_run "Pro Video Formats"
  fi

  # Install or update — Homebrew, managed packages, Premiere plugins and uv tools,
  # each paired with its installed check (mirrors the Windows checklist's one merged
  # line). Friendly names come from pkg_alias.
  local formulae_list="$CORE_FORMULAE" casks_list="$CORE_CASKS"
  $FULL && formulae_list="$formulae_list $FULL_FORMULAE"
  $FULL && casks_list="$casks_list $FULL_CASKS"

  local apps_all="" apps_done="" apps_todo="" pkg name

  name="Homebrew"
  apps_all="$apps_all, $name"
  if ! $FAST; then
    if $BREW_OK; then apps_done="$apps_done, $name"; else apps_todo="$apps_todo, $name"; fi
  fi
  for pkg in $formulae_list; do
    name="$(pkg_alias "$pkg")"
    apps_all="$apps_all, $name"
    if ! $FAST; then
      if formula_installed "$pkg"; then apps_done="$apps_done, $name"; else apps_todo="$apps_todo, $name"; fi
    fi
  done
  for pkg in $casks_list; do
    name="$(pkg_alias "$pkg")"
    apps_all="$apps_all, $name"
    if ! $FAST; then
      # MediaInfo GUI counts as done when a MediaInfo.app is already present, even if
      # Homebrew isn't managing it (e.g. an App Store install we deliberately leave alone).
      if cask_installed "$pkg" || { [ "$pkg" = mediainfo ] && mediainfo_gui_external; }; then
        apps_done="$apps_done, $name"
      else
        apps_todo="$apps_todo, $name"
      fi
    fi
  done
  if $PREMIERE_OK; then
    apps_all="$apps_all, Mister Horse"
    if ! $FAST; then
      if misterhorse_installed; then apps_done="$apps_done, Mister Horse"; else apps_todo="$apps_todo, Mister Horse"; fi
    fi
    apps_all="$apps_all, Flicker Free"
    if ! $FAST; then
      if flickerfree_installed; then apps_done="$apps_done, Flicker Free"; else apps_todo="$apps_todo, Flicker Free"; fi
    fi
  fi
  for pkg in $CORE_UV; do
    name="$(pkg_alias "$pkg")"
    apps_all="$apps_all, $name"
    if ! $FAST; then
      if uv_installed "$pkg"; then apps_done="$apps_done, $name"; else apps_todo="$apps_todo, $name"; fi
    fi
  done

  apps_all="${apps_all#, }"
  apps_done="${apps_done#, }"
  apps_todo="${apps_todo#, }"

  if $FAST; then
    would_skip "Install or update (--fast) — $apps_all"
  else
    [ -n "$apps_done" ] && already_done "Install or update: $apps_done"
    [ -n "$apps_todo" ] && would_run "Install or update: $apps_todo"
  fi

  echo ""
}

# -----------------------------------------------------------------------------
# Phase functions
# -----------------------------------------------------------------------------
# run_fast — lightweight preference changes only (no downloads/installs).
# run_slow — everything that downloads or installs, plus the one Finder tweak
# that needs python3 from Command Line Tools. The bare command runs run_fast
# inline then continues into run_slow; --fast runs run_fast only and --full runs both.

run_fast() {
  # System preferences
  defaults write NSGlobalDomain KeyRepeat -int 2
  defaults write NSGlobalDomain InitialKeyRepeat -int 15
  defaults write NSGlobalDomain com.apple.trackpad.scaling -float 2
  defaults write com.apple.dock autohide -bool true
  defaults write com.apple.dock magnification -bool false
  defaults write com.apple.dock mru-spaces -bool false
  defaults write com.apple.dock orientation -string "bottom"
  defaults write com.apple.dock show-recents -bool false
  defaults write com.apple.dock tilesize -int 50
  if pmset -g batt | grep -q "InternalBattery"; then # Laptops only
    defaults write com.apple.controlcenter BatteryShowPercentage -bool true
  fi
  killall Dock

  # Finder preferences — the top-level keys. The nested "Calculate all sizes"
  # toggle needs python3 (Command Line Tools), so it lives in run_slow.
  defaults write NSGlobalDomain AppleShowAllExtensions -bool true
  defaults write com.apple.finder ShowPathbar -bool true
  defaults write com.apple.finder ShowStatusBar -bool true
  defaults write com.apple.finder FXDefaultSearchScope -string "SCcf"
  defaults write com.apple.finder NewWindowTarget -string "PfLo"
  defaults write com.apple.finder NewWindowTargetPath -string "file://${HOME}/Downloads/"
  killall Finder 2>/dev/null || true

  # TextEdit preferences
  defaults write NSGlobalDomain NSAutomaticDashSubstitutionEnabled -bool false
  defaults write NSGlobalDomain NSAutomaticTextCompletionEnabled -bool false
  defaults write com.apple.TextEdit CorrectSpellingAutomatically -bool false
  defaults write com.apple.TextEdit RichText -int 0
  defaults write com.apple.TextEdit ShowRuler -bool false
  defaults write com.apple.TextEdit SmartDashes -bool false
  defaults write com.apple.TextEdit TextReplacement -bool false
  killall cfprefsd
  killall AppleSpell 2>/dev/null || true
  killall TextEdit 2>/dev/null || true

  # Premiere Pro shortcuts, workspace & labels
  if $PREMIERE_OK; then
    for profile in "$HOME/Documents/Adobe/Premiere Pro"/*/Profile-*/; do
      [ -d "$profile" ] || continue
      prefs="${profile}Adobe Premiere Pro Prefs"

      # Drop the shortcuts into the Profile's Mac folder (where Premiere reads custom sets)
      (cd "${profile}Mac" && curl -fsSL -O "https://raw.githubusercontent.com/lucuma13/load/main/src/data/$KYS_FILE")

      # Drop the workspace into Layouts. Premiere auto-registers it on launch.
      (cd "${profile}Layouts" && curl -fsSL -O "https://raw.githubusercontent.com/lucuma13/load/main/src/data/$WS_FILE")
      ws_name="$(premiere_workspace_name "${profile}Layouts/$WS_FILE")"

      if $PREMIERE_RUNNING; then
        echo "  ⚠️  Premiere Pro is running — files dropped but not activated"
      elif [ -f "$prefs" ]; then
        # Version dir sits above Profile-* (e.g. ".../Premiere Pro/25.0/Profile-foo/"),
        # so the warning can be traced to the right install when several coexist.
        customise_premiere_pro "$prefs" "$KYS_FILE" "$ws_name" "$(basename "$(dirname "$profile")")"
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

    # LUTs — download LUTs into the work directory. The file list comes from the GitHub
    # contents API (new LUTs are picked up automatically)
    LUT_DIR="$WORKDIR/LUTs"
    LUT_API="https://api.github.com/repos/lucuma13/load/contents/src/data/LUTs?ref=main"
    mkdir -p "$LUT_DIR"
    LUT_URLS="$(curl -fsSL "$LUT_API" | grep -o 'https://raw.githubusercontent.com/[^"]*' || true)"
    for url in $LUT_URLS; do
      (cd "$LUT_DIR" && curl -fsSL -O "$url")
    done
  fi
}

run_slow() {
  # Command Line Tools (provides git/python3; required by Homebrew). Without this,
  # a fresh Mac triggers the Xcode CLT dialog mid-run and aborts; we pop the
  # installer and wait for it to finish.
  if ! xcode-select -p &>/dev/null; then
    echo "  🚀  Command Line Tools — installing (accept the dialog; this can take a few minutes)…"
    xcode-select --install &>/dev/null || true
    # The installer window opens behind the terminal, so nudge it to the front
    # while we wait so the user doesn't miss the dialog.
    until xcode-select -p &>/dev/null; do
      osascript -e 'tell application "System Events" to set frontmost of (first process whose name is "Install Command Line Developer Tools") to true' &>/dev/null || true
      sleep 10
    done
  fi

  # Finder "Calculate all sizes" — a nested plist key defaults(1) can't reach, so
  # we edit it with python3. Quit Finder first so it doesn't rewrite the plist on
  # exit and clobber the edit.
  if command -v python3 &>/dev/null; then
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
  else
    echo "  ⚠️  Finder 'Calculate all sizes' skipped — python3 not available"
  fi

  # Cache sudo credentials (only the steps below need root) and keep them alive
  sudo -v
  while true; do
    sudo -n true
    sleep 60
    kill -0 "$$" || exit
  done 2>/dev/null &

  # Homebrew — install it, or refresh it (update + cleanup) when already present.
  if ! $BREW_OK; then
    would_run "Installing Homebrew"
    echo | quiet_run /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

    PREFIX="$(brew_prefix)"
    SHELLENV_LINE="eval \"\$(${PREFIX}/bin/brew shellenv)\""
    echo >>"$HOME/.zprofile"
    echo "$SHELLENV_LINE" >>"$HOME/.zprofile"
    eval "$("${PREFIX}/bin/brew" shellenv)"
  fi

  # Ensure brew is in PATH even if already installed
  PREFIX="$(brew_prefix)"
  eval "$("${PREFIX}/bin/brew" shellenv)" 2>/dev/null || true

  # Update a pre-existing Homebrew (but don't upgrade packages that are not ours).
  if $BREW_OK; then
    would_run "Updating Homebrew"
    quiet_run brew update
    quiet_run brew cleanup
  fi

  # Core managed packages. Skip the MediaInfo GUI cask only when a MediaInfo.app is
  # present but NOT brew-managed (e.g. the better-integrated App Store build) — don't
  # override or adopt it.
  checking "Core packages: $(echo $CORE_FORMULAE | tr ' ' ,)"
  quiet_run brew install --adopt $CORE_FORMULAE
  local core_casks=""
  for cask in $CORE_CASKS; do
    [ "$cask" = mediainfo ] && mediainfo_gui_external && continue
    core_casks="$core_casks $cask"
  done
  # install --adopt brings in anything missing; upgrade --greedy then updates the
  # already-installed casks.
  checking "Core casks: $(echo $core_casks | tr ' ' ,)"
  quiet_run brew install --cask --adopt $core_casks
  quiet_run brew upgrade --cask --greedy $core_casks
  # --quiet drops uv's resolve/install progress on success but still prints errors.
  checking "uv tools: $(echo $CORE_UV | tr ' ' ,)"
  for pkg in $CORE_UV; do uv tool install "$pkg" --upgrade --quiet; done

  # Ensure uv-installed CLI tools (~/.local/bin) are on PATH. `uv tool
  # update-shell` detects the active shell and updates the right profile (safer
  # than hardcoding ~/.zprofile). Idempotent. Export covers the current session.
  if command -v uv &>/dev/null; then
    uv tool update-shell --quiet || true
  fi
  export PATH="$HOME/.local/bin:$PATH"

  # Downloads sort — put ~/Downloads in list view, sorted by Date Added (newest
  # first). A folder's view/sort has no `defaults` key, and Finder's AppleScript view
  # columns are locked down on recent macOS, so the only route is the binary .DS_Store.
  # It lives in the *parent* (~/.DS_Store) under the "Downloads" record: vstl=Nlsv
  # (list view) + lsvC.sortColumn=dateAdded (that column is already newest-first). We
  # edit it with the `ds_store` library, fetched on demand via uvx (uv is installed
  # above). Finder buffers .DS_Store in memory and rewrites it on quit, so we write
  # while Finder is quit, then relaunch. Fully guarded: missing uv, no network or an
  # unreadable/odd store just prints a note and the run continues.
  if command -v uvx &>/dev/null; then
    osascript -e 'tell application "Finder" to quit' 2>/dev/null || true
    sleep 2
    uvx --from ds-store python3 - <<'PY' 2>/dev/null || echo "  ⚠️  Downloads sort skipped (couldn't update .DS_Store)"
import os, plistlib
import ds_store

home = os.path.expanduser('~/.DS_Store')
# Standard list-view columns — used only when the Downloads record has no lsvC yet
# (e.g. a fresh Mac where Downloads was never opened in list view); Finder reconciles
# the rest. An existing lsvC is edited in place so the user's columns/widths survive.
TEMPLATE = {
    'viewOptionsVersion': 1, 'sortColumn': 'dateAdded', 'useRelativeDates': True,
    'showIconPreview': True, 'calculateAllSizes': True,
    'iconSize': 16.0, 'textSize': 13.0, 'scrollPositionX': 0.0, 'scrollPositionY': 0.0,
    'columns': [
        {'identifier': 'name',         'visible': True, 'width': 300, 'ascending': True},
        {'identifier': 'dateModified', 'visible': True, 'width': 181, 'ascending': False},
        {'identifier': 'dateAdded',    'visible': True, 'width': 181, 'ascending': False},
        {'identifier': 'size',         'visible': True, 'width': 97,  'ascending': False},
        {'identifier': 'kind',         'visible': True, 'width': 115, 'ascending': True},
    ],
}
try:
    mode = 'r+' if os.path.exists(home) else 'w+'
    with ds_store.DSStore.open(home, mode) as d:
        ent = {e.code: e for e in d if e.filename == 'Downloads'}
        # View style -> list
        if b'vstl' in ent:
            d.delete('Downloads', b'vstl')
        d.insert(ds_store.DSStoreEntry('Downloads', b'vstl', b'type', b'Nlsv'))
        # Sort -> Date Added, newest first
        pl = plistlib.loads(bytes(ent[b'lsvC'].value)) if b'lsvC' in ent else dict(TEMPLATE)
        pl['sortColumn'] = 'dateAdded'
        for c in pl.get('columns', []):
            if c.get('identifier') == 'dateAdded':
                c['visible'] = True
                c['ascending'] = False   # newest first
        if b'lsvC' in ent:
            d.delete('Downloads', b'lsvC')
        d.insert(ds_store.DSStoreEntry('Downloads', b'lsvC', b'blob',
                                       plistlib.dumps(pl, fmt=plistlib.FMT_BINARY)))
except Exception as ex:
    print("  ⚠️  Downloads sort skipped:", ex)
PY
    sleep 1
    open -a Finder 2>/dev/null || true
  fi

  # Full-only managed packages
  if $FULL; then
    checking "Full-only packages: $(echo $FULL_FORMULAE $FULL_CASKS | tr ' ' ,)"
    quiet_run brew install --adopt $FULL_FORMULAE
    quiet_run brew install --cask --adopt $FULL_CASKS
    quiet_run brew upgrade --cask --greedy $FULL_CASKS
  fi

  # Every installer below downloads into the work dir; create it once up front.
  mkdir -p "$WORKDIR"

  # Premiere plugins — Mister Horse's Product Manager installs & updates Animation
  # Composer (and the other Mister Horse plugins) into Premiere/After Effects. We
  # download the Product Manager installer and run it; Animation Composer itself is
  # then installed from within the app on first launch.
  if $PREMIERE_OK; then
    would_run "Installing Mister Horse Product Manager"
    PM_DMG="$WORKDIR/MisterHorseProductManager.dmg"
    curl -fsSL -o "$PM_DMG" "https://misterhorse.com/downloads/product-manager/osx"
    VOL="$(hdiutil attach "$PM_DMG" -nobrowse | grep -o '/Volumes/.*' | head -1 || true)"
    PM_APP="$(find "$VOL" -maxdepth 1 -name '*.app' 2>/dev/null | head -1 || true)"
    [ -n "$PM_APP" ] && sudo cp -R "$PM_APP" /Applications/
    [ -n "$VOL" ] && hdiutil detach "$VOL" -quiet
    rm -f "$PM_DMG"

    # Flicker Free — Digital Anarchy's deflicker plugin. The DMG holds a .pkg we
    # install straight to the system; the plugin then shows up in Premiere/AE.
    would_run "Installing Flicker Free"
    FF_DMG="$WORKDIR/flickerfree_229_AE.dmg"
    curl -fsSL -o "$FF_DMG" "https://www.digitalanarchy.com/downloads/flickerfree_229_AE.dmg"
    FF_VOL="$(hdiutil attach "$FF_DMG" -nobrowse | grep -o '/Volumes/.*' | head -1 || true)"
    FF_PKG="$(find "$FF_VOL" -maxdepth 1 -name '*.pkg' 2>/dev/null | head -1 || true)"
    # The pkg's preinstall script unconditionally runs `open <registration URL>`,
    # popping Digital Anarchy's sign-up page in the default browser — pure noise on an
    # unattended run. Close the tab that lands on that URL — in Safari and Chrome -
    # and clean up if that leaves an empty window behind.
    [ -n "$FF_PKG" ] && sudo installer -pkg "$FF_PKG" -target /
    sleep 3
    osascript <<'APPLESCRIPT' &>/dev/null || true
repeat with appName in {"Safari", "Google Chrome"}
  if application appName is running then
    tell application appName
      set matchingTabs to {}
      repeat with w in windows
        repeat with t in tabs of w
          if (URL of t contains "digitalanarchy.com") and (URL of t contains "registration") then
            set end of matchingTabs to t
          end if
        end repeat
      end repeat
      repeat with t in matchingTabs
        close t
      end repeat
      set emptyWindows to {}
      repeat with w in windows
        if (count of tabs of w) = 0 then set end of emptyWindows to w
      end repeat
      repeat with w in emptyWindows
        close w
      end repeat
    end tell
  end if
end repeat
APPLESCRIPT
    [ -n "$FF_VOL" ] && hdiutil detach "$FF_VOL" -quiet
    rm -f "$FF_DMG"
  fi

  # Pro Video Formats
  if ! $PVF_OK; then
    DMG_URL="https://updates.cdn-apple.com/2026/macos/072-84099-20260127-5022F0FE-82CF-44E9-B96D-430E73501EBA/ProVideoFormats.dmg"
    DMG_PATH="$WORKDIR/ProVideoFormats.dmg"

    if [ ! -f "$DMG_PATH" ]; then
      curl -o "$DMG_PATH" "$DMG_URL"
    fi

    hdiutil attach "$DMG_PATH" -nobrowse
    sudo installer -pkg "/Volumes/Pro Video Formats/ProVideoFormats.pkg" -target /
    hdiutil detach "/Volumes/Pro Video Formats" -quiet
    rm -f "$DMG_PATH"
  fi
}

# -----------------------------------------------------------------------------
# Dispatch — run_fast inline; the bare command then continues into the Full pass,
# and run_slow does the downloads/installs.
#
# Wrapped in main() and invoked only on the very last line. Under `bash <(curl …)`
# the script is read from the stream as it runs, so bash must parse this whole
# function (through its closing brace) before it can call it: a truncated download
# fails to parse and runs nothing that touches the system. Everything above main is
# read-only detection, so it's safe even if a partial read aborts before main. Keep
# the call bare (`main "$@"`) — invoking it in a conditional would disable `set -e`
# inside main.
# -----------------------------------------------------------------------------

main() {
  # --dry-run just prints the checklist, then stops.
  if $DRY_RUN; then
    checklist
    exit 0
  fi

  if $RUN_FAST; then run_fast; fi

  if $AUTO; then
    # Fast pass finished. Prompt, then continue into the Full pass in this same
    # process — flip the mode flags so run_slow and the summary below behave as a
    # full run. The single post-install summary at the end covers this Fast pass too.
    exec 3<>/dev/tty
    printf ""
    printf '%s' "

  ▶️  Fast loading is complete. Press enter to continue on FULL mode " >&3
    read -r _ <&3 || true
    echo ""
    exec 3>&-
    FAST=false
    FULL=true
    RUN_SLOW=true
  fi

  if $RUN_SLOW; then run_slow; fi

  # Summary
  checklist
  echo "  🛼  You're ready to roll!"
  echo ""
  echo "  ⚠️  Please restart the computer for all changes to take effect"
  echo ""
}

main "$@"
