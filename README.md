# Claude Code Review Action

AI-powered code review using Claude. A reusable GitHub Composite Action that handles diff capture, re-review reconciliation, cost tracking, and configurable review authority.

## Quick Start

Add the `claude-review` label to any PR to trigger a review:

```yaml
# .github/workflows/claude-review.yml
name: Claude Code Review
on:
  pull_request:
    types: [labeled]

jobs:
  review:
    runs-on: ubuntu-latest
    if: github.event.label.name == 'claude-review'
    permissions:
      contents: write
      pull-requests: write
      issues: write
      id-token: write
      actions: read
      checks: read
    steps:
      - uses: toriihq/claude-review-action@v1
        with:
          anthropic-api-key: ${{ secrets.ANTHROPIC_API_KEY }}
```

That's it. One required input — everything else has sensible defaults.

## Features

- **3 trigger types** — Label (`claude-review`), `@claude` comment, inline review comment
- **Re-review reconciliation** — Tracks previous findings, author responses, and new commits
- **Relevant commit filtering** — Only flags commits that contribute real changes vs base
- **Configurable review authority** — Comment-only, request-changes, or full (with auto-approve)
- **PR size guard** — Skips reviews for PRs exceeding configurable file limits
- **Diff truncation** — Line and byte limits prevent token overflow
- **Cost tracking** — Appends cost, turns, and model to the review body
- **Review dismissal** — Dismisses previous Claude reviews before posting new ones
- **Typed failure messages** — Distinguishes max-turns, API errors, and missing output
- **Review guide support** — Fetches guide from default branch with PR branch fallback
- **Pure bash** — No TypeScript, no node_modules, no build step

## Inputs

### Required

| Input | Description |
|-------|-------------|
| `anthropic-api-key` | Anthropic API key (from secrets) |

### Review Content

| Input | Default | Description |
|-------|---------|-------------|
| `review-guide-path` | `""` | Path to repo's review guide markdown. Empty = no guide |
| `critical-rules` | `""` | Multiline string injected as BLOCKER-level rules |
| `extra-prompt` | `""` | Appended to end of prompt (custom instructions) |
| `include-pr-description` | `true` | Feed PR title+body into review prompt |
| `context-intro` | `"You are a code reviewer."` | Opening line of prompt (repo identity/context) |

### Limits

| Input | Default | Description |
|-------|---------|-------------|
| `max-files` | `50` | Skip review if PR exceeds this many files |
| `max-diff-lines` | `3000` | Truncate diff after N lines |
| `max-diff-bytes` | `80000` | Truncate diff after N bytes |
| `max-turns` | `30` | Claude conversation turn limit |
| `timeout-minutes` | `20` | Job timeout (informational — set actual timeout on your job) |

### Model & Tools

| Input | Default | Description |
|-------|---------|-------------|
| `model` | `claude-sonnet-4-6` | Claude model to use |
| `allowed-tools` | `Bash,Read,Write,Grep,Glob` | Tools Claude can use during review |

### Review Authority

| Input | Default | Description |
|-------|---------|-------------|
| `review-authority` | `request-changes` | Level: `comment-only`, `request-changes`, or `full` |
| `approve-threshold` | `strict` | For `full` mode: `strict` (zero MEDIUM+) or `normal` (zero HIGH+) |
| `approve-max-files` | `50` | For `full` mode: only approve PRs with <= N files |

### Triggers

| Input | Default | Description |
|-------|---------|-------------|
| `review-label` | `claude-review` | Label name for `label_trigger`. Must match your workflow's `if:` |
| `trigger-phrase` | `@claude` | Comment trigger phrase (excluded from author feedback) |
| `default-branch` | `""` (auto-detect) | Base branch for guide fetch. Empty = auto-detect |

### Behavior

| Input | Default | Description |
|-------|---------|-------------|
| `skip-if-already-reviewed` | `true` | Skip on label trigger if no new commits since last review |
| `include-previous-review` | `true` | Enable re-review reconciliation with previous findings |
| `track-cost` | `true` | Append cost/turns/model to review comment |
| `dismiss-previous-reviews` | `true` | Dismiss old Claude reviews before posting new one |

## Required Permissions

Your workflow job **must** include these permissions:

```yaml
permissions:
  contents: write        # Checkout PR branch, read files
  pull-requests: write   # Post reviews, dismiss reviews, read PR data
  issues: write          # Post comments on PRs (issue_comment API)
  id-token: write        # Required by claude-code-action for auth
  actions: read          # Read workflow run info (for failure URLs)
  checks: read           # Read check status (optional, used by Claude)
```

## Examples

See the [`examples/`](examples/) directory:

- **[minimal.yml](examples/minimal.yml)** — Label trigger only (~20 lines)
- **[standard.yml](examples/standard.yml)** — 3 triggers, review guide, critical rules
- **[advanced.yml](examples/advanced.yml)** — All 20 inputs with explanatory comments

## How It Works

```
resolve-pr.sh        → Normalize PR number + SHA across trigger types
  ↓
actions/checkout@v4  → Checkout the PR branch
  ↓
fetch-guide.sh       → Fetch review guide (default branch + PR fallback)
  ↓
capture-context.sh   → Diff capture, size guard, PR description
  ↓
detect-previous.sh   → Find previous reviews, calculate new commits
  ↓
fetch-comments.sh    → Author comments since last review (if re-review)
  ↓
build-prompt.sh      → Assemble 11-section prompt from all inputs
  ↓
claude-code-action   → Run Claude with assembled prompt
  ↓
post-failure.sh      → Post typed failure message (if failed)
  ↓
report-cost.sh       → Append cost/turns/model to review body
```

## Review Authority Levels

| Level | Behavior |
|-------|----------|
| `comment-only` | Always posts as COMMENT. Advisory only — never blocks PRs. |
| `request-changes` | Posts REQUEST_CHANGES for blockers/high findings, COMMENT for medium, APPROVE for clean. **Default.** |
| `full` | Like `request-changes` but with configurable auto-approve: respects `approve-threshold` and `approve-max-files`. |

## Re-review Reconciliation

When Claude detects a previous review on the same PR:

1. **Finds previous review** via dual API detection (PR reviews + comments fallback)
2. **Filters new commits** to only those contributing real changes vs base branch
3. **Captures author responses** (PR comments + inline comments since last review)
4. **Reconciles findings** — each previous HIGH/BLOCKER is marked FIXED, ACCEPTED, or STILL OPEN
5. **New verdict** reflects reconciliation — only STILL OPEN findings block approval

Set `include-previous-review: false` to disable reconciliation (always full review, no history).

## Migration from Standalone Workflow

If you have an existing 500+ line Claude review workflow:

1. Replace the entire workflow file with the [standard example](examples/standard.yml)
2. Keep your existing `.github/claude-review-guide.md` unchanged
3. Move critical rules from bash heredoc to `critical-rules:` input
4. Test on one PR — verify review quality matches
5. Delete the old workflow steps

## Known Limitations

1. **Review dismissal is best-effort** — Dismissal commands are injected into Claude's prompt, not a separate step. If Claude's API call fails mid-review, old reviews may persist.

2. **Failure type detection** — The action reliably detects `max_turns` failures. API error subtypes (401 vs 429) may not be distinguishable and fall back to a generic message.

3. **Shallow checkout** — Uses `fetch-depth: 1` for speed. Sufficient for Claude's file reads, but `detect-previous.sh` fetches the base branch separately for commit comparison.

## Contributing

Contributions are welcome! This is a pure bash + markdown project — no build step required.

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test by pointing a workflow at your fork: `uses: your-user/claude-review-action@your-branch`
5. Open a pull request

## License

[MIT](LICENSE)
