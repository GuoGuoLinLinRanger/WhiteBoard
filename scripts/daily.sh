#!/usr/bin/env bash
# Daily GitHub activity bot.
# Priority:
#   1) If queue/ has files, "reveal" 1-4 of them into the repo (one realistic commit each).
#   2) Otherwise, fall back to a small activity.log change.
# Scoped git adds only -- never `git add -A` on the whole tree.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

QUEUE_DIR="queue"
LOG="activity.log"

# Occasionally skip a day so the graph isn't suspiciously perfect.
# ~5% chance => roughly 1-2 missed days per month. (Manual runs still skip too.)
SKIP_CHANCE=5
if [ "$(( RANDOM % 100 ))" -lt "$SKIP_CHANCE" ]; then
  echo "rest day -> skipping commits today"
  exit 0
fi

# Build a plausible commit message from a file's name/extension.
realistic_msg() {
  local f="$1" base name ext
  base="$(basename "$f")"
  name="${base%.*}"
  ext="${base##*.}"
  [ "$ext" = "$base" ] && ext=""
  case "$ext" in
    js|ts|jsx|tsx|mjs|cjs) echo "feat: add ${name} module" ;;
    py)                    echo "feat: implement ${name}" ;;
    go|rs|java|c|cpp|h)    echo "feat: add ${name}" ;;
    css|scss|less)         echo "style: add ${name} styles" ;;
    html|htm)              echo "feat: add ${name} page" ;;
    md|txt|rst)            echo "docs: add ${name} notes" ;;
    json|toml|yml|yaml|ini|cfg|conf) echo "chore: add ${name} config" ;;
    png|jpg|jpeg|svg|gif|ico|woff|woff2|ttf) echo "chore: add ${base} asset" ;;
    sh|ps1|bat)            echo "chore: add ${name} script" ;;
    *)                     echo "chore: add ${base}" ;;
  esac
}

# How many commits to make today (3-8), for a fuller, organic-looking graph.
MAX_PER_DAY=$(( (RANDOM % 6) + 3 ))

mapfile -t files < <(find "$QUEUE_DIR" -type f 2>/dev/null | LC_ALL=C sort | head -n "$MAX_PER_DAY")

if [ "${#files[@]}" -gt 0 ]; then
  for src in "${files[@]}"; do
    rel="${src#"$QUEUE_DIR"/}"     # path within the queue = final destination
    dest="$rel"
    mkdir -p "$(dirname "$dest")"
    if ! git mv "$src" "$dest" 2>/dev/null; then
      mv "$src" "$dest"
      git add "$dest" "$src" 2>/dev/null || git add "$dest"
    fi
    git commit -q -m "$(realistic_msg "$rel")"
    echo "revealed: $dest"
  done
  # Tidy any now-empty queue folders (git doesn't track empty dirs).
  find "$QUEUE_DIR" -type d -empty -delete 2>/dev/null || true
else
  # Queue empty: make MAX_PER_DAY log commits so the day still looks active.
  for i in $(seq 1 "$MAX_PER_DAY"); do
    echo "$(date -u '+%Y-%m-%dT%H:%M:%SZ') - update #$i" >> "$LOG"
    git add "$LOG"
    git commit -q -m "chore: update activity log ($(date -u '+%Y-%m-%d') #$i)"
  done
  echo "queue empty -> committed $MAX_PER_DAY log fallbacks"
fi

git push
