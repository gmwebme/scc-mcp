#!/usr/bin/env bash
# SessionStart hook for the scc-mcp auto-map system.
# Contract: ALWAYS exit 0. Emit either nothing (opt-out / not a mapped project)
# or one JSON object with hookSpecificOutput.additionalContext.
# A failure here must never block or delay a session — on any error print nothing.
#
# Backing MCP server: codebase-memory-mcp (https://github.com/DeusData/codebase-memory-mcp).
# This hook is the deterministic tier ONLY. All structural code queries are
# delegated to CBM. PROJECT_MAP.md is deprecated; this hook references only
# INDEX.md (≤1500 tokens) and metrics.json.

LIB="$(dirname "${BASH_SOURCE[0]}")/scc-map-lib.sh"
# shellcheck disable=SC1090
. "$LIB" 2>/dev/null || exit 0

{
  ROOT="$(scc_find_root "$PWD")" || exit 0          # no .scc/INDEX.md → silent
  META="$ROOT/.scc/.map-meta.json"
  INDEX="$ROOT/.scc/INDEX.md"
  CACHE="$ROOT/.scc/.cache"
  MFLAG="$CACHE/migrated-to-cbm"
  mkdir -p "$CACHE" 2>/dev/null

  # 1. Deterministic tier: refresh complexity metrics (pure bash, 0 LLM).
  HOTSPOTS="$(scc_refresh_metrics "$ROOT" 2>/dev/null)"
  SCC_OK="false"; scc_have_scc && SCC_OK="true"
  CBM_OK="false"; command -v codebase-memory-mcp >/dev/null 2>&1 && CBM_OK="true"

  # 2. Current content signal vs the signal recorded at last /scc-refresh.
  read -r CUR_HEAD CUR_HASH <<<"$(scc_content_signal "$ROOT")"
  SEM_HEAD="$(scc_meta_get semantic_git_head "$META")"
  SEM_HASH="$(scc_meta_get semantic_content_hash "$META")"

  # 3. Freshness verdict + changed-file list (rename-aware).
  if [ -z "$SEM_HEAD" ] && [ -z "$SEM_HASH" ]; then
    BANNER="ℹ Project map present but no baseline recorded — run /scc-refresh to anchor it."
  elif [ "$CUR_HEAD" = "$SEM_HEAD" ] && [ "$CUR_HASH" = "$SEM_HASH" ]; then
    BANNER="✓ Project map current (HEAD ${CUR_HEAD:0:7}). Query codebase-memory-mcp live for detail (get_graph_schema first)."
  else
    CHANGED=""; N="?"
    if scc_have_git "$ROOT" && [ "$SEM_HEAD" != "nogit" ] && [ -n "$SEM_HEAD" ]; then
      DIFF_LINES="$(git -C "$ROOT" diff --name-status "$SEM_HEAD" HEAD 2>/dev/null \
        | awk -F'\t' '
            $1 ~ /^R/ { print $3; next }
            $1 ~ /^C/ { print $3; next }
            $1 ~ /^[ADMTUX]/ { print $2; next }
          ')"
      STATUS_LINES="$(git -C "$ROOT" status --porcelain 2>/dev/null \
        | awk '{ if ($1 ~ /^R/) { sub(/.*-> /, ""); print; next } print $2 }')"
      CHANGED="$(printf '%s\n%s\n' "$DIFF_LINES" "$STATUS_LINES" \
        | sort -u | grep -v '^\.scc/' | grep . )"
      N="$(printf '%s\n' "$CHANGED" | grep -c . )"
    fi
    SAMPLE="$(printf '%s\n' "$CHANGED" | grep . | head -n8 | paste -sd', ' -)"
    BANNER="⚠ Project map STALE — ${N} file(s) changed since baseline (${SEM_HEAD:0:7}→${CUR_HEAD:0:7}). Run /scc-refresh for an accurate INDEX.md; for the changed files prefer live codebase-memory-mcp queries (detect_changes, trace_path). Changed: ${SAMPLE:-unknown}"
  fi

  # 4. Record the deterministic snapshot (semantic_* untouched here).
  scc_meta_write "$META" \
    semantic_git_head     "${SEM_HEAD:-}" \
    semantic_content_hash "${SEM_HASH:-}" \
    metrics_generated_at  "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    current_git_head      "$CUR_HEAD" \
    current_content_hash  "$CUR_HASH" \
    scc_available         "$SCC_OK" \
    cbm_available         "$CBM_OK"

  # 5. Assemble injected context: tiny INDEX + banner + hotspots + one-shot migration banner.
  {
    echo "## scc-mcp project map (auto-injected, ~tiny)"
    echo
    cat "$INDEX" 2>/dev/null
    echo
    echo "### Freshness"
    echo "$BANNER"
    [ "$SCC_OK" = "false" ] && echo "(scc binary not installed — complexity approximate; \`brew install scc\` for exact.)"
    [ "$CBM_OK" = "false" ] && echo "(codebase-memory-mcp not on PATH — install: curl -fsSL https://raw.githubusercontent.com/DeusData/codebase-memory-mcp/main/install.sh | bash && codebase-memory-mcp install)"
    if [ -n "$HOTSPOTS" ]; then
      echo
      echo "### Top complexity hotspots (deterministic, this session)"
      printf '%s\n' "$HOTSPOTS" | awk -F'\t' 'NF>=2{print "- "$2" (score "$1")"}'
    fi
    # One-shot migration banner: fires once per project after the scc-mcp upgrade.
    if [ ! -f "$MFLAG" ]; then
      echo
      echo "### scc-mcp upgrade notice (shown once)"
      echo "This skill now delegates ALL structural queries to codebase-memory-mcp."
      echo "Tools: get_graph_schema (first), get_architecture, search_graph, trace_path, query_graph, get_code_snippet, detect_changes, search_code, list_projects, manage_adr."
      echo "If /mcp does not list codebase-memory-mcp with 14 tools, run: codebase-memory-mcp install"
      : > "$MFLAG"
    fi
    echo
    echo "_INDEX.md is the only persisted map artifact. For deeper structure, call codebase-memory-mcp tools — never assume PROJECT_MAP.md is in context._"
  } | scc_emit_sessionstart

} 2>/dev/null

exit 0
