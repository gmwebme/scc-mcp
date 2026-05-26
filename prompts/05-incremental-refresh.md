# Incremental refresh (codebase-memory-mcp backend)
# Budget: <=3k tokens total context

Inputs: `CHANGED_FILES` from `scc-refresh-prep.sh` preflight (capped at 25).

[CHANGED_FILES]

1. **`get_graph_schema`** — cheap; confirms project is indexed.
2. **`detect_changes`** — "maps uncommitted changes to affected symbols with risk classification". Treat its `affected_symbols` as the work list. If `detect_changes` returns empty but `CHANGED_FILES` is non-empty, fall back to `search_graph(file_pattern=<path>)` per changed file.
3. For each affected symbol: **`trace_path(function_name=<qname>, direction="inbound", depth=2)`** to flag blast radius.
4. **`get_code_snippet`** only for symbols whose risk classification is `high` or `medium`. Skip `low` to stay under budget.
5. **Patch `.scc/INDEX.md` in place** — touch only sections under anchor ids of changed modules. Keep total ≤1500 tokens. Run `bash ~/.claude/skills/scc-mcp/scripts/validate-map.sh .scc/INDEX.md` to verify.
6. Do NOT call `get_architecture` here — full-graph operation is wasteful on an incremental refresh.

Return only the patched `INDEX.md` + a one-line summary `N symbols touched, M high-risk`.
