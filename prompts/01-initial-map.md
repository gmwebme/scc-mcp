# Initial project map (codebase-memory-mcp backend)
# Budget: <=4k tokens total context, <=1500 tokens written to .scc/INDEX.md

1. **`get_graph_schema`** first. Record: node counts, edge counts, sample names. If error "project not found or not indexed" — run `index_repository(repo_path=".")` then retry.
2. **`get_architecture`** once. Capture: languages, packages, entry_points, routes, hotspots, boundaries, layers, clusters.
3. **`search_graph(label="Route")`** only if Route node count > 0. Capture up to top 20 routes as `method path -> handler`.
4. Emit `.scc/INDEX.md` against the strict schema enforced by `scripts/validate-map.sh`:
   - One H1: `# <project> — codebase index`
   - Metadata HTML comment: `<!-- scc-mcp:index v=2 generated=<ISO-8601-UTC> baseline=<sha-or-NONE> tokens=<int> -->`
   - `## Summary` (3–6 bullets, <=120 chars each)
   - `## Modules` — one H3 per top module with anchor `### <name> {#mod-<slug>}` and 1–3 function bullets each
   - `## Routes` (optional; only if step 3 returned rows)
   - `## Hotspots` (table from `metrics.json`, top 5–10 files)
   - `## How to query deeper` (fixed boilerplate listing the 14 CBM tools + `get_graph_schema` first-rule)
5. Hard ceiling 1500 tokens. Run `bash ~/.claude/skills/scc-mcp/scripts/validate-map.sh .scc/INDEX.md` and trim if over.
6. Do NOT call `search_graph` per-module here; cluster list from step 2 is sufficient orientation.
