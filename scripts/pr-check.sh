#!/usr/bin/env bash
# PR Size Check — labels PRs by size and warns if too large
set -euo pipefail

PR_NUMBER="${1:?Usage: pr-check.sh <pr-number>}"
SIZE_THRESHOLD="${2:-400}"
REPO="${GITHUB_REPOSITORY}"

# Get PR stats
PR_DATA=$(gh pr view "$PR_NUMBER" --repo "$REPO" --json additions,deletions,title,headRefName)
ADDITIONS=$(echo "$PR_DATA" | jq -r '.additions')
DELETIONS=$(echo "$PR_DATA" | jq -r '.deletions')
TITLE=$(echo "$PR_DATA" | jq -r '.title')
BRANCH=$(echo "$PR_DATA" | jq -r '.headRefName')
TOTAL=$((ADDITIONS + DELETIONS))

# --- Size labeling ---
if [ "$TOTAL" -le 50 ]; then
  SIZE_LABEL="size/S"
elif [ "$TOTAL" -le 200 ]; then
  SIZE_LABEL="size/M"
elif [ "$TOTAL" -le 400 ]; then
  SIZE_LABEL="size/L"
else
  SIZE_LABEL="size/XL"
fi

# Ensure label exists (create with color if missing)
declare -A LABEL_COLORS=( ["size/S"]="0e8a16" ["size/M"]="fbca04" ["size/L"]="e99695" ["size/XL"]="d93f0b" )
gh label create "$SIZE_LABEL" --repo "$REPO" --color "${LABEL_COLORS[$SIZE_LABEL]}" --force 2>/dev/null || true

# Remove any existing size labels, then apply new one
for label in "size/S" "size/M" "size/L" "size/XL"; do
  if [ "$label" != "$SIZE_LABEL" ]; then
    gh pr edit "$PR_NUMBER" --repo "$REPO" --remove-label "$label" 2>/dev/null || true
  fi
done
gh pr edit "$PR_NUMBER" --repo "$REPO" --add-label "$SIZE_LABEL"

echo "PR #$PR_NUMBER: +$ADDITIONS -$DELETIONS = $TOTAL lines → $SIZE_LABEL"

# --- Type classification ---
TYPE="other"
LOWER_TITLE=$(echo "$TITLE" | tr '[:upper:]' '[:lower:]')
LOWER_BRANCH=$(echo "$BRANCH" | tr '[:upper:]' '[:lower:]')

for prefix in feat feature fix bugfix refactor chore ci docs; do
  if [[ "$LOWER_BRANCH" =~ ^${prefix}[/_-] ]] || [[ "$LOWER_TITLE" =~ ^${prefix}[:/\ ] ]] || [[ "$LOWER_BRANCH" =~ ^[0-9]{2}-[0-9]{2}-${prefix}[/_-] ]]; then
    case "$prefix" in
      feat|feature) TYPE="feature" ;;
      fix|bugfix)   TYPE="fix" ;;
      refactor)     TYPE="refactor" ;;
      chore)        TYPE="chore" ;;
      ci)           TYPE="ci" ;;
      docs)         TYPE="docs" ;;
    esac
    break
  fi
done

# Apply type label
TYPE_LABEL="type/$TYPE"
gh label create "$TYPE_LABEL" --repo "$REPO" --color "c5def5" --force 2>/dev/null || true
for t in feature fix refactor chore ci docs other; do
  if [ "type/$t" != "$TYPE_LABEL" ]; then
    gh pr edit "$PR_NUMBER" --repo "$REPO" --remove-label "type/$t" 2>/dev/null || true
  fi
done
gh pr edit "$PR_NUMBER" --repo "$REPO" --add-label "$TYPE_LABEL"

echo "PR #$PR_NUMBER: type=$TYPE (branch=$BRANCH)"

# --- Warn if too large ---
if [ "$TOTAL" -gt "$SIZE_THRESHOLD" ]; then
  COMMENT_MARKER="<!-- engineering-metrics-size-warning -->"

  # Check if warning already posted
  EXISTING=$(gh pr view "$PR_NUMBER" --repo "$REPO" --json comments --jq ".comments[].body" | grep -c "$COMMENT_MARKER" || true)

  if [ "$EXISTING" -eq 0 ]; then
    gh pr comment "$PR_NUMBER" --repo "$REPO" --body "${COMMENT_MARKER}
> ⚠️ **Large PR** — This PR changes **$TOTAL lines** (threshold: $SIZE_THRESHOLD).
>
> Large PRs are harder to review, more likely to introduce bugs, and slower to merge.
> Consider breaking this into smaller, focused PRs if possible.
>
> | Additions | Deletions | Total |
> |-----------|-----------|-------|
> | +$ADDITIONS | -$DELETIONS | $TOTAL |"
    echo "Posted size warning comment"
  else
    echo "Size warning already posted, skipping"
  fi
fi
