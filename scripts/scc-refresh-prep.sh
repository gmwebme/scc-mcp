#!/usr/bin/env bash
# /scc-refresh preflight. Bootstraps .scc/, decides full vs incremental, lists
# changed files. Prints a compact report block consumed by the command prompt.
# Never hard-fails: prints what it can and exits 0.
#
# Correctness fixes vs the original:
#  - Renames (R-status) counted once, on the new path.
#  - Submodule pointer updates counted as one change per submodule.
#  - flock around concurrent /scc-refresh invocations.

LIB="$(dirname "${BASH_SOURCE[0]}")/scc-map-lib.sh"
# shellcheck disable=SC1090
. "$LIB" 2>/dev/null || { echo "ROOT=$PWD"; echo "MODE=full"; exit 0; }

ROOT="$(scc_pick_root)"
scc_init_dir "$ROOT"
META="$ROOT/.scc/.map-meta.json"
LOCK="$ROOT/.scc/.refresh.lock"

# Concurrent /scc-refresh would race meta writes. Take a non-blocking lock.
if command -v flock >/dev/null 2>&1; then
  exec 9>"$LOCK"
  if ! flock -n 9; then
    echo "ROOT=$ROOT"
    echo "MODE=full"
    echo "SCC_AVAILABLE=$(scc_have_scc && echo true || echo false)"
    echo "GIT=$(scc_have_git "$ROOT" && echo true || echo false)"
    echo "BASELINE=<locked-by-other-refresh>"
    echo "CURRENT_HEAD=unknown"
    echo "--- CHANGED_FILES ---"
    echo "(another /scc-refresh is in progress — try again in a moment)"
    echo "--- END ---"
    exit 0
  fi
fi

SCC_OK="false"; scc_have_scc && SCC_OK="true"
SEM_HEAD="$(scc_meta_get semantic_git_head "$META")"
read -r CUR_HEAD CUR_HASH <<<"$(scc_content_signal "$ROOT")"

MODE="full"; CHANGED=""
if [ -f "$ROOT/.scc/INDEX.md" ] && [ -n "$SEM_HEAD" ]; then
  if scc_have_git "$ROOT" && [ "$SEM_HEAD" != "nogit" ]; then
    # --name-status preserves R/C/D/A/M and lets us treat renames as one path.
    DIFF_LINES="$(git -C "$ROOT" diff --name-status "$SEM_HEAD" HEAD 2>/dev/null \
      | awk -F'\t' '
          $1 ~ /^R/ { print $3; next }   # rename: new path only
          $1 ~ /^C/ { print $3; next }   # copy:   new path only
          $1 ~ /^[ADMTUX]/ { print $2; next }
        ')"
    # Working-tree status (uncommitted). Rename format: "R  old -> new".
    STATUS_LINES="$(git -C "$ROOT" status --porcelain 2>/dev/null \
      | awk '{
          if ($1 ~ /^R/) { sub(/.*-> /, ""); print; next }
          print $2
        }')"
    # Submodule pointer changes count as one change per submodule.
    SUBM_LINES="$(git -C "$ROOT" submodule status --recursive 2>/dev/null \
      | awk '/^[+\-U]/ { print $2 }')"
    CHANGED="$(printf '%s\n%s\n%s\n' "$DIFF_LINES" "$STATUS_LINES" "$SUBM_LINES" \
      | sort -u | grep -v '^\.scc/' | grep . )"
    CNT="$(printf '%s\n' "$CHANGED" | grep -c . )"
    if [ "$CNT" -gt 0 ] && [ "$CNT" -le 25 ]; then MODE="incremental"; fi
  fi
fi

echo "ROOT=$ROOT"
echo "MODE=$MODE"
echo "SCC_AVAILABLE=$SCC_OK"
echo "GIT=$([ "$CUR_HEAD" = nogit ] && echo false || echo true)"
echo "BASELINE=${SEM_HEAD:-<none>}"
echo "CURRENT_HEAD=${CUR_HEAD}"
echo "--- CHANGED_FILES ---"
[ "$MODE" = "incremental" ] && printf '%s\n' "$CHANGED" || echo "(full rebuild — map every important module)"
echo "--- END ---"
exit 0
