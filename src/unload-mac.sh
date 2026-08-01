#!/bin/bash
# Mac workstation cleanup script Copyright (c) 2026 Luis Gómez Gutiérrez
#
# It removes custom setup — load-mac's work directory, our Premiere Pro
# workspace templates, the Mister Horse Product Manager sign-in, Claude Code and
# the shell history. And it quits Google Chrome.
#
# Usage — --dry-run is the only option, and reports the very same run instead of
# performing it, a line per phase either way:
#
#   # preview it, change nothing
#   bash <(curl -fsSL https://raw.githubusercontent.com/lucuma13/load/main/src/unload-mac.sh) --dry-run
#
#   # do it
#   bash <(curl -fsSL https://raw.githubusercontent.com/lucuma13/load/main/src/unload-mac.sh)
#
# Process substitution is the recommended form — flags pass straight through. As
# in load-mac.sh the work is wrapped in main() and invoked on the last line, so
# bash parses the whole script before running anything: a truncated download
# can't half-execute.

# =============================================================================
# Function library
#
# Everything above the LOAD_LIB guard is side-effect-free definitions, so the
# test suite can `source` this file (with LOAD_LIB=1) to exercise individual
# functions without deleting anything.
# =============================================================================

# check_args <args…> — return 1 on any argument that isn't a recognised option.
#
# The bare command removes everything this script knows about, so an unrecognised
# argument must stop the run rather than be ignored: a typo'd "--dryrun" would
# otherwise fall through and be treated as a bare command.
check_args() {
  local arg
  for arg in "$@"; do
    case "$arg" in
    --dry-run | --help | -h) ;;
    *) return 1 ;;
    esac
  done
}

usage() {
  echo "Usage: unload-mac.sh [--dry-run]" >&2
  echo "" >&2
  echo "  Removes:" >&2
  echo "    - the work directory ~/Downloads/load-mac" >&2
  echo "    - the Premiere Pro workspaces" >&2
  echo "    - the Mister Horse Product Manager sign-in" >&2
  echo "    - claude-code" >&2
  echo "    - shell history" >&2
  echo "" >&2
  echo "  Quits (leaving the app and its data in place):" >&2
  echo "    - Google Chrome" >&2
  echo "" >&2
}

# Output is exactly one line per phase.
removing() { echo "  🧹  $1"; }
would() { echo "  🚀  $1"; }
skipped() { echo "  ⏩  $1"; }
note() { echo "  ℹ️  $1"; }

# did_it <verb-past> <verb-plain> <object…> — the result line of a phase that had
# something to do.
#
# Split into its verb so a dry run can say the same sentence in the conditional:
# "Removed shell history" becomes "Would remove shell history".
did_it() {
  local past="$1" plain="$2"
  shift 2
  if ${DRY_RUN:-false}; then
    would "Would $plain $*"
  else
    removing "$past $*"
  fi
}

# tilde <path> — Shorten a path under $HOME to ~/… for display. Presentation only.
tilde() {
  case "$1" in
  "$HOME"/*) echo "~${1#"$HOME"}" ;;
  *) echo "$1" ;;
  esac
}

# under_home <path> — true only for a path strictly inside $HOME and free of "..".
#
# Every removal this script makes is per-user, so this is the single guard between
# a variable that came back empty (or unexpanded, or relative) and an `rm -rf`
# with a catastrophic argument.
under_home() {
  case "${1:-}" in
  *..*) return 1 ;;
  "$HOME"/?*) return 0 ;;
  *) return 1 ;;
  esac
}

# rm_path <path> — remove a file, directory tree or symlink, honouring --dry-run.
#
# Silent: the caller reports the phase in one line. What it returns is the part
# callers use — whether there was anything there at all — which is what lets a
# phase tell "cleaned" from "already clean", on a dry run as on a real one.
rm_path() {
  local p="${1:-}"
  [ -e "$p" ] || [ -L "$p" ] || return 1
  under_home "$p" || {
    echo "  ⚠️  Refusing to remove '$p' — outside \$HOME"
    return 1
  }
  if ${DRY_RUN:-false}; then
    return 0
  fi
  rm -rf "$p"
}

# claude_casks_installed — echo the claude-code casks present on this machine.
# Homebrew ships both "claude-code@latest" and "claude-code"; a machine can
# carry either or both, so resolve it.
claude_casks_installed() {
  local cask
  for cask in claude-code claude-code@latest; do
    if brew list --cask "$cask" &>/dev/null; then echo "$cask"; fi
  done
  return 0
}

# claude_state_paths — echo every per-user path Claude Code writes, one per line.
#
# ~/.claude is the one that matters on a machine you're leaving: it holds the
# conversation transcripts, per-project history and memory files, not just config.
#
# ~/Library/Application Support/Claude is deliberately NOT here. That belongs to
# the Claude desktop app, which is a separate product that may well be someone
# else's; only the CLI's own state is in scope.
claude_state_paths() {
  echo "$HOME/.claude"
  echo "$HOME/.claude.json"
  echo "$HOME/.claude.json.backup"
  echo "$HOME/Library/Caches/claude-cli-nodejs"
}

# misterhorse_state_paths — echo every per-user path holding the Mister Horse
# sign-in.
#
# The session lives in the app's own encrypted .dat files under ~/Library/
# Application Support/MisterHorse (ProductManager/as.dat is the account itself,
# and the Premiere/After Effects panels keep their own copy beside it) — so
# removing that tree is the local sign-out.
#
# The Product Manager signs in through a web view, so its cookies sit in
# ~/Library/HTTPStorages and part of the account state is mirrored into
# ~/Library/Caches.
misterhorse_state_paths() {
  local p
  echo "$HOME/Library/Application Support/MisterHorse"
  for p in "$HOME/Library/HTTPStorages/com.misterhorse."* "$HOME/Library/Caches/com.misterhorse."*; do
    [ -e "$p" ] && echo "$p"
  done
  return 0
}

# misterhorse_pids — echo the pid of every running Mister Horse process (the
# Product Manager and the helpers beside it).
misterhorse_pids() {
  ps -xo pid=,comm= | awk 'tolower($0) ~ /mister ?horse/ { print $1 }'
}

# chrome_pids — echo the pid of every running Google Chrome process (the browser
# and the renderer/GPU helpers beside it).
#
# Matched on the executable path like misterhorse_pids, because that is what
# `comm` prints: the helpers are named "Google Chrome Helper (Renderer)" and the
# like, but every one of them runs out of Google Chrome.app, so the bundle is
# the thing to match. Anchored on ".app/" so a checkout or a download that
# merely has "Google Chrome" in its path can't be mistaken for the browser.
chrome_pids() {
  ps -xo pid=,comm= | awk '/Google Chrome\.app\// { print $1 }'
}

# WS_API — the repo's src/data listing, where the workspaces `load-mac` drops
# come from.
WS_API="https://api.github.com/repos/lucuma13/load/contents/src/data?ref=main"

# parse_workspace_names — read a GitHub contents listing on stdin and echo the
# name of every UserWorkspace_*.xml entry in it.
parse_workspace_names() {
  grep -o '"name"[[:space:]]*:[[:space:]]*"UserWorkspace_[^"]*\.xml"' |
    sed 's/.*"\(UserWorkspace_[^"]*\.xml\)"/\1/'
}

# workspace_names — echo the workspace filenames from the live listing. Empty
# when the fetch fails, which the caller reports rather than treating as
# "nothing to remove".
workspace_names() { curl -fsSL "${1:-$WS_API}" | parse_workspace_names; }

# premiere_layout_dirs — echo the Layouts folder of every Premiere Pro profile on
# this machine.
premiere_layout_dirs() {
  local profile
  for profile in "$HOME/Documents/Adobe/Premiere Pro"/*/Profile-*/; do
    [ -d "${profile}Layouts" ] && echo "${profile}Layouts"
  done
  return 0
}

# history_paths — echo every shell-history path to remove, one per line.
#
# $HISTFILE first because a customised history location must not be missed, but it
# is only readable when it happens to be exported (zsh doesn't export it by
# default), so the standard paths are listed unconditionally after it.
#
# ~/.zsh_sessions is included because it is history too — Terminal's "reopen
# windows" restores each session's commands from the .historynew files in there,
# so wiping ~/.zsh_history alone leaves them recoverable.
#
# Deduped, because $HISTFILE and $ZDOTDIR normally resolve to paths already listed
# below them. A real run wouldn't care (rm_path is silent the second time), but
# --dry-run would print the same path twice and read like a bug.
history_paths() {
  {
    [ -n "${HISTFILE:-}" ] && echo "$HISTFILE"
    echo "${ZDOTDIR:-$HOME}/.zsh_history"
    echo "$HOME/.zsh_history"
    echo "$HOME/.zsh_sessions"
    echo "$HOME/.bash_history"
  } | awk '!seen[$0]++'
}

# Sourced as a library (tests set LOAD_LIB=1): stop here, run nothing below.
[ -n "${LOAD_LIB:-}" ] && return 0 2>/dev/null

set -euo pipefail

# -----------------------------------------------------------------------------
# Flags — the only option is --dry-run.
# -----------------------------------------------------------------------------

check_args "$@" || {
  echo "  ⚠️  Unrecognised argument. Nothing was removed." >&2
  usage
  exit 1
}

case " $* " in *" --help "* | *" -h "*)
  usage
  exit 0
  ;;
esac

DRY_RUN=false
for _arg in "$@"; do [ "$_arg" = "--dry-run" ] && DRY_RUN=true; done

# -----------------------------------------------------------------------------
# Preflight
# -----------------------------------------------------------------------------

# Mirrors $WORKDIR in load-mac.sh — everything that run finished with (the LUT
# pack, the plugin DMGs it didn't get to delete) lives under this one folder.
WORKDIR="$HOME/Downloads/load-mac"

BREW_OK=false
command -v brew &>/dev/null && BREW_OK=true

# The macOS keychain service Claude Code stores its OAuth token under. Deleting
# this item IS the local sign-out — the CLI has no `logout` subcommand, and the
# token is kept in the login keychain rather than in ~/.claude, so wiping the
# state directory alone would leave a working credential behind on the machine.
CLAUDE_KEYCHAIN_SERVICE="Claude Code-credentials"

# -----------------------------------------------------------------------------
# Cleanup phases
# -----------------------------------------------------------------------------

clean_workdir() {
  if rm_path "$WORKDIR"; then
    did_it Removed remove "work directory ($(tilde "$WORKDIR"))"
  else
    skipped "Work directory - nothing to remove"
  fi
}

# clean_premiere_workspaces — remove our workspace files from every Premiere
# profile's Layouts folder.
clean_premiere_workspaces() {
  local did=false dirs names dir name
  dirs="$(premiere_layout_dirs)"
  # No Premiere profile means nothing to remove - and no reason to go to the
  # network for the list.
  if [ -z "$dirs" ]; then
    skipped "Premiere Pro workspaces - nothing to remove"
    return 0
  fi
  # `|| true` because set -o pipefail makes both halves fatal otherwise: a failed
  # curl (offline) and a grep that matches nothing both exit non-zero.
  names="$(workspace_names || true)"
  if [ -z "$names" ]; then
    echo "  ⚠️  Could not read the workspace list from GitHub — Premiere workspaces left in place"
    return 0
  fi
  while IFS= read -r dir; do
    while IFS= read -r name; do
      rm_path "$dir/$name" && did=true
    done <<<"$names"
  done <<<"$dirs"
  if $did; then
    did_it Removed remove "Premiere Pro workspaces"
  else
    skipped "Premiere Pro workspaces - nothing to remove"
  fi
}

# quit_chrome — ask Google Chrome to quit. Silent; the outcome comes back in the
# return code for clean_chrome to report:
#
#   0  it quit when asked
#   1  it wasn't running
#   2  it had to be forced
#
# Asked, not killed: `kill -9` costs the session — Chrome comes back with the
# "didn't shut down correctly" restore bar and a half-written profile — whereas
# an AppleScript quit closes the profile cleanly and saves
# the open tabs for next launch.
quit_chrome() {
  local waited=0 left
  [ -n "$(chrome_pids)" ] || return 1
  if $DRY_RUN; then
    return 0
  fi
  osascript -e 'tell application "Google Chrome" to quit' &>/dev/null || true
  while [ "$waited" -lt 10 ]; do
    left="$(chrome_pids)"
    [ -n "$left" ] || break
    sleep 1
    waited=$((waited + 1))
  done
  [ -z "$left" ] || {
    echo "$left" | xargs kill -9 2>/dev/null || true
    return 2
  }
}

# clean_chrome — quit Google Chrome.
#
# No process count in the lines below: Chrome runs a helper per tab, so a couple
# of windows is twenty-odd processes and a number there would read as twenty-odd
# windows about to close.
clean_chrome() {
  local rc=0
  quit_chrome || rc=$?
  case "$rc" in
  0) did_it Quit quit "Google Chrome" ;;
  2) removing "Quit Google Chrome — it did not close on its own, so it was forced" ;;
  *) skipped "Google Chrome - not running" ;;
  esac
}

# quit_misterhorse — quit the Product Manager so the sign-out below sticks, and
# return 1 when nothing was running.
quit_misterhorse() {
  local pids
  pids="$(misterhorse_pids)"
  [ -n "$pids" ] || return 1
  if $DRY_RUN; then
    return 0
  fi
  echo "$pids" | xargs kill -9 2>/dev/null || true
}

# clean_misterhorse — sign this account out of Mister Horse, leaving the plugins
# installed. See misterhorse_state_paths for why removing that state is the
# sign-out.
clean_misterhorse() {
  local did=false path
  quit_misterhorse && did=true
  while IFS= read -r path; do
    rm_path "$path" && did=true
  done <<<"$(misterhorse_state_paths)"
  if $did; then
    did_it "Signed out of" "sign out of" "Mister Horse Product Manager"
  else
    skipped "Mister Horse Product Manager - not signed in"
    return 0
  fi

  # A panel open inside a running Premiere or After Effects has the same session
  # in memory and writes its own copy back when the host quits, so a sign-out
  # performed underneath it does not stick. Killing the host would cost the user
  # unsaved work, so say so instead. Skipped on a dry run, where nothing has been
  # removed for a panel to undo.
  if ! $DRY_RUN && pgrep "Adobe Premiere Pro|Adobe After Effects" &>/dev/null; then
    note "Premiere Pro / After Effects is open — close it and re-run, or its Mister Horse panel will write the session back."
  fi
}

# claude_signout — drop the stored credential so the account is signed out on this
# machine. Runs BEFORE the uninstall (and before the state wipe) so it can't be
# stranded by either.
#
# Looped because the keychain can hold more than one item for a service (a second
# account, or a stale entry from an earlier sign-in) and each call deletes one.
# Bounded so a keychain that keeps returning success can't spin forever.
claude_signout() {
  local n=0
  if ! security find-generic-password -s "$CLAUDE_KEYCHAIN_SERVICE" &>/dev/null; then
    return 1
  fi
  if $DRY_RUN; then
    return 0
  fi
  while [ "$n" -lt 5 ] && security delete-generic-password -s "$CLAUDE_KEYCHAIN_SERVICE" &>/dev/null; do
    n=$((n + 1))
  done
  # The loop ends on a failing condition, so say so explicitly.
  return 0
}

clean_claude() {
  local did=false casks cask path

  claude_signout && did=true

  # Uninstall before wiping state: brew's own uninstall may want to read the
  # cask's metadata. The cask names stay out of the result line (e.g.
  # claude-code, claude-code@latest) and they appear only in the failure below,
  # which is there to be acted on.
  if $BREW_OK; then
    casks="$(claude_casks_installed)"
    [ -z "$casks" ] || did=true
    if ! $DRY_RUN; then
      for cask in $casks; do
        brew uninstall --cask --force "$cask" &>/dev/null ||
          echo "  ⚠️  'brew uninstall --cask $cask' failed — remove it by hand"
      done
    fi
  fi

  while IFS= read -r path; do
    rm_path "$path" && did=true
  done <<<"$(claude_state_paths)"

  if $did; then
    did_it Uninstalled uninstall "Claude Code"
  else
    skipped "Claude Code - nothing to uninstall"
    return 0
  fi

  # A `claude` still on PATH after all that was installed some other way — the
  # native installer (~/.local/bin) or a global npm package — which this script
  # deliberately doesn't touch. Say so rather than let a "cleaned" summary imply
  # the machine is clear. Skipped on a dry run, where nothing has been removed
  # yet and the binary is still there by definition.
  if ! $DRY_RUN && command -v claude &>/dev/null; then
    note "'claude' is still on PATH at $(command -v claude) — not a Homebrew install; remove it by hand"
  fi
}

clean_history() {
  local did=false path
  while IFS= read -r path; do
    rm_path "$path" && did=true
  done <<<"$(history_paths)"

  if $did; then
    did_it Removed remove "shell history"
  else
    skipped "Shell history - nothing to remove"
  fi
}

# -----------------------------------------------------------------------------
# Dispatch — wrapped in main() and invoked only on the very last line, so a
# truncated download fails to parse and deletes nothing. See the header comment;
# keep the call bare (`main "$@"`), as invoking it in a conditional would disable
# `set -e` inside it.
# -----------------------------------------------------------------------------

main() {
  echo ""
  if $DRY_RUN; then
    echo "  🔍  Dry run — nothing will be changed."
    echo ""
  fi

  clean_chrome
  clean_workdir
  clean_premiere_workspaces
  clean_misterhorse
  clean_claude
  clean_history

  echo ""
  if $DRY_RUN; then
    echo "  🔍  Nothing was changed. Re-run without --dry-run to do the above."
  else
    # The shell you launched this from holds its own commands in memory and
    # appends them to a fresh history file when it exits — including the command
    # that ran this script. Nothing a child process can do reaches into that
    # buffer, so sign off with the one-liner that stops it rather than leave a
    # file to reappear.
    echo "  🧽🧼💧 Almost clean now!"
    echo '  Run this here to remove current session shell history:'
    # Single-quoted because this line is for the user to paste, so the
    # expressions must expand in their shell, not ours.
    # shellcheck disable=SC2016
    echo '      unset HISTFILE; rm -f "${ZDOTDIR:-$HOME}/.zsh_history"'
  fi
  echo ""
}

main "$@"
