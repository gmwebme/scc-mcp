#!/usr/bin/env bash
# Validate .scc/INDEX.md against the strict schema.
# Exit 0 = pass; non-zero = fail with reason on stderr.
set -euo pipefail

f="${1:-.scc/INDEX.md}"
[[ -f "$f" ]] || { echo "FAIL: $f not found" >&2; exit 2; }

bytes=$(wc -c <"$f")
tokens=$(( bytes / 4 ))
(( tokens <= 1500 )) || { echo "FAIL: $tokens tokens > 1500 cap" >&2; exit 3; }

# Exactly one H1
h1=$(grep -c '^# ' "$f" || true)
(( h1 == 1 )) || { echo "FAIL: expected 1 H1, got $h1" >&2; exit 4; }

# Required metadata block
grep -q '^<!-- scc-mcp:index v=2 ' "$f" \
  || { echo "FAIL: metadata comment missing (expected '<!-- scc-mcp:index v=2 ...')" >&2; exit 5; }

# Required H2 sections (order not enforced; presence is)
for h in '^## Summary$' '^## Modules$' '^## Hotspots$' '^## How to query deeper$'; do
  grep -qE "$h" "$f" \
    || { echo "FAIL: missing required heading matching: $h" >&2; exit 6; }
done

# Every #fn-/#mod-/#route- ref must have a matching anchor declaration
anchors=$(grep -oE '\{#(mod|fn|route)-[a-z0-9-]+\}' "$f" | tr -d '{}' | sort -u || true)
refs=$(grep -oE '\(#(mod|fn|route)-[a-z0-9-]+\)' "$f" | tr -d '()' | sort -u || true)
if [[ -n "$refs" ]]; then
  missing=$(comm -23 <(printf '%s\n' "$refs") <(printf '%s\n' "$anchors") || true)
  [[ -z "$missing" ]] || { echo "FAIL: dangling anchor refs: $(echo "$missing" | tr '\n' ' ')" >&2; exit 7; }
fi

n_anchors=$(printf '%s\n' "$anchors" | grep -c . || true)
echo "OK: $tokens tokens, $n_anchors anchors"
