#!/usr/bin/env bats
#
# Tests for unload-mac.sh.
#
setup() {
  DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" >/dev/null 2>&1 && pwd)"
  export BATS_LIB_PATH="$DIR/../node_modules${BATS_LIB_PATH:+:$BATS_LIB_PATH}"
  bats_load_library bats-support
  bats_load_library bats-assert
  LOAD_LIB=1 source "$DIR/../src/unload-mac.sh"
  # Every path-touching test works inside a throwaway home, so a bug in rm_path
  # destroys a temp dir rather than the machine running the suite.
  HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME"
  DRY_RUN=false
}

# Truncation safety: the work is wrapped in main(), invoked on the very last line,
# so bash parses the whole script before running anything - a dropped connection
# can't half-execute it. Doubly important here, where "half" means "deleted some
# things and stopped".
@test "main is invoked only on the final line (truncation safety)" {
  run awk 'NF{l=$0} END{print l}' "$DIR/../src/unload-mac.sh"
  assert_output 'main "$@"'
}

# Every recursive delete must go through rm_path, which is where the under_home
# guard lives. A second `rm -rf` anywhere else in the script would bypass it, so
# assert there is exactly one executable occurrence (comments discuss it too, and
# are filtered out) and that it sits in rm_path's body.
@test "rm -rf appears only inside rm_path" {
  run awk '!/^[[:space:]]*#/ && /rm -rf/' "$DIR/../src/unload-mac.sh"
  assert_output '  rm -rf "$p" && removing "Removed $(tilde "$p")"'
  run awk '/^rm_path\(\) \{/{c=1} c{print} c&&/^\}/{exit}' "$DIR/../src/unload-mac.sh"
  assert_output --partial 'rm -rf "$p"'
}

# -----------------------------------------------------------------------------
# check_args
#
# There are no target flags: the bare command is the whole interface. That makes
# argument validation the safety property worth testing - a typo'd "--dryrun" that
# fell through to "no options given" would delete for real at exactly the moment
# the caller was asking for a preview.
# -----------------------------------------------------------------------------

@test "check_args accepts the bare command and its only options" {
  run check_args
  assert_success
  run check_args --dry-run
  assert_success
  run check_args --help
  assert_success
  run check_args -h
  assert_success
}

@test "check_args rejects a misspelt --dry-run" {
  run check_args --dryrun
  assert_failure
  run check_args --dry_run
  assert_failure
}

@test "check_args rejects the target flags that used to exist" {
  run check_args --workdir
  assert_failure
  run check_args --claude
  assert_failure
  run check_args --all
  assert_failure
}

@test "check_args rejects an unknown argument alongside a valid one" {
  run check_args --dry-run --nope
  assert_failure
}

@test "the script exits non-zero on an unrecognised argument without removing anything" {
  run bash "$DIR/../src/unload-mac.sh" --dryrun
  assert_failure
  assert_output --partial "Unrecognised argument. Nothing was removed."
}

# The bare command must reach every phase - that is the whole interface now.
# The throwaway HOME holds no Premiere profile, so the workspace phase returns
# before it would go to the network: this stays an offline test.
@test "the bare command runs all six cleanup phases" {
  run env HOME="$BATS_TEST_TMPDIR/home" bash "$DIR/../src/unload-mac.sh" --dry-run
  assert_success
  assert_output --partial "Google Chrome"
  assert_output --partial "Work directory"
  assert_output --partial "Premiere Pro workspaces"
  assert_output --partial "Mister Horse"
  assert_output --partial "Claude Code"
  assert_output --partial "Shell history"
}

# -----------------------------------------------------------------------------
# under_home - the guard on every delete
# -----------------------------------------------------------------------------

@test "under_home accepts paths strictly inside \$HOME" {
  run under_home "$HOME/Downloads/load-mac"
  assert_success
  run under_home "$HOME/.claude"
  assert_success
}

# An empty or unexpanded variable is the failure mode that turns `rm -rf "$p"`
# into a catastrophe, so it is the case that matters most.
@test "under_home rejects empty, root and \$HOME itself" {
  run under_home ""
  assert_failure
  run under_home "/"
  assert_failure
  run under_home "$HOME"
  assert_failure
  run under_home "$HOME/"
  assert_failure
}

@test "under_home rejects paths outside \$HOME" {
  run under_home "/etc/passwd"
  assert_failure
  run under_home "/Applications"
  assert_failure
  run under_home "relative/path"
  assert_failure
}

# ".." would let an in-$HOME-looking path resolve anywhere on the disk.
@test "under_home rejects parent-directory traversal" {
  run under_home "$HOME/../../etc"
  assert_failure
}

# -----------------------------------------------------------------------------
# rm_path
# -----------------------------------------------------------------------------

@test "rm_path removes a file and reports it" {
  touch "$HOME/victim"
  run rm_path "$HOME/victim"
  assert_success
  assert_output --partial "Removed ~/victim"
  [ ! -e "$HOME/victim" ]
}

@test "rm_path removes a directory tree" {
  mkdir -p "$HOME/tree/nested"
  touch "$HOME/tree/nested/file"
  run rm_path "$HOME/tree"
  assert_success
  [ ! -e "$HOME/tree" ]
}

@test "rm_path removes a dangling symlink" {
  ln -s "$HOME/does-not-exist" "$HOME/link"
  run rm_path "$HOME/link"
  assert_success
  [ ! -L "$HOME/link" ]
}

# "Already clean" has to be distinguishable from "cleaned", so callers can print
# a single "nothing to remove" instead of a line per absent path.
@test "rm_path is silent and fails when the path is absent" {
  run rm_path "$HOME/never-existed"
  assert_failure
  assert_output ""
}

@test "rm_path refuses a path outside \$HOME and leaves it alone" {
  local outside="$BATS_TEST_TMPDIR/outside"
  touch "$outside"
  run rm_path "$outside"
  assert_failure
  assert_output --partial "Refusing to remove"
  [ -e "$outside" ]
}

@test "rm_path under --dry-run reports but deletes nothing" {
  touch "$HOME/survivor"
  DRY_RUN=true
  run rm_path "$HOME/survivor"
  assert_success
  assert_output --partial "Would remove ~/survivor"
  [ -e "$HOME/survivor" ]
}

@test "tilde shortens \$HOME and leaves other paths alone" {
  run tilde "$HOME/Downloads/load-mac"
  assert_output "~/Downloads/load-mac"
  run tilde "/etc/hosts"
  assert_output "/etc/hosts"
}

# -----------------------------------------------------------------------------
# Target path lists
# -----------------------------------------------------------------------------

# ~/.claude is the whole point of the Claude target on a machine you're leaving:
# it holds transcripts, per-project history and memory, not just config.
@test "claude_state_paths covers the CLI's state" {
  run claude_state_paths
  assert_line "$HOME/.claude"
  assert_line "$HOME/.claude.json"
  assert_line "$HOME/.claude.json.backup"
  assert_line "$HOME/Library/Caches/claude-cli-nodejs"
}

# The Claude desktop app is a separate product that may well belong to someone
# else on a shared machine. Only the CLI's own state is in scope, so this path
# must never creep into the list.
@test "claude_state_paths leaves the Claude desktop app alone" {
  run claude_state_paths
  refute_output --partial "Application Support/Claude"
}

@test "claude_state_paths stays inside \$HOME" {
  run claude_state_paths
  for path in "${lines[@]}"; do
    under_home "$path" || fail "claude_state_paths yielded '$path', outside \$HOME"
  done
}

# -----------------------------------------------------------------------------
# Google Chrome
# -----------------------------------------------------------------------------

# A stand-in for `ps -xo pid=,comm=`: chrome_pids calls `ps`, and a shell
# function of that name takes precedence over the real one, so the parsing can
# be exercised against a fixed process list.
fake_ps() {
  ps() {
    echo "  501 /Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
    echo "  502 /Applications/Google Chrome.app/Contents/Frameworks/Google Chrome Framework.framework/Versions/140/Helpers/Google Chrome Helper (Renderer).app/Contents/MacOS/Google Chrome Helper (Renderer)"
    echo "  503 /Applications/Safari.app/Contents/MacOS/Safari"
    echo "  504 /Users/someone/Google Chrome notes/watcher"
  }
}

# The helpers are separately named processes ("Google Chrome Helper (Renderer)"
# and friends) but they all run out of the app bundle, so the bundle is what the
# match is on - and they have to be found, or the wait for Chrome to exit would
# return while its children were still up.
@test "chrome_pids finds the browser and its helpers" {
  fake_ps
  run chrome_pids
  assert_success
  assert_line "501"
  assert_line "502"
}

# Matching "Google Chrome" loosely anywhere in the path would sweep up whatever
# else happens to carry the name - and every pid this yields is about to be sent
# a kill.
@test "chrome_pids ignores other browsers and paths that merely read like Chrome" {
  fake_ps
  run chrome_pids
  refute_line "503"
  refute_line "504"
}

# Quitting another user's browser is not this script's business: -x without -a is
# this account's processes only.
@test "chrome_pids looks only at this account's processes" {
  run awk '/^chrome_pids\(\) \{/{c=1} c{print} c&&/^\}/{exit}' "$DIR/../src/unload-mac.sh"
  refute_output --partial "ps -ax"
}

# A kill -9 costs the session: Chrome reopens with the "didn't shut down
# correctly" bar and a half-written profile. The AppleScript quit is ⌘Q, which
# saves the tabs - so it has to come first, with the kill only as the timeout.
@test "quit_chrome asks Chrome to quit before it forces anything" {
  local body quit force
  body="$(awk '/^quit_chrome\(\) \{/{c=1} c{print} c&&/^\}/{exit}' "$DIR/../src/unload-mac.sh")"
  quit="$(echo "$body" | grep -n 'osascript' | head -1 | cut -d: -f1)"
  force="$(echo "$body" | grep -n 'kill -9' | head -1 | cut -d: -f1)"
  [ -n "$quit" ] || fail "quit_chrome never asks Chrome to quit"
  [ -n "$force" ] || fail "quit_chrome has no fallback for a Chrome that won't close"
  [ "$quit" -lt "$force" ] || fail "quit_chrome forces the kill before asking"
}

# The wait has to be bounded. A "Leave site?" dialog can hold a quit up for as
# long as nobody clicks it, and an unload that hangs behind it is worse than a
# lost tab.
@test "quit_chrome does not wait forever for Chrome to close" {
  run awk '/^quit_chrome\(\) \{/{c=1} c{print} c&&/^\}/{exit}' "$DIR/../src/unload-mac.sh"
  assert_output --partial "waited"
  refute_output --partial "while true"
}

# This phase is a quit and nothing more: Chrome stays installed, and the profile
# is left exactly as it is.
@test "clean_chrome removes nothing and uninstalls nothing" {
  run awk '/^clean_chrome\(\) \{/{c=1} c{print} c&&/^\}/{exit}' "$DIR/../src/unload-mac.sh"
  assert_success
  refute_output --partial "rm_path"
  refute_output --partial "brew"
  refute_output --partial "Application Support/Google"
}

# A dry run must not close the browser any more than it deletes a file, so the
# --dry-run branch has to report and return ahead of both the quit and the kill.
# quit_chrome lives below the library guard (it reads $DRY_RUN), so this is
# asserted against the source text, as the Mister Horse ordering test is.
@test "quit_chrome under --dry-run returns before it touches Chrome" {
  local body dry act
  body="$(awk '/^quit_chrome\(\) \{/{c=1} c{print} c&&/^\}/{exit}' "$DIR/../src/unload-mac.sh")"
  echo "$body" | grep -q 'Would quit Google Chrome' || fail "quit_chrome has no --dry-run message"
  dry="$(echo "$body" | grep -n 'if \$DRY_RUN' | head -1 | cut -d: -f1)"
  act="$(echo "$body" | grep -n 'osascript\|kill -9' | head -1 | cut -d: -f1)"
  [ -n "$dry" ] || fail "quit_chrome does not check DRY_RUN"
  [ "$dry" -lt "$act" ] || fail "quit_chrome acts on Chrome before checking DRY_RUN"
}

# -----------------------------------------------------------------------------
# Mister Horse sign-out
#
# This is a sign-out, not an uninstall: the plugins are the machine's now, the way
# VLC and FFmpeg are, but the account signed into them is the departing user's.
# The session lives in the app's own encrypted files rather than in the keychain,
# so removing them IS the sign-out - which makes the contents of that path list,
# and the order the phase does things in, the properties worth pinning.
# -----------------------------------------------------------------------------

# ~/Library/Application Support/MisterHorse holds the Product Manager's session
# (ProductManager/as.dat) alongside each panel's cached copy of it, so one removal
# signs out the lot.
@test "misterhorse_state_paths covers the per-user state dir" {
  run misterhorse_state_paths
  assert_line "$HOME/Library/Application Support/MisterHorse"
}

# The Product Manager signs in through a web view, so its cookies and its mirrored
# account state sit under the vendor's bundle ids. Globbed rather than named one
# at a time: each panel gets its own id and the set varies by install.
@test "misterhorse_state_paths covers the web session and the cached account state" {
  mkdir -p "$HOME/Library/HTTPStorages/com.misterhorse.ProductManager"
  mkdir -p "$HOME/Library/Caches/com.misterhorse.ProductManager"
  mkdir -p "$HOME/Library/Caches/com.misterhorse.PremiereComposer2"
  run misterhorse_state_paths
  assert_line "$HOME/Library/HTTPStorages/com.misterhorse.ProductManager"
  assert_line "$HOME/Library/Caches/com.misterhorse.ProductManager"
  assert_line "$HOME/Library/Caches/com.misterhorse.PremiereComposer2"
}

# An unmatched glob must not reach the list as its own literal pattern: rm_path
# would only refuse it, but --dry-run would print "com.misterhorse.*" and read
# like a bug.
@test "misterhorse_state_paths yields no unmatched glob" {
  run misterhorse_state_paths
  refute_output --partial "*"
}

@test "misterhorse_state_paths stays inside \$HOME" {
  mkdir -p "$HOME/Library/Caches/com.misterhorse.ProductManager"
  run misterhorse_state_paths
  for path in "${lines[@]}"; do
    under_home "$path" || fail "misterhorse_state_paths yielded '$path', outside \$HOME"
  done
}

# The sign-out must not turn into an uninstall: the Product Manager lives in
# /Applications and the plugins in the shared Adobe plug-in tree. Both are
# machine-wide, so under_home would refuse them anyway - but they must not be
# offered to it in the first place.
@test "misterhorse_state_paths removes no installed plugin" {
  run misterhorse_state_paths
  refute_output --partial "/Applications"
  refute_output --partial "/Library/Application Support/Adobe"
}

# The ordering is the mechanism: a running Product Manager holds the session in
# memory and writes its state back as it closes, so files deleted underneath it
# come straight back and the account is still signed in.
@test "clean_misterhorse quits the Product Manager before removing its state" {
  local body quit rm
  body="$(awk '/^clean_misterhorse\(\) \{/{c=1} c{print} c&&/^\}/{exit}' "$DIR/../src/unload-mac.sh")"
  quit="$(echo "$body" | grep -n "quit_misterhorse" | head -1 | cut -d: -f1)"
  rm="$(echo "$body" | grep -n "rm_path" | head -1 | cut -d: -f1)"
  [ -n "$quit" ] || fail "clean_misterhorse never quits the Product Manager"
  [ -n "$rm" ] || fail "clean_misterhorse removes nothing"
  [ "$quit" -lt "$rm" ] || fail "clean_misterhorse removes state before quitting the app"
}

# "ProductManager" is a generic enough name to belong to another vendor entirely,
# so the process match is on the executable path, which is what `comm` prints.
@test "misterhorse_pids matches the app by executable path, not by process name" {
  run awk '/^misterhorse_pids\(\) \{/{c=1} c{print} c&&/^\}/{exit}' "$DIR/../src/unload-mac.sh"
  assert_output --partial "comm="
}

# Quitting another user's app is not this script's business: -x without -a is this
# account's processes only.
@test "misterhorse_pids looks only at this account's processes" {
  run awk '/^misterhorse_pids\(\) \{/{c=1} c{print} c&&/^\}/{exit}' "$DIR/../src/unload-mac.sh"
  refute_output --partial "ps -ax"
}

# ~/.zsh_sessions is history too: Terminal's "reopen windows" restores each
# session's commands from the .historynew files in there, so wiping
# ~/.zsh_history alone would leave them recoverable.
@test "history_paths covers zsh, its saved sessions, and bash" {
  run history_paths
  assert_line "$HOME/.zsh_history"
  assert_line "$HOME/.zsh_sessions"
  assert_line "$HOME/.bash_history"
}

# $HISTFILE and $ZDOTDIR normally resolve to paths already in the list. A real run
# wouldn't care - rm_path is silent the second time - but --dry-run would print
# the same path twice and read like a bug.
@test "history_paths deduplicates when HISTFILE points at a listed path" {
  HISTFILE="$HOME/.zsh_history"
  run history_paths
  local seen=0
  for line in "${lines[@]}"; do
    [ "$line" = "$HOME/.zsh_history" ] && seen=$((seen + 1))
  done
  [ "$seen" -eq 1 ] || fail "~/.zsh_history listed $seen times, expected once"
}

@test "history_paths honours a custom HISTFILE" {
  HISTFILE="$HOME/.config/zsh/my_history"
  run history_paths
  assert_line "$HOME/.config/zsh/my_history"
}

@test "history_paths honours ZDOTDIR" {
  ZDOTDIR="$HOME/.config/zsh"
  run history_paths
  assert_line "$HOME/.config/zsh/.zsh_history"
}

# -----------------------------------------------------------------------------
# Premiere Pro workspaces
# -----------------------------------------------------------------------------

# A GitHub contents listing for src/data, trimmed to the fields the parser reads
# and shaped like the real thing: compact JSON, one object per entry, each
# repeating its filename in "path" and "download_url" as well as "name".
contents_listing() {
  printf '[{"name":"LGG_25.1.kys","path":"src/data/LGG_25.1.kys","type":"file",'
  printf '"download_url":"https://raw.githubusercontent.com/lucuma13/load/main/src/data/LGG_25.1.kys"},'
  printf '{"name":"UserWorkspace_LGG_1.xml","path":"src/data/UserWorkspace_LGG_1.xml","type":"file",'
  printf '"download_url":"https://raw.githubusercontent.com/lucuma13/load/main/src/data/UserWorkspace_LGG_1.xml"},'
  printf '{"name":"UserWorkspace_LGG_2.xml","path":"src/data/UserWorkspace_LGG_2.xml","type":"file",'
  printf '"download_url":"https://raw.githubusercontent.com/lucuma13/load/main/src/data/UserWorkspace_LGG_2.xml"},'
  printf '{"name":"UserWorkspace_Colour.xml","path":"src/data/UserWorkspace_Colour.xml","type":"file",'
  printf '"download_url":"https://raw.githubusercontent.com/lucuma13/load/main/src/data/UserWorkspace_Colour.xml"},'
  printf '{"name":"LUTs","path":"src/data/LUTs","type":"dir","download_url":null}]\n'
}

# The match is on UserWorkspace_*.xml: a workspace added to src/data under any
# name is one load drops, so unload has to take it back out without being edited
# first.
@test "parse_workspace_names picks the workspaces out of a contents listing" {
  run bash -c "$(declare -f contents_listing parse_workspace_names); contents_listing | parse_workspace_names"
  assert_success
  assert_line "UserWorkspace_LGG_1.xml"
  assert_line "UserWorkspace_LGG_2.xml"
  assert_line "UserWorkspace_Colour.xml"
}

# Each entry names its file three times (name, path, download_url). Matching the
# filename loosely anywhere in the JSON would yield every workspace three times,
# and --dry-run would print each removal three times over.
@test "parse_workspace_names yields each workspace exactly once" {
  run bash -c "$(declare -f contents_listing parse_workspace_names); contents_listing | parse_workspace_names"
  assert_equal "${#lines[@]}" 3
}

# Nothing but a UserWorkspace_*.xml may come out of the parser.
@test "parse_workspace_names ignores the other files in src/data" {
  run bash -c "$(declare -f contents_listing parse_workspace_names); contents_listing | parse_workspace_names"
  refute_output --partial "LGG_25.1.kys"
  refute_output --partial "LUTs"
}

@test "parse_workspace_names yields nothing for an unreadable listing" {
  run bash -c "$(declare -f parse_workspace_names); printf '%s' '{\"message\":\"API rate limit exceeded\"}' | parse_workspace_names"
  assert_output ""
}

# Premiere keeps one profile per version, so a machine that has been through an
# upgrade has several - each with its own copy of the workspaces to remove.
@test "premiere_layout_dirs finds the Layouts folder of every profile" {
  local root="$HOME/Documents/Adobe/Premiere Pro"
  mkdir -p "$root/25.1/Profile-lgg/Layouts" "$root/24.0/Profile-lgg/Layouts"
  run premiere_layout_dirs
  assert_success
  assert_line "$root/25.1/Profile-lgg/Layouts"
  assert_line "$root/24.0/Profile-lgg/Layouts"
}

# A profile Premiere has never written a Layouts folder into contributes nothing
# - and an unexpanded glob must not be echoed as if it were a path.
@test "premiere_layout_dirs is silent when there is no Premiere profile" {
  run premiere_layout_dirs
  assert_success
  assert_output ""
}

@test "premiere_layout_dirs yields only paths the delete guard will accept" {
  mkdir -p "$HOME/Documents/Adobe/Premiere Pro/25.1/Profile-lgg/Layouts"
  run premiere_layout_dirs
  for path in "${lines[@]}"; do
    under_home "$path" || fail "premiere_layout_dirs yielded '$path', outside \$HOME"
  done
}

# local_workspace_names — the same UserWorkspace_*.xml match, applied to the
# checkout's own src/data instead of the published listing.
local_workspace_names() {
  local f
  for f in "$DIR"/../src/data/UserWorkspace_*.xml; do
    [ -e "$f" ] && basename "$f"
  done
  return 0
}

# resolved_workspace_names — the workspace filenames unload would act on,
# preferring the published listing and falling back to the checkout when the
# fetch comes back empty (no network, or GitHub rate-limiting the
# unauthenticated request).
resolved_workspace_names() {
  local names
  names="$(workspace_names || true)"
  [ -n "$names" ] || names="$(local_workspace_names)"
  echo "$names"
}

# The contract that matters: unload must remove exactly the workspaces load
# drops. Both sides read the same src/data listing, so this asserts the listing
# still carries the filenames load-mac.sh delivers - a rename in the repo that
# reached only one of the two scripts shows up here.
@test "the src/data listing carries the workspaces load-mac drops" {
  local names dropped ws
  names="$(resolved_workspace_names)"
  [ -n "$names" ] || fail "no listing from GitHub and no UserWorkspace_*.xml in src/data"
  # Read from the source text rather than by sourcing it: load-mac.sh sets
  # WS_FILE_* below its own library guard, so LOAD_LIB=1 never reaches them.
  dropped="$(grep -o '^WS_FILE_[0-9]*="[^"]*"' "$DIR/../src/load-mac.sh" | sed 's/.*="//;s/"$//')"
  [ -n "$dropped" ] || fail "no WS_FILE_* assignments found in load-mac.sh"
  while IFS= read -r ws; do
    grep -qx "$ws" <<<"$names" || fail "load-mac drops '$ws', which is not in src/data"
  done <<<"$dropped"
}

# The fallback is only worth having if it holds the same filenames the published
# listing does, so point the fetch at a dead URL and confirm the checkout answers
# with the workspaces load-mac drops.
@test "the workspace list falls back to the checkout when the fetch fails" {
  local names dropped ws
  WS_API="https://127.0.0.1:9/no-such-listing"
  names="$(resolved_workspace_names)"
  dropped="$(grep -o '^WS_FILE_[0-9]*="[^"]*"' "$DIR/../src/load-mac.sh" | sed 's/.*="//;s/"$//')"
  while IFS= read -r ws; do
    grep -qx "$ws" <<<"$names" || fail "the offline fallback did not yield '$ws'"
  done <<<"$dropped"
}

# -----------------------------------------------------------------------------
# Claude casks
# -----------------------------------------------------------------------------

# Homebrew ships both an auto-updating "claude-code@latest" and a pinned
# "claude-code"; a machine can carry either, or both after switching. Whatever is
# installed here, the function must only ever name those two - the result is fed
# straight to `brew uninstall`.
@test "claude_casks_installed names only known Claude casks" {
  run claude_casks_installed
  assert_success
  for line in "${lines[@]}"; do
    case "$line" in
    claude-code | claude-code@latest) ;;
    *) fail "claude_casks_installed yielded an unexpected cask: '$line'" ;;
    esac
  done
}
