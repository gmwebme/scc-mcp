---
name: scc-mcp
description: Thin orientation layer that maintains .scc/INDEX.md (<=1500-token deterministic project map) and delegates ALL structural code queries to codebase-memory-mcp (CBM). Use when user asks for project overview, who calls X, what does X depend on, dead code, REST routes, cross-service HTTP calls, security audit, or incremental refresh. Owns: SessionStart freshness banner, Boyter-scc complexity hotspots, /scc-refresh slash command. Triggers on "scc", "scc-refresh", "project map", "map this codebase", "security audit", "deep dive". Works great on PrestaShop, Symfony, Laravel, Node, Go, Python.
---

# scc-mcp — thin orientation layer over codebase-memory-mcp

## What this skill owns

1. **SessionStart banner** — freshness verdict (ℹ / ✓ / ⚠), changed-file scope, top complexity hotspots, migration banner once-per-project.
2. **`.scc/INDEX.md`** — single committed artifact, <=1500 tokens, human-readable orientation. Built once per `/scc-refresh`.
3. **Boyter-`scc` complexity hotspots** — graph indexes structure (nodes/edges), NOT complexity. The deterministic tier is non-redundant.
4. **Post-compact directive** — when 1–25 files changed since baseline, push the model to run `/scc-refresh` (which calls CBM `detect_changes`).
5. **`/scc-refresh` slash command** — full or incremental rebuild of `.scc/INDEX.md` via CBM tools.

## What this skill does NOT own (delegate to CBM)

| Task | CBM tool |
|------|----------|
| Symbol / function / class lookup | `search_graph(name_pattern, label, file_pattern, min_degree, max_degree)` |
| Callers / callees / call chain | `trace_path(function_name, direction=inbound\|outbound\|both, depth=1..5)` |
| Complex graph patterns | `query_graph(<cypher subset>)` |
| Source hydration | `get_code_snippet(qualified_name="<project>.<path>.<name>")` |
| Architecture overview | `get_architecture` |
| Incremental impact | `detect_changes` |
| Text search | `search_code` |
| Dead code | `search_graph(max_degree=0, exclude_entry_points=true)` |
| ADRs | `manage_adr` |
| Index lifecycle | `index_repository`, `index_status`, `list_projects`, `delete_project` |
| Runtime trace validation | `ingest_traces` |
| Schema sniffing | **`get_graph_schema` — call FIRST in every workflow** |

Reference: https://github.com/DeusData/codebase-memory-mcp (v0.6.1, 14 tools).

## Requirements

- **codebase-memory-mcp** installed and registered as MCP server. Install:
  ```bash
  curl -fsSL https://raw.githubusercontent.com/DeusData/codebase-memory-mcp/main/install.sh | bash
  codebase-memory-mcp install
  ```
  Verify with `/mcp` — should list `codebase-memory-mcp` with 14 tools.
- **Boyter `scc`** for exact complexity. Optional but recommended:
  ```bash
  brew install scc   # macOS
  ```
  If absent, the deterministic tier degrades gracefully to line-count.

## Cypher subset supported by `query_graph`

- `MATCH` with labels and relationship types, variable-length paths
- `WHERE` with comparisons, regex (`=~`), `CONTAINS`
- `RETURN` with property access, `COUNT`, `DISTINCT`, `ORDER BY`, `LIMIT`
- **Not supported:** `WITH`, `COLLECT`, `OPTIONAL MATCH`, any mutations

Examples:
```cypher
MATCH (f:Function) WHERE f.name =~ '.*Handler.*' RETURN f.name, f.file_path LIMIT 50
MATCH (a)-[r:HTTP_CALLS]->(b) RETURN a.name, b.name, r.url_path, r.confidence LIMIT 20
MATCH (a)-[r:CALLS]->(b) WHERE a.name = 'main' RETURN b.name
```

## Qualified names (`get_code_snippet`)

Format: `<project>.<path_parts>.<name>`. Discover via `search_graph(name_pattern=".*PartialName.*")` first.

## Persisted, self-refreshing map (`.scc/`)

Per project under `<root>/.scc/`:

| File | What | In context? | Git |
|------|------|-------------|-----|
| `INDEX.md` | <=1500-token deterministic schema (see `scripts/validate-map.sh`) | **Yes** — injected every SessionStart | commit |
| `metrics.json` | `scc` complexity output | No | gitignored |
| `.map-meta.json` | Baseline git head + content hash | No | gitignored |
| `.cache/migrated-to-cbm` | One-shot migration banner flag | No | gitignored |

Opt-in per project: `.scc/` does not exist until first `/scc-refresh`.

`PROJECT_MAP.md` (older artifact) is deprecated. `get_architecture` returns the same data on demand in one tool call. If a legacy `PROJECT_MAP.md` exists, it is ignored — no need to delete.

## Refresh tiers

- **Deterministic** (every SessionStart, pure bash, 0 LLM tokens): `scripts/session-start.sh` refreshes `metrics.json`, computes freshness verdict, injects `INDEX.md` + banner + top-5 complexity hotspots.
- **Semantic** (on `/scc-refresh`): regenerates `.scc/INDEX.md` via `get_architecture` + `search_graph(label="Route")`. Incremental via `detect_changes` when 1–25 files changed.

## Freshness banner

- `✓ current` — trust `INDEX.md`; query CBM live for detail.
- `⚠ STALE — N files changed` — predates recent edits. Run `/scc-refresh` for accurate index; for the changed files prefer live CBM queries.
- `ℹ no baseline` — run `/scc-refresh` to anchor.

## Workflow

`prompts/` files are recipes invoked by `/scc-refresh` and security audits. Substitute `[PLACEHOLDER]` with the user's target.

| Prompt | Use |
|--------|-----|
| `01-initial-map.md` | First `.scc/INDEX.md` build via `get_graph_schema` + `get_architecture` |
| `02-deep-dive.md` | Deep-dive on a function/module via `search_graph` + `trace_path` + `get_code_snippet` |
| `03-security-audit.md` | Language-aware taint audit (PHP/Symfony, Node, Python, Go, Rust) |
| `04-full-audit.md` | Architecture + complexity + dead code + security red flags orchestrator |
| `05-incremental-refresh.md` | `detect_changes` + minimal hydration; patches `INDEX.md` in place |

## Graceful degradation

- **No CBM installed:** SessionStart banner says so + install instructions. `/scc-refresh` falls back to `Glob`/`Grep`/`Read` scoped tightly.
- **No `scc` binary:** complexity tier approximates from line count; banner notes it.
- **No git:** `scc_content_signal` hashes file mtimes via `find`. Freshness still works.

The SessionStart hook always `exit 0` and is silent outside mapped projects.

## Coexistence with CBM's own hooks

CBM auto-installs:
- `~/.claude/hooks/cbm-session-reminder` (SessionStart, text reminder of tool names)
- `~/.claude/hooks/cbm-code-discovery-gate` (PreToolUse, blocks the FIRST `Grep`/`Glob`/`Read` per session to nudge the model toward CBM tools)

Both are non-conflicting. scc-mcp's SessionStart emits JSON `additionalContext`; CBM's emits stdout text. They concatenate into the agent's context.
