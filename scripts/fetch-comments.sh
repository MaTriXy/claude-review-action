#!/usr/bin/env bash
set -euo pipefail

# Fetch author comments since last Claude review for reconciliation context.
# Inputs (env vars): GH_TOKEN, REPO, PR_NUMBER, LAST_REVIEW_DATE, TRIGGER_PHRASE
# Outputs: /tmp/author-comments.txt

# Get PR author login
PR_AUTHOR=$(gh pr view "$PR_NUMBER" --repo "$REPO" --json author --jq '.author.login')

# Build jq filter — exclude trigger phrase comments if phrase is non-empty
if [ -n "$TRIGGER_PHRASE" ]; then
  TRIGGER_FILTER="and (.body | test(\"${TRIGGER_PHRASE}\") | not)"
else
  TRIGGER_FILTER=""
fi

# Fetch PR-level comments by author since last review
PR_COMMENTS=$(gh api "repos/${REPO}/issues/${PR_NUMBER}/comments" \
  --jq "[.[] | select(.user.login == \"${PR_AUTHOR}\" and .created_at > \"${LAST_REVIEW_DATE}\" ${TRIGGER_FILTER})] | map(\"**@\" + .user.login + \"** (\" + .created_at + \"):\\n\" + .body) | join(\"\\n\\n---\\n\\n\")" 2>/dev/null || echo "")

# Fetch inline review comments by author since last review
INLINE_COMMENTS=$(gh api "repos/${REPO}/pulls/${PR_NUMBER}/comments" \
  --jq "[.[] | select(.user.login == \"${PR_AUTHOR}\" and .created_at > \"${LAST_REVIEW_DATE}\")] | map(\"**@\" + .user.login + \"** on \`\" + .path + \":\" + (.line // .original_line // \"?\" | tostring) + \"\` (\" + .created_at + \"):\\n\" + .body) | join(\"\\n\\n---\\n\\n\")" 2>/dev/null || echo "")

# Write to file
: > /tmp/author-comments.txt
if [ -n "$PR_COMMENTS" ]; then
  echo "### PR comments:" >> /tmp/author-comments.txt
  echo "" >> /tmp/author-comments.txt
  echo "$PR_COMMENTS" >> /tmp/author-comments.txt
  echo "" >> /tmp/author-comments.txt
fi
if [ -n "$INLINE_COMMENTS" ]; then
  echo "### Inline review comments:" >> /tmp/author-comments.txt
  echo "" >> /tmp/author-comments.txt
  echo "$INLINE_COMMENTS" >> /tmp/author-comments.txt
  echo "" >> /tmp/author-comments.txt
fi

# Truncate if too large (keep under ~3000 tokens ≈ 12000 chars)
if [ -s /tmp/author-comments.txt ]; then
  CHAR_COUNT=$(wc -c < /tmp/author-comments.txt | tr -d ' ')
  if [ "$CHAR_COUNT" -gt 12000 ]; then
    head -c 12000 /tmp/author-comments.txt > /tmp/author-comments-truncated.txt
    echo "" >> /tmp/author-comments-truncated.txt
    echo "... [author comments truncated — ${CHAR_COUNT} chars total, showing first 12000]" >> /tmp/author-comments-truncated.txt
    mv /tmp/author-comments-truncated.txt /tmp/author-comments.txt
  fi
  echo "::notice::Author comments captured ($(wc -c < /tmp/author-comments.txt | tr -d ' ') bytes)"
else
  echo "::notice::No author comments found since last review"
fi
