#!/usr/bin/env bash
set -euo pipefail

# Capture PR context: size check, diff (truncated), description.
# Inputs (env vars): GH_TOKEN, REPO, PR_NUMBER, MAX_FILES, MAX_DIFF_LINES, MAX_DIFF_BYTES, INCLUDE_PR_DESCRIPTION
# Outputs (GITHUB_OUTPUT): file_count
# Outputs (files): /tmp/pr-diff.txt, /tmp/pr-description.txt

# --- PR size guard ---
FILE_COUNT=$(gh pr view "$PR_NUMBER" --repo "$REPO" --json files --jq '.files | length')
echo "file_count=$FILE_COUNT" >> "$GITHUB_OUTPUT"

if [ "$FILE_COUNT" -gt "$MAX_FILES" ]; then
  gh pr comment "$PR_NUMBER" --repo "$REPO" \
    --body "⚠️ PR too large for automated review ($FILE_COUNT files, limit: $MAX_FILES). Please split into smaller PRs or review manually." || true
  echo "::notice::Review skipped — PR has $FILE_COUNT files (limit: $MAX_FILES)"
  echo "skipped=true" >> "$GITHUB_OUTPUT"
  exit 0
fi

# --- Capture diff ---
gh pr diff "$PR_NUMBER" --repo "$REPO" > /tmp/pr-diff.txt

# Truncate by line count
LINES=$(wc -l < /tmp/pr-diff.txt)
if [ "$LINES" -gt "$MAX_DIFF_LINES" ]; then
  head -"$MAX_DIFF_LINES" /tmp/pr-diff.txt > /tmp/pr-diff-truncated.txt
  echo "" >> /tmp/pr-diff-truncated.txt
  echo "... [diff truncated — $LINES total lines, showing first $MAX_DIFF_LINES. Use Read tool on specific files for full context.]" >> /tmp/pr-diff-truncated.txt
  mv /tmp/pr-diff-truncated.txt /tmp/pr-diff.txt
fi

# Truncate by byte size
BYTES=$(wc -c < /tmp/pr-diff.txt | tr -d ' ')
if [ "$BYTES" -gt "$MAX_DIFF_BYTES" ]; then
  head -c "$MAX_DIFF_BYTES" /tmp/pr-diff.txt > /tmp/pr-diff-truncated.txt
  echo "" >> /tmp/pr-diff-truncated.txt
  echo "... [diff truncated — ${BYTES} bytes total, showing first $MAX_DIFF_BYTES. Use Read tool on specific files for full context.]" >> /tmp/pr-diff-truncated.txt
  mv /tmp/pr-diff-truncated.txt /tmp/pr-diff.txt
fi

echo "::notice::PR diff captured ($LINES lines, $(wc -c < /tmp/pr-diff.txt | tr -d ' ') bytes)"

# --- Capture PR description ---
if [ "$INCLUDE_PR_DESCRIPTION" = "true" ]; then
  gh pr view "$PR_NUMBER" --repo "$REPO" \
    --json title,body --jq '"# " + .title + "\n\n" + (.body // "")' \
    > /tmp/pr-description.txt 2>/dev/null || : > /tmp/pr-description.txt
  echo "::notice::PR description captured ($(wc -c < /tmp/pr-description.txt | tr -d ' ') bytes)"
else
  : > /tmp/pr-description.txt
fi
