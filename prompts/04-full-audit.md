# Full audit — architecture + complexity + dead code + security (codebase-memory-mcp + Boyter-scc)
# Budget: <=6k tokens total output

1. **`get_graph_schema`** — confirm indexed.
2. **`get_architecture`** → Executive summary section (languages, top-level boundaries, layer count, route count, ADRs if present).
3. Top-10 complexity hotspots from Boyter-`scc`:
   ```bash
   scc --format json --by-file -s complexity --no-cocomo "$ROOT" | jq -r '[.[].Files[]] | sort_by(-.Complexity) | .[:10][] | "\(.Complexity)\t\(.Location)"'
   ```
   (Falls back to line-count if `scc` not installed.)
4. Top-10 highest-fan-out functions: **`search_graph(label="Function", relationship="CALLS", direction="outbound", min_degree=10)`**.
5. Dead code: **`search_graph(label="Function", relationship="CALLS", direction="inbound", max_degree=0, exclude_entry_points=true)`**.
6. Cross-service surface: **`query_graph("MATCH (a)-[r:HTTP_CALLS]->(b) RETURN count(r) AS http_edges")`** + ASYNC_CALLS variant.
7. Security red flags: run `03-security-audit.md` against routes only; cap at top-20 highest-fan-in handlers.

## Output sections (exact order, no prose between)

1. **Executive summary** — 5 bullets max.
2. **Hotspots (complexity)** — table from step 3.
3. **Hubs (fan-out)** — table from step 4.
4. **Dead code** — list from step 5; group by package.
5. **Cross-service edges** — counts from step 6.
6. **Security red flags** — from step 7; one line per finding with CWE-id.
