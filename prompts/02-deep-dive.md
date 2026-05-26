# Deep-dive on a function / class / module / feature (codebase-memory-mcp backend)
# Budget: <=8k tokens total context

Inputs: `[TARGET]` (anchor id from .scc/INDEX.md like `#mod-auth` or a partial name) and `[QUESTION]`.

1. **`get_graph_schema`** — cheap; confirms project is indexed.
2. If `[TARGET]` is a partial name: **`search_graph(label="Function", name_pattern=".*<partial>.*")`** to discover the exact qualified name.
3. If `[TARGET]` is a module anchor: **`search_graph(label="Function", file_pattern="<module path>/*", min_degree=5)`** to locate hub functions.
4. For each hub or target function: **`trace_path(function_name=<qname>, direction="both", depth=3)`** to map callers and callees. Use `direction="outbound"` when the question is "what does X do", `direction="inbound"` for "who depends on X".
5. **`get_code_snippet(qualified_name="<project>.<path>.<name>")`** for any function whose source you must read. Do NOT use `Read` unless this fails.
6. For multi-hop / cross-service patterns ("which Controller writes to which Service that emits which Event"): **`query_graph`** with read-only Cypher. Supported: `MATCH` (labels + rel types + variable-length paths), `WHERE` (comparisons, regex `=~`, `CONTAINS`), `RETURN` (property access, `COUNT`, `DISTINCT`, `ORDER BY`, `LIMIT`). Not supported: `WITH`, `COLLECT`, `OPTIONAL MATCH`, mutations.
7. Report in this exact order: signature & location → callers (inbound) → callees (outbound) → I/O & DB interactions → error handling & security boundaries → relevant business rules. Reference line numbers from `get_code_snippet`.
8. Stop when `[QUESTION]` is answered. Do not enumerate further.
