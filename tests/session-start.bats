#!/usr/bin/env bats
# Run: bats tests/session-start.bats
# Table-driven over freshness verdicts: current ✓, stale ⚠, no-baseline ℹ.

setup() {
  TMP="$(mktemp -d)"
  ( cd "$TMP" && git init -q && git config user.email t@t && git config user.name t \
      && echo a >a.txt && git add a.txt && git commit -q -m init )
  mkdir -p "$TMP/.scc"
  SCRIPT="$BATS_TEST_DIRNAME/../scripts/session-start.sh"
}

teardown() { rm -rf "$TMP"; }

@test "no .scc/INDEX.md -> silent (exit 0, no output)" {
  rm -rf "$TMP/.scc"
  run env PWD="$TMP" bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "INDEX.md present, no baseline -> emits informational banner" {
  cd "$TMP"
  echo "# stub — codebase index" >.scc/INDEX.md
  echo "<!-- scc-mcp:index v=2 generated=t baseline=NONE tokens=5 -->" >>.scc/INDEX.md
  run env PWD="$TMP" bash "$SCRIPT"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'no baseline'
}

@test "INDEX.md present, baseline matches HEAD -> emits ✓ current" {
  cd "$TMP"
  echo "# stub — codebase index" >.scc/INDEX.md
  echo "<!-- scc-mcp:index v=2 generated=t baseline=NONE tokens=5 -->" >>.scc/INDEX.md
  HEAD=$(git rev-parse HEAD)
  HASH=$(git status --porcelain | shasum | cut -c1-12)
  cat >.scc/.map-meta.json <<EOF
{
  "semantic_git_head": "$HEAD",
  "semantic_content_hash": "$HASH"
}
EOF
  run env PWD="$TMP" bash "$SCRIPT"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'current'
}
