#!/usr/bin/env bash
# Copy a source project into queue/ so the daily bot can reveal it bit by bit.
# Excludes secrets, build junk, and VCS metadata. Review the result before committing!
# Usage: scripts/prepare-queue.sh <source-dir> [dest-name]
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

SRC="${1:?usage: prepare-queue.sh <source-dir> [dest-name]}"
DEST_NAME="${2:-$(basename "$SRC")}"
OUT="queue/$DEST_NAME"

[ -d "$SRC" ] || { echo "source not found: $SRC" >&2; exit 1; }
mkdir -p "$OUT"

# Patterns to skip (secrets + noise). Case-insensitive match on the full path.
SKIP_RE='(/\.git/|/node_modules/|/\.venv/|/venv/|/__pycache__/|/\.temp/|/dist/|/build/|\.env($|\.)|\.local\.|(^|/)secrets?|credential|\.pem$|\.key$|id_rsa|\.p12$|\.pfx$|\.keystore$)'

copied=0; skipped=0
while IFS= read -r -d '' f; do
  rel="${f#"$SRC"/}"
  if echo "/$rel" | grep -qiE "$SKIP_RE"; then
    skipped=$((skipped+1)); continue
  fi
  mkdir -p "$OUT/$(dirname "$rel")"
  cp "$f" "$OUT/$rel"
  copied=$((copied+1))
done < <(find "$SRC" -type f -print0)

echo "Prepared queue/$DEST_NAME : copied=$copied skipped(secret/junk)=$skipped"
echo "Now REVIEW the files, then: git add queue/$DEST_NAME && git commit && git push"
echo "After that the daily bot will reveal them a few at a time."
