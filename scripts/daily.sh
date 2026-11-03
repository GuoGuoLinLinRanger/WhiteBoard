#!/usr/bin/env bash
# Daily GitHub activity bot.
# Priority:
#   1) If queue/ has files, "reveal" a few of them into the repo (one realistic commit each).
#   2) Otherwise, make realistic "maintenance" commits on files already in the repo.
# Scoped git adds only -- never `git add -A` on the whole tree.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

QUEUE_DIR="queue"

# Skip exactly 1-2 "rest days" each month, chosen pseudo-randomly but
# deterministically from the month (runner is stateless, and a real skip must
# leave no commit -- so we can't persist a counter). Hash YYYY-MM -> pick days.
YM="$(date -u +%Y-%m)"
TODAY_DOM="$(( 10#$(date -u +%d) ))"
DIM="$(date -u -d "$YM-01 +1 month -1 day" +%d 2>/dev/null || echo 28)"; DIM="$(( 10#$DIM ))"
H="$(printf '%s' "$YM" | md5sum | cut -c1-8)"
HN=$(( 16#$H ))
SKIP_COUNT=$(( 1 + (HN % 2) ))                 # 1 or 2 rest days this month
skip_today=0
for k in $(seq 0 $(( SKIP_COUNT - 1 ))); do
  HK=$(( 16#$(printf '%s-%s' "$YM" "$k" | md5sum | cut -c1-8) ))
  DAY=$(( (HK % DIM) + 1 ))
  [ "$TODAY_DOM" -eq "$DAY" ] && skip_today=1
done
if [ "$skip_today" -eq 1 ]; then
  echo "rest day ($YM day $TODAY_DOM) -> skipping commits today"
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

# Realistic conventional-commit message for an edit to an existing file.
work_msg() {
  local f="$1" base name
  base="$(basename "$f")"
  name="${base%.*}"
  local pool=(
    "refactor: simplify ${name} logic"
    "fix: handle edge case in ${name}"
    "style: clean up formatting in ${name}"
    "chore: minor cleanup in ${name}"
    "perf: small optimization in ${name}"
    "docs: clarify comments in ${name}"
    "refactor: extract helper in ${name}"
    "fix: address lint warning in ${name}"
    "test: tweak coverage around ${name}"
    "chore: tidy ${name}"
  )
  echo "${pool[$(( RANDOM % ${#pool[@]} ))]}"
}

# Apply a tiny, non-breaking in-place change to a file: refresh a managed
# trailing comment (replaced each time, so files never bloat). Comment syntax
# matches the file type so nothing breaks.
maint_touch() {
  local f="$1" base ext open close token stamp tmp
  base="$(basename "$f")"
  ext="${base##*.}"
  case "$ext" in
    css|scss|less) open="/*"; close=" */" ;;
    md)            open="<!--"; close=" -->" ;;
    *)             open="//"; close="" ;;
  esac
  token="last build"                       # stable marker to find/replace prior line
  stamp="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  tmp="$f.bot.tmp"
  grep -v "${token} " "$f" > "$tmp" 2>/dev/null || cp "$f" "$tmp"
  # make sure there's a trailing newline before we append
  if [ -s "$tmp" ] && [ -n "$(tail -c1 "$tmp")" ]; then printf '\n' >> "$tmp"; fi
  printf '%s %s %s%s\n' "$open" "$token" "$stamp" "$close" >> "$tmp"
  mv "$tmp" "$f"
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
  # Queue empty: make realistic "maintenance" commits on files already in the repo,
  # so the activity reads like ongoing work instead of a timestamp log.
  mapfile -t CAND < <(git ls-files \
        '*.ts' '*.tsx' '*.js' '*.jsx' '*.mjs' '*.cjs' '*.css' '*.scss' '*.md' \
      | grep -vE '(^|/)(queue|scripts)/' \
      | grep -vE 'package-lock\.json$')
  if [ "${#CAND[@]}" -eq 0 ]; then
    echo "no candidate files to edit yet; nothing to do today"
    exit 0
  fi
  made=0
  for i in $(seq 1 "$MAX_PER_DAY"); do
    f="${CAND[$(( RANDOM % ${#CAND[@]} ))]}"
    maint_touch "$f"
    git add "$f"
    if git commit -q -m "$(work_msg "$f")"; then made=$(( made + 1 )); fi
  done
  echo "queue empty -> made $made maintenance commits"
fi

git push
