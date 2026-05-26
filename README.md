# scc-mcp

> A Claude Code skill that gives your AI agent a **deterministic, <=1500-token project map** and routes every structural code query through [codebase-memory-mcp](https://github.com/DeusData/codebase-memory-mcp) — so Claude stops dumping 50 files into context to answer "who calls X?".

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Claude Code](https://img.shields.io/badge/Claude%20Code-skill-orange)](https://docs.claude.com/en/docs/claude-code)

## Why this exists

Out of the box, Claude Code answers questions like "who calls `processOrder`?" by greppin' the repo and reading whatever files come back. On a 200k-LOC PrestaShop or Symfony app, that:

- burns 30k–80k tokens per question,
- misses indirect callers (HTTP, queues, DI),
- gives different answers every time depending on which files got read.

`scc-mcp` flips it: every SessionStart you get a **tight, deterministic project map** (`.scc/INDEX.md`, <=1500 tokens) plus a freshness verdict (`✓ / ⚠ / ℹ`). Every "who calls X / what does X depend on / where are the routes / find dead code" question is delegated to [`codebase-memory-mcp`](https://github.com/DeusData/codebase-memory-mcp) — a Neo4j-backed graph index with 14 structural tools.

## What you get

| Without scc-mcp | With scc-mcp |
|-----------------|--------------|
| Grep across files, read whatever matches | `search_graph(name_pattern=".*processOrder.*")` → exact list |
| Manually trace call chains, miss indirect calls | `trace_path("processOrder", direction=inbound, depth=3)` |
| Re-read the same files every session | `.scc/INDEX.md` injected at SessionStart |
| No idea what changed since last conversation | `⚠ STALE — 7 files changed` banner |
| Read 50 files to estimate complexity | Boyter-`scc` hotspots, top-5 in-banner |

## Real-world benchmarks

Run on real, indexed projects. Five structural queries per stack — `grep`'s output is the upper bound on tokens an agent would read if it did naive search; CBM's output is exact, structural, and tiny.

**Next.js project** (~59k `.ts`/`.tsx` files):

| Query | Raw grep tokens | CBM tokens | Reduction |
|-------|----------------:|-----------:|----------:|
| api-routes | 228,620 | 6 | 100.0% |
| data-fetching | 351,845 | 5 | 100.0% |
| high-fanout | 3,004,289 | 71 | 100.0% |
| **Total (matched queries)** | **3,584,754** | **82** | **~100%** |

**Mixed Go/Python monorepo** (~19k source files):

| Query | Raw grep tokens | CBM tokens | Reduction |
|-------|----------------:|-----------:|----------:|
| all-handlers | 248,971 | 71 | 100.0% |
| all-routes | 30,719 | 71 | 99.8% |
| http-edges | 1,220 | 5 | 99.6% |
| dead-code | 204,281 | 71 | 100.0% |
| high-fanout | 3,407,565 | 71 | 100.0% |
| **Total** | **3,892,756** | **289** | **~100%** |

Reproduce on your repo:
```bash
codebase-memory-mcp cli index_repository '{"repo_path":"/path/to/repo"}'
bash scripts/benchmark.sh --md /path/to/repo
```

## Install

1. **Install [codebase-memory-mcp](https://github.com/DeusData/codebase-memory-mcp)** (required):
   ```bash
   curl -fsSL https://raw.githubusercontent.com/DeusData/codebase-memory-mcp/main/install.sh | bash
   codebase-memory-mcp install
   ```
   Verify with `/mcp` — should list `codebase-memory-mcp` with 14 tools.

2. **Install `scc` for complexity hotspots** (optional but recommended):
   ```bash
   brew install scc   # macOS
   ```

3. **Drop this skill into your Claude Code skills dir**:
   ```bash
   git clone https://github.com/<you>/scc-mcp ~/.claude/skills/scc-mcp
   ```

4. **First run on a project**:
   ```
   /scc-refresh
   ```
   Builds `.scc/INDEX.md` once. Commit it. Subsequent sessions inject it automatically.

## How it works

```
SessionStart hook (pure bash, 0 LLM tokens)
  ├─ scripts/session-start.sh
  ├─ refreshes metrics.json via `scc`
  ├─ computes freshness verdict from git head + content hash
  └─ injects .scc/INDEX.md + banner + top-5 complexity hotspots

/scc-refresh slash command (semantic tier)
  ├─ full rebuild: get_architecture + search_graph(label="Route")
  └─ incremental: detect_changes (when 1-25 files changed)

Structural code queries → delegated to codebase-memory-mcp
  ├─ search_graph        — find functions/classes/routes
  ├─ trace_path          — call chains (inbound/outbound/both)
  ├─ get_code_snippet    — hydrate source for a qualified name
  ├─ query_graph         — Cypher subset for complex patterns
  ├─ get_architecture    — project structure on demand
  └─ detect_changes      — incremental impact analysis
```

## What this skill owns vs. what it delegates

**Owns** (deterministic tier, runs in pure bash):
- `.scc/INDEX.md` — the <=1500-token committed map
- SessionStart freshness banner
- Boyter-`scc` complexity hotspots
- `/scc-refresh` slash command

**Delegates** (everything structural goes to CBM):
- symbol lookup, call chains, dead code, REST routes
- cross-service HTTP calls, security audit taint paths
- source hydration, architecture overview, ADRs

See [`SKILL.md`](SKILL.md) for the full delegation table.

## Supported languages / frameworks

Works on anything CBM indexes. Battle-tested on:
- **PHP**: PrestaShop, Symfony, Laravel
- **JavaScript / TypeScript**: Node, Next.js, NestJS
- **Python**: Django, FastAPI, Flask
- **Go**, **Rust**

## Repo layout

```
scc-mcp/
├── SKILL.md                       # skill manifest + delegation table
├── prompts/
│   ├── 01-initial-map.md          # first .scc/INDEX.md build
│   ├── 02-deep-dive.md            # function/module deep dive
│   ├── 03-security-audit.md       # taint analysis per language
│   ├── 04-full-audit.md           # architecture + dead code + sec
│   └── 05-incremental-refresh.md  # detect_changes flow
├── scripts/
│   ├── session-start.sh           # SessionStart hook entry point
│   ├── scc-refresh-prep.sh        # /scc-refresh prep
│   ├── scc-refresh-finalize.sh    # /scc-refresh finalize
│   ├── validate-map.sh            # enforces <=1500-token schema
│   ├── scc-map-lib.sh             # shared helpers
│   └── benchmark.sh               # token-cost benchmark
└── tests/                         # bats tests
```

## Graceful degradation

| Missing | Behavior |
|---------|----------|
| codebase-memory-mcp | Banner explains; `/scc-refresh` falls back to scoped Grep/Glob/Read |
| `scc` binary | Complexity tier approximates from line count |
| `git` | Freshness hashes file mtimes via `find` |

The SessionStart hook always `exit 0`, silent outside mapped projects.

## License

MIT — see [LICENSE](LICENSE).

## Credits

- [codebase-memory-mcp](https://github.com/DeusData/codebase-memory-mcp) — the graph index this skill orchestrates
- [Boyter `scc`](https://github.com/boyter/scc) — complexity metrics
- [Anthropic Claude Code](https://docs.claude.com/en/docs/claude-code) — the agent runtime
