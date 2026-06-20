#!/usr/bin/env bats
#
# Tests for the Premiere prefs editing and mode parsing in src/load-mac.sh.
# The script is sourced with LOAD_LIB=1 so only its functions load (no installer).

setup() {
  DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" >/dev/null 2>&1 && pwd)"
  load "$DIR/lib/bats-support/load"
  load "$DIR/lib/bats-assert/load"
  LOAD_LIB=1 source "$DIR/../src/load-mac.sh"
  PREFS="$BATS_TEST_TMPDIR/prefs"
}

@test "shortcut set is activated" {
  cp "$DIR/fixtures/premiere_pro_v26.2.2/Adobe Premiere Pro Prefs_truncated" "$PREFS"
  premiere_apply_prefs "$PREFS" "Luis_Mengo_25.1.kys" "LM - Single monitor"
  run cat "$PREFS"
  assert_output --partial '<FE.Prefs.Shortcuts.Filename>Luis_Mengo_25.1.kys</FE.Prefs.Shortcuts.Filename>'
}

@test "workspace is activated, spaces preserved" {
  cp "$DIR/fixtures/premiere_pro_v26.2.2/Adobe Premiere Pro Prefs_truncated" "$PREFS"
  premiere_apply_prefs "$PREFS" "Luis_Mengo_25.1.kys" "LM - Single monitor"
  run cat "$PREFS"
  assert_output --partial '<FE.Application.LastWorkspaceName>LM - Single monitor</FE.Application.LastWorkspaceName>'
}

@test "labels switch to Classic (names + colours + marker)" {
  cp "$DIR/fixtures/premiere_pro_v26.2.2/Adobe Premiere Pro Prefs_truncated" "$PREFS"
  premiere_apply_prefs "$PREFS" "x.kys" "WS"
  run cat "$PREFS"
  assert_output --partial '<BE.Prefs.LabelNames.0>Violet</BE.Prefs.LabelNames.0>'
  assert_output --partial '<BE.Prefs.LabelNames.15>Yellow</BE.Prefs.LabelNames.15>'
  assert_output --partial '<BE.Prefs.LabelColors.0>14717094</BE.Prefs.LabelColors.0>'
  assert_output --partial '<BE.Prefs.LabelColors.15>6611682</BE.Prefs.LabelColors.15>'
  assert_output --partial '"name":"Classic"'
  refute_output --partial 'Vibrant'
}

@test "auto-save enabled every 5 minutes" {
  cp "$DIR/fixtures/premiere_pro_v26.2.2/Adobe Premiere Pro Prefs_truncated" "$PREFS"
  premiere_apply_prefs "$PREFS" "x.kys" "WS"
  run cat "$PREFS"
  assert_output --partial '<BE.Prefs.AutoSave.DoSave>true</BE.Prefs.AutoSave.DoSave>'
  assert_output --partial '<BE.Prefs.AutoSave.Interval>5</BE.Prefs.AutoSave.Interval>'
}

@test "timeline Link Selection is enabled" {
  cp "$DIR/fixtures/premiere_pro_v26.2.2/Adobe Premiere Pro Prefs_truncated" "$PREFS"
  premiere_apply_prefs "$PREFS" "x.kys" "WS"
  run cat "$PREFS"
  assert_output --partial '<TL.PREFLinkedSelectionState>true</TL.PREFLinkedSelectionState>'
}

@test "timeline display settings all enabled" {
  cp "$DIR/fixtures/premiere_pro_v26.2.2/Adobe Premiere Pro Prefs_truncated" "$PREFS"
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
}

@test "output prefs is valid XML" {
  cp "$DIR/fixtures/premiere_pro_v26.2.2/Adobe Premiere Pro Prefs_truncated" "$PREFS"
  premiere_apply_prefs "$PREFS" "x.kys" "WS"
  run xmllint --noout "$PREFS"
  assert_success
}

@test "no BOM is introduced" {
  cp "$DIR/fixtures/premiere_pro_v26.2.2/Adobe Premiere Pro Prefs_truncated" "$PREFS"
  premiere_apply_prefs "$PREFS" "x.kys" "WS"
  run head -c 3 "$PREFS"
  assert_output '<?x'   # would be the UTF-8 BOM bytes if perl had added one
}

@test "idempotent: second run is byte-identical" {
  cp "$DIR/fixtures/premiere_pro_v26.2.2/Adobe Premiere Pro Prefs_truncated" "$PREFS"
  premiere_apply_prefs "$PREFS" "Luis_Mengo_25.1.kys" "LM - Single monitor"
  cp "$PREFS" "$PREFS.first"
  premiere_apply_prefs "$PREFS" "Luis_Mengo_25.1.kys" "LM - Single monitor"
  run cmp -s "$PREFS.first" "$PREFS"
  assert_success
}

@test "a renamed node is reported and skipped without corrupting others" {
  cp "$DIR/fixtures/premiere_pro_v26.2.2/Adobe Premiere Pro Prefs_truncated" "$PREFS"
  # simulate a future Premiere renaming one node
  sed -i.bak 's/TL.PREFShowFXBadges/TL.PREFShowFXBadgesRENAMED/g' "$PREFS"
  run premiere_apply_prefs "$PREFS" "Luis_Mengo_25.1.kys" "LM - Single monitor"
  assert_success
  assert_output --partial 'needs revising'
  assert_output --partial 'TL.PREFShowFXBadges'
  run xmllint --noout "$PREFS"
  assert_success
  run cat "$PREFS"
  assert_output --partial '<BE.Prefs.AutoSave.Interval>5</BE.Prefs.AutoSave.Interval>'           # others still applied
  assert_output --partial '<TL.PREFShowFXBadgesRENAMED>false</TL.PREFShowFXBadgesRENAMED>'        # renamed node untouched
}

@test "premiere_workspace_name extracts the UserName" {
  run premiere_workspace_name "$DIR/fixtures/premiere_pro_v26.2.2/UserWorkspace_truncated.xml"
  assert_output 'LM - Single monitor'
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
