#!/usr/bin/env bats
#
# Tests for the Premiere prefs editing and mode parsing in src/load-mac.sh.
# The script is sourced with LOAD_LIB=1 so only its functions load (no installer).
#
# The prefs format is Premiere-version-dependent (not platform-dependent), so the
# prefs tests run against every captured version in PREMIERE_VERSIONS.

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
}

# Copy the given version's prefs fixture into the per-test temp file.
copy_prefs() { cp "$DIR/fixtures/$1/Adobe Premiere Pro Prefs_truncated" "$PREFS"; }

@test "shortcut set is activated" {
  for v in "${PREMIERE_VERSIONS[@]}"; do
    copy_prefs "$v"
    premiere_apply_prefs "$PREFS" "LGG_25.1.kys" "LGG - Single monitor"
    run cat "$PREFS"
    assert_output --partial '<FE.Prefs.Shortcuts.Filename>LGG_25.1.kys</FE.Prefs.Shortcuts.Filename>'
  done
}

@test "workspace is activated, spaces preserved" {
  for v in "${PREMIERE_VERSIONS[@]}"; do
    copy_prefs "$v"
    premiere_apply_prefs "$PREFS" "LGG_25.1.kys" "LGG - Single monitor"
    run cat "$PREFS"
    assert_output --partial '<FE.Application.LastWorkspaceName>LGG - Single monitor</FE.Application.LastWorkspaceName>'
  done
}

@test "labels switch to Classic (names + colours + marker)" {
  for v in "${PREMIERE_VERSIONS[@]}"; do
    copy_prefs "$v"
    premiere_apply_prefs "$PREFS" "x.kys" "WS"
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
    premiere_apply_prefs "$PREFS" "x.kys" "WS"
    run cat "$PREFS"
    assert_output --partial '<BE.Prefs.AutoSave.DoSave>true</BE.Prefs.AutoSave.DoSave>'
    assert_output --partial '<BE.Prefs.AutoSave.Interval>5</BE.Prefs.AutoSave.Interval>'
  done
}

@test "timeline Link Selection is enabled" {
  for v in "${PREMIERE_VERSIONS[@]}"; do
    copy_prefs "$v"
    premiere_apply_prefs "$PREFS" "x.kys" "WS"
    run cat "$PREFS"
    assert_output --partial '<TL.PREFLinkedSelectionState>true</TL.PREFLinkedSelectionState>'
  done
}

@test "timeline display settings all enabled" {
  for v in "${PREMIERE_VERSIONS[@]}"; do
    copy_prefs "$v"
    premiere_apply_prefs "$PREFS" "x.kys" "WS"
    run cat "$PREFS"
    assert_output --partial '<be.Prefs.Timeline.Show.Video.Thumbnails>true</be.Prefs.Timeline.Show.Video.Thumbnails>'
    assert_output --partial '<be.Prefs.Timeline.Show.Video.Names>true</be.Prefs.Timeline.Show.Video.Names>'
    assert_output --partial '<be.Prefs.Timeline.Show.Audio.Waveforms>true</be.Prefs.Timeline.Show.Audio.Waveforms>'
    assert_output --partial '<be.Prefs.Timeline.Show.Audio.Names>true</be.Prefs.Timeline.Show.Audio.Names>'
    assert_output --partial '<be.Prefs.Timeline.Show.Proxy.Badges>true</be.Prefs.Timeline.Show.Proxy.Badges>'
    assert_output --partial '<TL.PREFShowFXBadges>true</TL.PREFShowFXBadges>'
    assert_output --partial '<TL.PREFShowThroughEditsState>true</TL.PREFShowThroughEditsState>'
    assert_output --partial '<MZ.SQShowDuplicateMarkers>true</MZ.SQShowDuplicateMarkers>'
  done
}

@test "output prefs is valid XML" {
  for v in "${PREMIERE_VERSIONS[@]}"; do
    copy_prefs "$v"
    premiere_apply_prefs "$PREFS" "x.kys" "WS"
    run xmllint --noout "$PREFS"
    assert_success
  done
}

@test "no BOM is introduced" {
  for v in "${PREMIERE_VERSIONS[@]}"; do
    copy_prefs "$v"
    premiere_apply_prefs "$PREFS" "x.kys" "WS"
    run head -c 3 "$PREFS"
    assert_output '<?x'   # would be the UTF-8 BOM bytes if perl had added one
  done
}

@test "idempotent: second run is byte-identical" {
  for v in "${PREMIERE_VERSIONS[@]}"; do
    copy_prefs "$v"
    premiere_apply_prefs "$PREFS" "LGG_25.1.kys" "LGG - Single monitor"
    cp "$PREFS" "$PREFS.first"
    premiere_apply_prefs "$PREFS" "LGG_25.1.kys" "LGG - Single monitor"
    run cmp -s "$PREFS.first" "$PREFS"
    assert_success
  done
}

@test "a renamed node is reported and skipped without corrupting others" {
  for v in "${PREMIERE_VERSIONS[@]}"; do
    copy_prefs "$v"
    # simulate a future Premiere renaming one node
    sed -i.bak 's/TL.PREFShowFXBadges/TL.PREFShowFXBadgesRENAMED/g' "$PREFS"
    run premiere_apply_prefs "$PREFS" "LGG_25.1.kys" "LGG - Single monitor"
    assert_success
    assert_output --partial 'needs revising'
    assert_output --partial 'TL.PREFShowFXBadges'
    run xmllint --noout "$PREFS"
    assert_success
    run cat "$PREFS"
    assert_output --partial '<BE.Prefs.AutoSave.Interval>5</BE.Prefs.AutoSave.Interval>'           # others still applied
    assert_output --partial '<TL.PREFShowFXBadgesRENAMED>false</TL.PREFShowFXBadgesRENAMED>'        # renamed node untouched
  done
}

@test "premiere_workspace_name extracts the UserName" {
  for v in "${PREMIERE_VERSIONS[@]}"; do
    run premiere_workspace_name "$DIR/fixtures/$v/UserWorkspace_truncated.xml"
    assert_output 'LGG - Single monitor'
  done
}

@test "resolve_mode parses flags" {
  run resolve_mode --fast;           assert_output 'fast'
  run resolve_mode --full;           assert_output 'full'
  run resolve_mode --dry-run;        assert_output 'dryrun'
  run resolve_mode;                  assert_output ''
  run resolve_mode --full --dry-run; assert_output 'full dryrun'
  run resolve_mode foo;              assert_output ''
}

@test "premiere_set_media_cache sets FolderPath, preserves DatabasePath" {
  D="test.load.$$.mediacache"
  defaults write "$D" "Media Cache" -dict DatabasePath "/orig/db/" FolderPath "/orig/folder/"
  premiere_set_media_cache "$D" "/Volumes/SCRATCH_X/Cache"   # no trailing slash on input
  run defaults read "$D" "Media Cache"
  assert_output --partial 'FolderPath = "/Volumes/SCRATCH_X/Cache/"'
  assert_output --partial 'DatabasePath = "/orig/db/"'
  defaults delete "$D"
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
@test "Mister Horse Product Manager (macOS) link is live" {
  run link_status "https://misterhorse.com/downloads/product-manager/osx"
  assert_output --regexp '^(200|206)$'
}

# bats test_tags=live
@test "Flicker Free (macOS) link is live" {
  run link_status "https://www.digitalanarchy.com/downloads/flickerfree_229_AE.dmg"
  assert_output --regexp '^(200|206)$'
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
