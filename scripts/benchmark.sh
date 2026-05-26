#!/usr/bin/env bash
# Compare raw-grep cost vs codebase-memory-mcp CLI cost across 5 representative queries.
# Auto-detects stack (Next.js / Express / NestJS / Symfony / Laravel / Django / Flask /
# Go / Rust / generic) and chooses idiomatic grep patterns + CBM queries per stack.
#
# Usage:
#   benchmark.sh [path]               auto-detect stack
#   benchmark.sh --stack=nextjs path  force a specific stack
#   benchmark.sh --md path            emit a markdown table (machine-readable)
#   benchmark.sh --list-stacks        list supported stacks
#
# CBM headline: "Five structural queries: ~3,400 tokens vs ~412,000 via grep — 99.2% reduction"
# Reference: https://github.com/DeusData/codebase-memory-mcp
set -uo pipefail

MARKDOWN=0
FORCED_STACK=""
ROOT="."
for a in "$@"; do
  case "$a" in
    --md|--markdown)     MARKDOWN=1 ;;
    --stack=*)           FORCED_STACK="${a#--stack=}" ;;
    --list-stacks)       echo "nextjs express nestjs symfony laravel django flask go rust generic"; exit 0 ;;
    -h|--help)           sed -n '2,16p' "$0"; exit 0 ;;
    *)                   ROOT="$a" ;;
  esac
done

CBM="${CBM_BIN:-codebase-memory-mcp}"
command -v "$CBM" >/dev/null 2>&1 || { echo "ERR: $CBM not on PATH" >&2; exit 1; }
[[ -d "$ROOT" ]] || { echo "ERR: $ROOT not a directory" >&2; exit 1; }
ROOT_ABS="$(cd "$ROOT" && pwd)"

# Preflight: is any project indexed?
PROJECTS_JSON="$("$CBM" cli list_projects '{}' 2>&1 | grep -v '^level=' || true)"
if echo "$PROJECTS_JSON" | grep -q '"projects":\[\]'; then
  echo "ERR: no projects indexed in codebase-memory-mcp." >&2
  echo "     Run first: $CBM cli index_repository '{\"repo_path\":\"$ROOT_ABS\"}'" >&2
  exit 2
fi

# --- stack detection --------------------------------------------------------

detect_stack() {
  local r="$1"
  if [ -f "$r/next.config.js" ] || [ -f "$r/next.config.ts" ] || [ -f "$r/next.config.mjs" ]; then
    echo nextjs; return
  fi
  if [ -f "$r/package.json" ]; then
    grep -q '"next"[[:space:]]*:'     "$r/package.json" 2>/dev/null && { echo nextjs;  return; }
    grep -q '"@nestjs/core"'          "$r/package.json" 2>/dev/null && { echo nestjs;  return; }
    grep -q '"express"[[:space:]]*:'  "$r/package.json" 2>/dev/null && { echo express; return; }
    echo express; return    # default for Node when no specific framework
  fi
  if [ -f "$r/composer.json" ]; then
    grep -q 'symfony/framework-bundle' "$r/composer.json" 2>/dev/null && { echo symfony; return; }
    grep -q 'laravel/framework'        "$r/composer.json" 2>/dev/null && { echo laravel; return; }
    echo symfony; return    # PHP fallback to symfony patterns
  fi
  if [ -f "$r/manage.py" ]; then echo django; return; fi
  if [ -f "$r/pyproject.toml" ] || [ -f "$r/requirements.txt" ]; then
    grep -qi 'django'           "$r/pyproject.toml" "$r/requirements.txt" 2>/dev/null && { echo django; return; }
    grep -qi 'flask\|fastapi'   "$r/pyproject.toml" "$r/requirements.txt" 2>/dev/null && { echo flask;  return; }
    echo flask; return
  fi
  [ -f "$r/go.mod" ]     && { echo go;   return; }
  [ -f "$r/Cargo.toml" ] && { echo rust; return; }
  echo generic
}

STACK="${FORCED_STACK:-$(detect_stack "$ROOT_ABS")}"

# --- per-stack query sets ---------------------------------------------------
# Format per line: name|grep-pattern|cbm-tool|cbm-json-args

queries_for() {
  case "$1" in
    nextjs) cat <<'EOF'
route-handlers|export (async )?function (GET|POST|PUT|DELETE|PATCH|handler)|search_graph|{"label":"Function","name_pattern":"^(GET|POST|PUT|DELETE|PATCH|handler)$"}
api-routes|app/api/.*/route\.|pages/api/|search_graph|{"label":"Route"}
server-components|'use server'|export const dynamic|search_code|{"pattern":"use server"}
data-fetching|fetch\(|axios\.|useSWR|useQuery|query_graph|{"query":"MATCH (a)-[r:HTTP_CALLS]->(b) RETURN a.name, b.name LIMIT 100"}
high-fanout|.|search_graph|{"label":"Function","relationship":"CALLS","direction":"outbound","min_degree":10}
EOF
      ;;
    nestjs) cat <<'EOF'
controllers|@Controller\(|search_graph|{"label":"Class","name_pattern":".*Controller$"}
endpoints|@(Get|Post|Put|Delete|Patch)\(|search_graph|{"label":"Function","name_pattern":".*(Get|Post|Put|Delete|Patch).*"}
services|@Injectable\(\)|search_graph|{"label":"Class","name_pattern":".*Service$"}
dto-validation|class-validator|search_code|{"pattern":"class-validator"}
dead-code|TODO|search_graph|{"label":"Function","relationship":"CALLS","direction":"inbound","max_degree":0,"exclude_entry_points":true}
EOF
      ;;
    express) cat <<'EOF'
route-handlers|app\.(get|post|put|delete|patch)\(|search_graph|{"label":"Function","name_pattern":".*Handler"}
middleware|function ?\(req, ?res|search_graph|{"label":"Function","name_pattern":".*middleware.*"}
http-calls|fetch\(|axios\.|query_graph|{"query":"MATCH (a)-[r:HTTP_CALLS]->(b) RETURN a.name, b.name LIMIT 100"}
db-queries|\.query\(|search_graph|{"label":"Function","name_pattern":".*[Qq]uery.*"}
dead-code|TODO|search_graph|{"label":"Function","relationship":"CALLS","direction":"inbound","max_degree":0,"exclude_entry_points":true}
EOF
      ;;
    symfony) cat <<'EOF'
controllers|class .*Controller\b|search_graph|{"label":"Class","name_pattern":".*Controller$"}
routes|#\[Route\(|@Route\(|search_graph|{"label":"Route"}
services|class .*Service\b|search_graph|{"label":"Class","name_pattern":".*Service$"}
doctrine-entities|#\[ORM\\|@ORM\\Entity|search_graph|{"label":"Class","name_pattern":".*Entity.*"}
dead-code|TODO|search_graph|{"label":"Function","relationship":"CALLS","direction":"inbound","max_degree":0,"exclude_entry_points":true}
EOF
      ;;
    laravel) cat <<'EOF'
routes|Route::(get|post|put|delete)|search_graph|{"label":"Route"}
controllers|class .*Controller\b|search_graph|{"label":"Class","name_pattern":".*Controller$"}
eloquent-models|extends Model\b|search_graph|{"label":"Class","name_pattern":".*Model.*"}
migrations|Schema::create|search_code|{"pattern":"Schema::create"}
dead-code|TODO|search_graph|{"label":"Function","relationship":"CALLS","direction":"inbound","max_degree":0,"exclude_entry_points":true}
EOF
      ;;
    django) cat <<'EOF'
urls|path\(.*views|search_graph|{"label":"Route"}
class-views|class .*View\b|search_graph|{"label":"Class","name_pattern":".*View$"}
models|class .*\(models\.Model\)|search_graph|{"label":"Class","name_pattern":".*Model.*"}
querysets|\.objects\.(filter|get|all)|search_graph|{"label":"Function","name_pattern":".*query.*"}
dead-code|TODO|search_graph|{"label":"Function","relationship":"CALLS","direction":"inbound","max_degree":0,"exclude_entry_points":true}
EOF
      ;;
    flask) cat <<'EOF'
routes|@app\.route|@.*\.route|search_graph|{"label":"Route"}
views|def .*\(.*request|search_graph|{"label":"Function","name_pattern":".*view.*"}
http-calls|requests\.(get|post|put|delete)|query_graph|{"query":"MATCH (a)-[r:HTTP_CALLS]->(b) RETURN a.name, b.name LIMIT 100"}
main-entry|if __name__|search_code|{"pattern":"if __name__"}
dead-code|TODO|search_graph|{"label":"Function","relationship":"CALLS","direction":"inbound","max_degree":0,"exclude_entry_points":true}
EOF
      ;;
    go) cat <<'EOF'
http-handlers|func.*ResponseWriter.*Request|search_graph|{"label":"Function","name_pattern":".*Handler"}
routes|r\.(GET|POST|PUT|DELETE)|mux\.HandleFunc|search_graph|{"label":"Route"}
goroutines|go func\(|search_code|{"pattern":"go func("}
sql-queries|\.Query(Context)?\(|\.Exec(Context)?\(|search_graph|{"label":"Function","name_pattern":".*Query.*"}
dead-code|TODO|search_graph|{"label":"Function","relationship":"CALLS","direction":"inbound","max_degree":0,"exclude_entry_points":true}
EOF
      ;;
    rust) cat <<'EOF'
handlers|async fn .*Request|search_graph|{"label":"Function","name_pattern":".*handler.*"}
routes|\.route\(|search_graph|{"label":"Route"}
unsafe-blocks|unsafe \{|search_code|{"pattern":"unsafe {"}
sqlx-queries|sqlx::query|search_graph|{"label":"Function","name_pattern":".*query.*"}
dead-code|TODO|search_graph|{"label":"Function","relationship":"CALLS","direction":"inbound","max_degree":0,"exclude_entry_points":true}
EOF
      ;;
    *) cat <<'EOF'
all-handlers|Handler|search_graph|{"label":"Function","name_pattern":".*Handler"}
all-routes|Route|search_graph|{"label":"Route"}
high-fanout|.|search_graph|{"label":"Function","relationship":"CALLS","direction":"outbound","min_degree":10}
http-edges|fetch\(|http\.|query_graph|{"query":"MATCH (a)-[r:HTTP_CALLS]->(b) RETURN a.name, b.name LIMIT 100"}
dead-code|TODO|search_graph|{"label":"Function","relationship":"CALLS","direction":"inbound","max_degree":0,"exclude_entry_points":true}
EOF
      ;;
  esac
}

# Load queries into array (bash 3.2 compatible — no mapfile)
Q=()
while IFS= read -r line; do
  [ -z "$line" ] && continue
  Q+=("$line")
done < <(queries_for "$STACK")

# --- output helpers ---------------------------------------------------------

if [ -t 1 ] && [ "$MARKDOWN" -eq 0 ]; then
  C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'; C_GRAY=$'\033[90m'
  C_BOLD=$'\033[1m';   C_DIM=$'\033[2m';     C_RESET=$'\033[0m'
else
  C_GREEN= C_YELLOW= C_GRAY= C_BOLD= C_DIM= C_RESET=
fi

human_n() {
  awk -v n="${1:-0}" 'BEGIN{
    if (n+0 >= 1000000)      printf "%.1f M", n/1000000
    else if (n+0 >= 1000)    printf "%.1f K", n/1000
    else                     printf "%d",     n
  }'
}

C_RED=$'\033[31m'
[ -z "${C_GRAY:-}" ] && C_RED=

color_pct() {
  local p="$1"
  case "$p" in
    n/a|tiny)         printf '%s%s%s' "$C_GRAY"   "$p" "$C_RESET" ;;
    -*)               printf '%s%s%s' "$C_RED"    "$p" "$C_RESET" ;;
    100.0%|99.*%)     printf '%s%s%s' "$C_GREEN"  "$p" "$C_RESET" ;;
    9[0-8].*%)        printf '%s%s%s' "$C_GREEN"  "$p" "$C_RESET" ;;
    [5-8][0-9].*%)    printf '%s%s%s' "$C_YELLOW" "$p" "$C_RESET" ;;
    *)                printf '%s'                  "$p"           ;;
  esac
}

est_tokens() { local n; n=$(wc -c); echo $(( n / 4 )); }

run_grep() {
  ( cd "$ROOT" && grep -rIEn --exclude-dir=node_modules --exclude-dir=.git \
                              --exclude-dir=vendor --exclude-dir=dist \
                              --exclude-dir=.next --exclude-dir=build "$1" . ) \
    2>/dev/null | est_tokens
}
run_cbm() {
  "$CBM" cli "$1" "$2" 2>&1 1>/dev/null | grep -v '^level=' | est_tokens
}

# --- run queries, collect rows ----------------------------------------------

declare -a ROWS=()
TOTAL_RAW=0; TOTAL_CBM=0; MATCHED=0
for row in "${Q[@]}"; do
  IFS='|' read -r name pat tool args <<<"$row"
  raw=$(run_grep "$pat");  raw="${raw:-0}"
  cbm=$(run_cbm "$tool" "$args"); cbm="${cbm:-0}"
  if [ "$raw" -eq 0 ]; then
    pct="n/a"
  elif [ "$raw" -lt 100 ]; then
    # Raw sample too small to be a meaningful comparison; CBM overhead dominates.
    pct="tiny"
  else
    pct=$(awk -v r="$raw" -v c="$cbm" 'BEGIN{ printf "%.1f%%", 100*(1 - c/r) }')
    MATCHED=$((MATCHED+1))
  fi
  ROWS+=("$name|$raw|$cbm|$pct")
  TOTAL_RAW=$((TOTAL_RAW + raw))
  TOTAL_CBM=$((TOTAL_CBM + cbm))
done

# --- emit -------------------------------------------------------------------

if [ "$MARKDOWN" -eq 1 ]; then
  echo "| query | raw tokens | cbm tokens | reduction |"
  echo "|---|---:|---:|---:|"
  for r in "${ROWS[@]}"; do
    IFS='|' read -r n raw cbm pct <<<"$r"
    printf "| %s | %s | %s | %s |\n" "$n" "$raw" "$cbm" "$pct"
  done
  exit 0
fi

echo
printf '%s scc-mcp benchmark %s· codebase-memory-mcp vs grep%s\n' \
  "$C_BOLD" "$C_DIM" "$C_RESET"
printf '%s target:%s %s\n' "$C_DIM" "$C_RESET" "$ROOT_ABS"
printf '%s stack: %s%s%s%s\n' "$C_DIM" "$C_BOLD" "$STACK" "$C_RESET" \
  "$([ -n "$FORCED_STACK" ] && echo " (forced via --stack)" || echo " (auto-detected)")"
echo

printf '  %-22s %10s %10s %12s\n' "query" "raw" "cbm" "reduction"
printf '  %s\n' "──────────────────────────────────────────────────────────"
for r in "${ROWS[@]}"; do
  IFS='|' read -r n raw cbm pct <<<"$r"
  printf '  %-22s %10s %10s %12b\n' \
    "$n" "$(human_n "$raw")" "$(human_n "$cbm")" "$(color_pct "$pct")"
done
printf '  %s\n' "──────────────────────────────────────────────────────────"

if [ "$TOTAL_RAW" -gt 0 ]; then
  TOTAL_PCT=$(awk -v r="$TOTAL_RAW" -v c="$TOTAL_CBM" \
    'BEGIN{ printf "%.1f%%", 100*(1 - c/r) }')
else
  TOTAL_PCT="n/a"
fi
SAVED=$((TOTAL_RAW - TOTAL_CBM))
[ "$SAVED" -lt 0 ] && SAVED=0

printf '  %s%-22s %10s %10s %12b%s\n' \
  "$C_BOLD" "TOTAL" "$(human_n "$TOTAL_RAW")" "$(human_n "$TOTAL_CBM")" "$(color_pct "$TOTAL_PCT")" "$C_RESET"
echo
printf '  %smatched queries:%s %d / %d  %s(others returned 0 raw hits)%s\n' \
  "$C_DIM" "$C_RESET" "$MATCHED" "${#Q[@]}" "$C_DIM" "$C_RESET"
printf '  %snet savings:%s     %s tokens\n' \
  "$C_DIM" "$C_RESET" "$(human_n "$SAVED")"
echo
