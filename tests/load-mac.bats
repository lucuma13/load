#!/usr/bin/env bats
#
# Tests for load-mac.sh.

setup() {
  DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" >/dev/null 2>&1 && pwd)"
  export BATS_LIB_PATH="$DIR/../node_modules${BATS_LIB_PATH:+:$BATS_LIB_PATH}"
  bats_load_library bats-support
  bats_load_library bats-assert
  LOAD_LIB=1 source "$DIR/../src/load-mac.sh"
  PREFS="$BATS_TEST_TMPDIR/prefs"
  # Discover every captured version; adding a premiere_pro_* fixture dir is enough.
  PREMIERE_VERSIONS=()
  for d in "$DIR"/fixtures/premiere_pro_*/; do
    [ -d "$d" ] && PREMIERE_VERSIONS+=("$(basename "$d")")
  done
  MEDIA_CACHE_DOMAIN="test.load.mediacache"
  defaults delete "$MEDIA_CACHE_DOMAIN" 2>/dev/null || true
}

teardown() {
  defaults delete "$MEDIA_CACHE_DOMAIN" 2>/dev/null || true
}

# Truncation safety: the installer's work is wrapped in main(), invoked on the very
# last line, so bash parses the whole script before running anything - a dropped
# connection can't half-execute it (see the header comment).
@test "main is invoked only on the final line (truncation safety)" {
  run awk 'NF{l=$0} END{print l}' "$DIR/../src/load-mac.sh"
  assert_output 'main "$@"'
}

# The bare (auto) run and --fast execute only run_fast; every privileged step lives
# in run_slow. Guard that run_fast escalates nothing, so the quick pass never blocks
# on a sudo prompt - especially under the unattended auto hand-off. Parses the
# function body from the script text (col-0 '}' closes the function).
@test "run_fast performs no sudo (the fast pass needs no root)" {
  run awk '/^run_fast\(\) \{/{c=1} c{print} c&&/^\}/{exit}' "$DIR/../src/load-mac.sh"
  assert_output --partial 'defaults write com.apple.dock' # guard: body actually captured
  refute_output --partial 'sudo'
}

# Copy the given version's prefs fixture into the per-test temp file.
copy_prefs() { cp "$DIR/fixtures/$1/Adobe Premiere Pro Prefs_truncated" "$PREFS"; }

@test "shortcut set is activated" {
  for v in "${PREMIERE_VERSIONS[@]}"; do
    copy_prefs "$v"
    customise_premiere_pro "$PREFS" "LGG_25.1.kys" "LGG - Single monitor" "$v"
    run cat "$PREFS"
    assert_output --partial '<FE.Prefs.Shortcuts.Filename>LGG_25.1.kys</FE.Prefs.Shortcuts.Filename>'
  done
}

@test "workspace is activated, spaces preserved" {
  for v in "${PREMIERE_VERSIONS[@]}"; do
    copy_prefs "$v"
    customise_premiere_pro "$PREFS" "LGG_25.1.kys" "LGG - Single monitor" "$v"
    run cat "$PREFS"
    assert_output --partial '<FE.Application.LastWorkspaceName>LGG - Single monitor</FE.Application.LastWorkspaceName>'
  done
}

@test "labels switch to Classic (names + colours + marker)" {
  for v in "${PREMIERE_VERSIONS[@]}"; do
    copy_prefs "$v"
    customise_premiere_pro "$PREFS" "x.kys" "WS" "$v"
    run cat "$PREFS"
    assert_output --partial '<BE.Prefs.LabelNames.0>Violet</BE.Prefs.LabelNames.0>'
    assert_output --partial '<BE.Prefs.LabelNames.15>Yellow</BE.Prefs.LabelNames.15>'
    assert_output --partial '<BE.Prefs.LabelColors.0>14717094</BE.Prefs.LabelColors.0>'
    assert_output --partial '<BE.Prefs.LabelColors.15>6611682</BE.Prefs.LabelColors.15>'
    assert_output --partial '"name":"Classic"'
    refute_output --partial 'Vibrant'
  done
}

@test "auto-save enabled every 5 minutes" {
  for v in "${PREMIERE_VERSIONS[@]}"; do
    copy_prefs "$v"
    customise_premiere_pro "$PREFS" "x.kys" "WS" "$v"
    run cat "$PREFS"
    assert_output --partial '<BE.Prefs.AutoSave.DoSave>true</BE.Prefs.AutoSave.DoSave>'
    assert_output --partial '<BE.Prefs.AutoSave.Interval>5</BE.Prefs.AutoSave.Interval>'
  done
}

# Read the timeline nodes straight from the `for tl_node in ...` loop in the script
# (comment lines skipped). Commenting a node in/out there automatically adds/removes
# its check below - no test edit needed.
timeline_nodes() {
  awk '
    /for tl_node in/ { capture=1; next }
    capture {
      done = ($0 ~ /; *do/)
      sub(/;.*$/, "", $0); gsub(/\\/, "", $0); gsub(/^[[:space:]]+|[[:space:]]+$/, "", $0)
      if ($0 != "" && $0 !~ /^#/) print $0
      if (done) capture=0
    }
  ' "$DIR/../src/load-mac.sh"
}

@test "timeline nodes from the script loop are enabled" {
  local nodes
  nodes="$(timeline_nodes)"
  [ -n "$nodes" ] # guard: parsing must find at least one node
  for v in "${PREMIERE_VERSIONS[@]}"; do
    copy_prefs "$v"
    customise_premiere_pro "$PREFS" "x.kys" "WS" "$v"
    run cat "$PREFS"
    assert_output --partial '<TL.PREFLinkedSelectionState>true</TL.PREFLinkedSelectionState>'
    while IFS= read -r node; do
      assert_output --partial "<$node>true</$node>"
    done <<<"$nodes"
  done
}

# The force-written nodes are absent on a fresh install - they must be created but only on
# the whitelisted versions.
@test "force nodes are created when absent on a whitelisted version" {
  for v in "${PREMIERE_VERSIONS[@]}"; do
    copy_prefs "$v"
    # Simulate a fresh install where Premiere has not written these nodes yet.
    sed -i.bak -E '/<(TL\.PREFShowThroughEditsState|MZ\.SQShowDuplicateMarkers)>/d' "$PREFS"
    run customise_premiere_pro "$PREFS" "x.kys" "WS" "$v"
    assert_success
    refute_output --partial 'not found and skipped'
    run cat "$PREFS"
    assert_output --partial '<TL.PREFShowThroughEditsState>true</TL.PREFShowThroughEditsState>'
    assert_output --partial '<MZ.SQShowDuplicateMarkers>true</MZ.SQShowDuplicateMarkers>'
    run xmllint --noout "$PREFS"
    assert_success
  done
}

# On a non-whitelisted version an absent node is reported and skipped, leaving
# the file untouched for it.
@test "force nodes are skipped (not created) on a non-whitelisted version" {
  copy_prefs "${PREMIERE_VERSIONS[0]}"
  sed -i.bak -E '/<(TL\.PREFShowThroughEditsState|MZ\.SQShowDuplicateMarkers)>/d' "$PREFS"
  run customise_premiere_pro "$PREFS" "x.kys" "WS" "0.0"
  assert_success
  assert_output --partial 'not found and skipped'
  assert_output --partial 'TL.PREFShowThroughEditsState'
  assert_output --partial 'MZ.SQShowDuplicateMarkers'
  run cat "$PREFS"
  refute_output --partial 'ShowThroughEditsState'
  refute_output --partial 'SQShowDuplicateMarkers'
}

@test "output prefs is valid XML" {
  for v in "${PREMIERE_VERSIONS[@]}"; do
    copy_prefs "$v"
    customise_premiere_pro "$PREFS" "x.kys" "WS" "$v"
    run xmllint --noout "$PREFS"
    assert_success
  done
}

@test "no BOM is introduced" {
  for v in "${PREMIERE_VERSIONS[@]}"; do
    copy_prefs "$v"
    customise_premiere_pro "$PREFS" "x.kys" "WS" "$v"
    run head -c 3 "$PREFS"
    assert_output '<?x' # would be the UTF-8 BOM bytes if perl had added one
  done
}

@test "idempotent: second run is byte-identical" {
  for v in "${PREMIERE_VERSIONS[@]}"; do
    copy_prefs "$v"
    customise_premiere_pro "$PREFS" "LGG_25.1.kys" "LGG - Single monitor" "$v"
    cp "$PREFS" "$PREFS.first"
    customise_premiere_pro "$PREFS" "LGG_25.1.kys" "LGG - Single monitor" "$v"
    run cmp -s "$PREFS.first" "$PREFS"
    assert_success
  done
}

@test "a renamed node is reported and skipped without corrupting others" {
  for v in "${PREMIERE_VERSIONS[@]}"; do
    copy_prefs "$v"
    # simulate a future Premiere renaming one node
    sed -i.bak 's/TL.PREFLinkedSelectionState/TL.PREFLinkedSelectionStateRENAMED/g' "$PREFS"
    run customise_premiere_pro "$PREFS" "LGG_25.1.kys" "LGG - Single monitor" "$v"
    assert_success
    assert_output --partial 'not found and skipped'
    assert_output --partial 'Adobe may have renamed these nodes'
    assert_output --partial 'TL.PREFLinkedSelectionState'
    run xmllint --noout "$PREFS"
    assert_success
    run cat "$PREFS"
    assert_output --partial '<BE.Prefs.AutoSave.Interval>5</BE.Prefs.AutoSave.Interval>'                     # others still applied
    assert_output --partial '<TL.PREFLinkedSelectionStateRENAMED>false</TL.PREFLinkedSelectionStateRENAMED>' # renamed node untouched
  done
}

# set_pref_node is the engine under customise_premiere_pro. Its "no edit = no
# corruption" contract - a missing node leaves the file byte-for-byte untouched -
# is the safety guarantee the rest of the prefs handling relies on, so exercise it
# directly (mirrors load-win.ps1's Set-PrefNode tests).
@test "set_pref_node replaces a present node's value and succeeds" {
  printf '<root><x>old</x></root>' >"$PREFS"
  run set_pref_node "$PREFS" "x" "new"
  assert_success
  run cat "$PREFS"
  assert_output --partial '<x>new</x>'
}

@test "set_pref_node fails and leaves the file untouched when the node is absent" {
  printf '<root><x>old</x></root>' >"$PREFS"
  cp "$PREFS" "$PREFS.orig"
  run set_pref_node "$PREFS" "missing" "new"
  assert_failure
  run cmp -s "$PREFS.orig" "$PREFS"
  assert_success
}

# The value reaches perl via the SPN_VAL env var precisely so regex/JSON specials
# in it are written literally, not interpreted as substitution metacharacters
# (& = whole match, $1/\1 = capture refs). Guards that escaping contract.
@test "set_pref_node writes a value with regex/JSON specials literally" {
  printf '<root><x>old</x></root>' >"$PREFS"
  local val='R&D $1 \1 {"k":2}'
  run set_pref_node "$PREFS" "x" "$val"
  assert_success
  run cat "$PREFS"
  assert_output --partial "<x>${val}</x>"
}

@test "premiere_workspace_name extracts the UserName" {
  for v in "${PREMIERE_VERSIONS[@]}"; do
    run premiere_workspace_name "$DIR/fixtures/$v/UserWorkspace_truncated.xml"
    assert_output 'LGG - Single monitor'
  done
}

@test "resolve_mode parses flags" {
  run resolve_mode --fast
  assert_output 'fast'
  run resolve_mode --full
  assert_output 'full'
  run resolve_mode --dry-run
  assert_output 'dryrun'
  run resolve_mode
  assert_output ''
  run resolve_mode --full --dry-run
  assert_output 'full dryrun'
  run resolve_mode foo
  assert_output ''
}

@test "premiere_set_media_cache sets FolderPath, preserves DatabasePath" {
  defaults write "$MEDIA_CACHE_DOMAIN" "Media Cache" -dict DatabasePath "/orig/db/" FolderPath "/orig/folder/"
  premiere_set_media_cache "$MEDIA_CACHE_DOMAIN" "/Volumes/SCRATCH_X/Cache" # no trailing slash on input
  run defaults read "$MEDIA_CACHE_DOMAIN" "Media Cache"
  assert_output --partial 'FolderPath = "/Volumes/SCRATCH_X/Cache/"'
  assert_output --partial 'DatabasePath = "/orig/db/"'
  # cleanup handled by teardown
}

# These hit the network to confirm the hard-coded plugin installer URLs are still
# live. Skip them on an offline run with:  bats --filter-tags '!live' tests/
#
# HEAD first, falling back to a 1-byte ranged GET for servers that reject HEAD;
# redirects are followed and 200/206 are both accepted.
link_status() {
  local url="$1" code
  code="$(curl -sS -o /dev/null -w '%{http_code}' -I -L --max-time 30 "$url")"
  if [ "$code" != 200 ] && [ "$code" != 206 ]; then
    code="$(curl -sS -o /dev/null -w '%{http_code}' -H 'Range: bytes=0-0' -L --max-time 30 "$url")"
  fi
  printf '%s' "$code"
}

# bats test_tags=live
@test "plugin download links are live" {
  run link_status "https://misterhorse.com/downloads/product-manager/osx"
  assert_output --regexp '^(200|206)$' # Mister Horse Product Manager
  run link_status "https://www.digitalanarchy.com/downloads/flickerfree_229_AE.dmg"
  assert_output --regexp '^(200|206)$' # Flicker Free
}

# Confirm every pinned formula/cask still resolves - catches an upstream
# rename/delisting or a local typo before it silently no-ops an install. Uses the
# package lists sourced from load-mac.sh, so the assertion can't drift from what
# the installer actually requests. Hits the network (tagged live); skipped when
# Homebrew is absent.
# bats test_tags=live
@test "all brew formulae resolve (rename/delisting/typo guard)" {
  command -v brew >/dev/null || skip "Homebrew not installed"
  local bad=()
  for f in $CORE_FORMULAE $FULL_FORMULAE; do
    brew info --formula "$f" &>/dev/null || bad+=("$f")
  done
  [ ${#bad[@]} -eq 0 ] || fail "unknown formulae: ${bad[*]}"
}

# bats test_tags=live
@test "all brew casks resolve (rename/delisting/typo guard)" {
  command -v brew >/dev/null || skip "Homebrew not installed"
  local bad=()
  for c in $CORE_CASKS $FULL_CASKS; do
    brew info --cask "$c" &>/dev/null || bad+=("$c")
  done
  [ ${#bad[@]} -eq 0 ] || fail "unknown casks: ${bad[*]}"
}

# The uv tools install from PyPI, so existence is a PyPI lookup (200 = project
# exists, 404 = renamed/delisted/mistyped). Same list the installer uses.
# bats test_tags=live
@test "all uv tools resolve on PyPI (rename/delisting/typo guard)" {
  local bad=()
  for p in $CORE_UV; do
    [ "$(link_status "https://pypi.org/pypi/$p/json")" = 200 ] || bad+=("$p")
  done
  [ ${#bad[@]} -eq 0 ] || fail "unknown PyPI packages: ${bad[*]}"
}
