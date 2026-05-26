#!/usr/bin/env bash
# /scc-refresh postflight. Call AFTER .scc/INDEX.md is written.
# Anchors the semantic baseline so SessionStart reports "current".
# Usage: scc-refresh-finalize.sh [ROOT]
#
# Note: PROJECT_MAP.md is deprecated — get_architecture (codebase-memory-mcp)
# returns equivalent data live in one call. We no longer require it.

LIB="$(dirname "${BASH_SOURCE[0]}")/scc-map-lib.sh"
# shellcheck disable=SC1090
. "$LIB" 2>/dev/null || exit 1

ROOT="${1:-$(scc_pick_root)}"
if [ ! -f "$ROOT/.scc/INDEX.md" ]; then
  echo "scc-refresh-finalize: INDEX.md missing in $ROOT/.scc — not anchoring." >&2
  exit 1
fi
scc_init_dir "$ROOT"

# Validate INDEX.md against the strict schema before anchoring.
VAL="$(dirname "${BASH_SOURCE[0]}")/validate-map.sh"
if [ -x "$VAL" ]; then
  if ! "$VAL" "$ROOT/.scc/INDEX.md" >&2; then
    echo "scc-refresh-finalize: validate-map.sh failed — not anchoring." >&2
    exit 2
  fi
fi

scc_set_baseline "$ROOT"

IDX_TOK=$(( $(wc -w <"$ROOT/.scc/INDEX.md" 2>/dev/null | tr -d ' ') * 4 / 3 ))
echo "Baseline anchored at $(scc_meta_get semantic_git_head "$ROOT/.scc/.map-meta.json")."
echo "INDEX.md ≈ ${IDX_TOK} tokens (hard cap 1500)."
[ "$IDX_TOK" -gt 1500 ] && echo "WARNING: INDEX.md over 1500-token cap — trim it." >&2
exit 0
