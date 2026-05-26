#!/usr/bin/env bats
# Run: bats tests/validate-map.bats
# Cases: well-formed (exit 0), over-budget (exit 3), missing required heading (exit 6).

setup() {
  TMP="$(mktemp -d)"
  mkdir -p "$TMP/.scc"
  SCRIPT="$BATS_TEST_DIRNAME/../scripts/validate-map.sh"
}

teardown() { rm -rf "$TMP"; }

@test "well-formed minimal INDEX.md passes" {
  cat >"$TMP/.scc/INDEX.md" <<'EOF'
# demo — codebase index
<!-- scc-mcp:index v=2 generated=2026-05-25T00:00:00Z baseline=NONE tokens=80 -->
## Summary
- minimal
## Modules
### core {#mod-core}
- [core::main](#fn-core-main) — entry
### core::main {#fn-core-main}
entry function
## Hotspots
| file | lines | complexity |
|---|---|---|
| main.go | 10 | 2 |
## How to query deeper
get_graph_schema first.
EOF
  run bash "$SCRIPT" "$TMP/.scc/INDEX.md"
  [ "$status" -eq 0 ]
  [[ "$output" == OK:* ]]
}

@test "over-budget INDEX.md fails with exit 3" {
  printf '# x\n<!-- scc-mcp:index v=2 generated=t baseline=NONE tokens=99999 -->\n' >"$TMP/.scc/INDEX.md"
  head -c 7000 /dev/urandom | base64 >>"$TMP/.scc/INDEX.md"
  run bash "$SCRIPT" "$TMP/.scc/INDEX.md"
  [ "$status" -eq 3 ]
  [[ "$output" == *"> 1500 cap"* ]]
}

@test "missing required heading fails with exit 6" {
  cat >"$TMP/.scc/INDEX.md" <<'EOF'
# x — codebase index
<!-- scc-mcp:index v=2 generated=t baseline=NONE tokens=10 -->
## Summary
- has summary but no Modules/Hotspots/How
EOF
  run bash "$SCRIPT" "$TMP/.scc/INDEX.md"
  [ "$status" -eq 6 ]
}
