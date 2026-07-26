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
@test "the bare command runs all three cleanup phases" {
  run env HOME="$BATS_TEST_TMPDIR/home" bash "$DIR/../src/unload-mac.sh" --dry-run
  assert_success
  assert_output --partial "Work directory"
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
