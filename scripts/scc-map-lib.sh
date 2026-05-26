#!/usr/bin/env bash
# scc-map-lib.sh — shared helpers for the scc-mcp auto-map system.
# Pure bash, zero LLM. Sourced by session-start.sh and usable from /scc-refresh.
# Every function is defensive: callers must never let a failure block a session.

# --- detection -------------------------------------------------------------

# Walk up from $1 (default: PWD) until a dir containing .scc/INDEX.md is found.
# Echoes the project root on success; returns 1 if none (system is opt-in).
scc_find_root() {
  local dir="${1:-$PWD}"
  dir="$(cd "$dir" 2>/dev/null && pwd)" || return 1
  while [ -n "$dir" ] && [ "$dir" != "/" ]; do
    if [ -f "$dir/.scc/INDEX.md" ]; then
      printf '%s\n' "$dir"
      return 0
    fi
    dir="$(dirname "$dir")"
  done
  [ -f "/.scc/INDEX.md" ] && { printf '/\n'; return 0; }
  return 1
}

# For /scc-refresh bootstrap: git toplevel of PWD, else PWD. Always succeeds.
scc_pick_root() {
  git rev-parse --show-toplevel 2>/dev/null || pwd
}

# Ensure .scc/ exists with a .gitignore that keeps the map but drops churn.
scc_init_dir() { # root
  mkdir -p "$1/.scc" 2>/dev/null || return 1
  local gi="$1/.scc/.gitignore"
  [ -f "$gi" ] || printf 'metrics.json\n.map-meta.json\n*.tmp.*\n' >"$gi"
}

# Record the semantic baseline (called by /scc-refresh after writing the map),
# preserving deterministic keys already in meta.
scc_set_baseline() { # root
  local root="$1" meta="$1/.scc/.map-meta.json" head hash
  read -r head hash <<<"$(scc_content_signal "$root")"
  scc_meta_write "$meta" \
    semantic_git_head     "$head" \
    semantic_content_hash "$hash" \
    semantic_generated_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    metrics_generated_at  "$(scc_meta_get metrics_generated_at "$meta")" \
    current_git_head      "$head" \
    current_content_hash  "$hash" \
    scc_available         "$(scc_have_scc && echo true || echo false)"
}

scc_have_git() { git -C "$1" rev-parse --is-inside-work-tree >/dev/null 2>&1; }
scc_have_scc() { command -v scc >/dev/null 2>&1; }
scc_have_jq()  { command -v jq  >/dev/null 2>&1; }

# --- hashing (OS aware) ----------------------------------------------------

scc_sha() {
  if command -v shasum >/dev/null 2>&1; then shasum | cut -c1-12
  elif command -v sha1sum >/dev/null 2>&1; then sha1sum | cut -c1-12
  else cksum | tr -d ' ' | cut -c1-12
  fi
}

# Content signal for a root: git HEAD + porcelain when git, else file mtimes.
# Echoes "<githead-or-nogit> <hash>".
scc_content_signal() {
  local root="$1" head="nogit" sig
  if scc_have_git "$root"; then
    head="$(git -C "$root" rev-parse HEAD 2>/dev/null || echo nogit)"
    sig="$( { git -C "$root" status --porcelain 2>/dev/null; } | scc_sha )"
  else
    sig="$( find "$root" -type f -not -path '*/.scc/*' -not -path '*/.git/*' \
              \( -name '*.[ch]' -o -name '*.go' -o -name '*.js' -o -name '*.ts' \
                 -o -name '*.py' -o -name '*.php' -o -name '*.rb' -o -name '*.java' \
                 -o -name '*.rs' -o -name '*.tsx' -o -name '*.jsx' -o -name '*.vue' \) \
              -printf '%p %T@\n' 2>/dev/null | sort | scc_sha )"
    [ -z "$sig" ] && sig="$( find "$root" -type f -not -path '*/.scc/*' \
              -not -path '*/.git/*' -exec stat -f '%N %m' {} + 2>/dev/null \
              | sort | scc_sha )"
  fi
  printf '%s %s\n' "$head" "$sig"
}

# --- flat-JSON read (no jq dependency) -------------------------------------
# .scc/.map-meta.json is written by us with all values as strings, so a
# single grep/sed extractor is enough and never needs jq.

scc_meta_get() { # key file
  [ -f "$2" ] || return 1
  grep -o "\"$1\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" "$2" 2>/dev/null \
    | head -n1 | sed 's/.*:[[:space:]]*"\(.*\)"/\1/'
}

# --- flat-JSON write -------------------------------------------------------
# scc_meta_write file k1 v1 k2 v2 ...   (atomic; all values stringified)
scc_meta_write() {
  local file="$1"; shift
  local tmp="$file.tmp.$$" first=1
  { printf '{\n'
    while [ "$#" -ge 2 ]; do
      [ "$first" -eq 1 ] || printf ',\n'; first=0
      printf '  "%s": "%s"' "$1" "$(printf '%s' "$2" | sed 's/\\/\\\\/g; s/"/\\"/g')"
      shift 2
    done
    printf '\n}\n'
  } >"$tmp" 2>/dev/null && mv "$tmp" "$file" 2>/dev/null
}

# --- JSON string escaping (for hook stdout) --------------------------------
# Prefer jq for correctness; fall back to sed+awk.
scc_emit_sessionstart() { # additionalContext-text on stdin
  local ctx; ctx="$(cat)"
  if scc_have_jq; then
    jq -cn --arg c "$ctx" \
      '{hookSpecificOutput:{hookEventName:"SessionStart",additionalContext:$c}}'
  elif command -v python3 >/dev/null 2>&1; then
    SCC_CTX="$ctx" python3 -c 'import json,os; print(json.dumps({"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":os.environ["SCC_CTX"]}}))'
  else
    # Last resort: escape \, ", control chars; fold newlines to \n.
    local esc
    esc="$(printf '%s' "$ctx" \
      | sed 's/\\/\\\\/g; s/"/\\"/g; s/	/\\t/g; s/\r/\\r/g' \
      | tr -d '\000-\010\013\014\016-\037' \
      | awk 'BEGIN{ORS=""} {if(NR>1)printf "\\n"; printf "%s",$0}')"
    printf '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"%s"}}\n' "$esc"
  fi
}

# --- deterministic tier: metrics + top hotspots ----------------------------
# Writes <root>/.scc/metrics.json and echoes up to 5 "complexity\tpath" lines.
scc_refresh_metrics() {
  local root="$1" out="$1/.scc/metrics.json"
  if scc_have_scc; then
    scc --format json --by-file -s complexity --no-cocomo \
        --not-match '(^|/)(\.scc|\.git|node_modules|vendor|dist|build)/' \
        "$root" >"$out" 2>/dev/null || echo '[]' >"$out"
    if scc_have_jq; then
      jq -r '[.[].Files[]?] | sort_by(-(.Complexity//0)) | .[:5][]
             | "\(.Complexity//0)\t\(.Location)"' "$out" 2>/dev/null
      return 0
    fi
    # scc + no jq: re-derive via csv (one cheap extra pass)
    scc --format csv --by-file -s complexity --no-cocomo "$root" 2>/dev/null \
      | awk -F, 'NR>1{print $8"\t"$2}' | sort -t'	' -k1 -nr | head -n5
    return 0
  fi
  # no scc: approximate hotspots by line count of tracked source files
  echo '{"_fallback":"scc not installed; metrics approximate"}' >"$out"
  local files
  if scc_have_git "$root"; then
    files="$(git -C "$root" ls-files 2>/dev/null)"
  else
    files="$(cd "$root" && find . -type f -not -path './.scc/*' \
             -not -path './.git/*' -not -path './node_modules/*' 2>/dev/null)"
  fi
  printf '%s\n' "$files" | grep -E '\.(c|h|go|js|ts|tsx|jsx|py|php|rb|java|rs|vue)$' \
    | head -n400 | while IFS= read -r f; do
        [ -f "$root/$f" ] || continue
        printf '%s\t%s\n' "$(wc -l <"$root/$f" 2>/dev/null | tr -d ' ')" "$f"
      done | sort -t'	' -k1 -nr | head -n5
}
