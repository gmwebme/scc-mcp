#!/usr/bin/env bats
# Run: bats tests/incremental.bats
# Verifies scc-refresh-prep.sh correctly handles renames + small changes.

setup() {
  REPO="$(mktemp -d)"
  ( cd "$REPO" && git init -q && git config user.email t@t && git config user.name t \
      && echo a >a.txt && git add a.txt && git commit -q -m init )
  mkdir -p "$REPO/.scc"
  HEAD=$(cd "$REPO" && git rev-parse HEAD)
  printf '{"semantic_git_head":"%s","semantic_content_hash":"x"}\n' "$HEAD" \
    >"$REPO/.scc/.map-meta.json"
  echo "# stub" >"$REPO/.scc/INDEX.md"
  touch "$REPO/.scc/PROJECT_MAP.md"
  SCRIPT="$BATS_TEST_DIRNAME/../scripts/scc-refresh-prep.sh"
}

teardown() { rm -rf "$REPO"; }

@test "rename a.txt -> b.txt counts as 1 changed file, not 2" {
  cd "$REPO"
  git mv a.txt b.txt
  git commit -q -m rename
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'MODE=incremental'
  changed=$(echo "$output" | sed -n '/--- CHANGED_FILES ---/,/--- END ---/p' \
    | grep -v '^---' | grep . | wc -l | tr -d ' ')
  [ "$changed" -eq 1 ]
  echo "$output" | grep -q 'b.txt'
  ! echo "$output" | grep -q '^a.txt$'
}

@test "small modify -> MODE=incremental with 1 changed" {
  cd "$REPO"
  echo more >>a.txt
  git add a.txt
  git commit -q -m mod
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'MODE=incremental'
}

@test "no baseline meta -> MODE=full" {
  cd "$REPO"
  rm .scc/.map-meta.json
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'MODE=full'
}
