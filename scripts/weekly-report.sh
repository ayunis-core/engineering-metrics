#!/usr/bin/env bash
# Weekly Engineering Metrics Report
# Collects PR size, cycle time, time to first review, deployment frequency, and type distribution
set -euo pipefail

REPO="${GITHUB_REPOSITORY}"
DAYS="${1:-7}"
SINCE=$(date -u -d "-${DAYS} days" '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || date -u -v-${DAYS}d '+%Y-%m-%dT%H:%M:%SZ')

echo "## 📊 Engineering Metrics — $(date -u '+%Y-%m-%d')"
echo ""
echo "**Repository:** \`$REPO\` | **Period:** last $DAYS days"
echo ""

# ============================================================
# Fetch merged PRs
# ============================================================
MERGED_PRS=$(gh pr list --repo "$REPO" --state merged --json number,additions,deletions,title,headRefName,createdAt,mergedAt,mergedBy --limit 200 \
  | jq --arg since "$SINCE" '[.[] | select(.mergedAt >= $since)]')

PR_COUNT=$(echo "$MERGED_PRS" | jq 'length')

if [ "$PR_COUNT" -eq 0 ]; then
  echo "No PRs merged in the last $DAYS days."
  exit 0
fi

echo "### Summary"
echo ""
echo "**$PR_COUNT PRs merged** in the last $DAYS days."
echo ""

# ============================================================
# 1. PR Size
# ============================================================
SIZE_DATA=$(echo "$MERGED_PRS" | jq '[.[] | {
  number: .number,
  total: (.additions + .deletions),
  additions: .additions,
  deletions: .deletions
}]')

AVG_SIZE=$(echo "$SIZE_DATA" | jq '[.[].total] | add / length | round')
MEDIAN_SIZE=$(echo "$SIZE_DATA" | jq '[.[].total] | sort | if length % 2 == 0 then (.[length/2 - 1] + .[length/2]) / 2 else .[length/2 | floor] end | round')
MAX_SIZE=$(echo "$SIZE_DATA" | jq '[.[].total] | max')
MIN_SIZE=$(echo "$SIZE_DATA" | jq '[.[].total] | min')

SIZE_S=$(echo "$SIZE_DATA" | jq '[.[] | select(.total <= 50)] | length')
SIZE_M=$(echo "$SIZE_DATA" | jq '[.[] | select(.total > 50 and .total <= 200)] | length')
SIZE_L=$(echo "$SIZE_DATA" | jq '[.[] | select(.total > 200 and .total <= 400)] | length')
SIZE_XL=$(echo "$SIZE_DATA" | jq '[.[] | select(.total > 400)] | length')

echo "### 1. PR Size"
echo ""
echo "| Metric | Value |"
echo "|--------|-------|"
echo "| Average | **$AVG_SIZE lines** |"
echo "| Median | **$MEDIAN_SIZE lines** |"
echo "| Min / Max | $MIN_SIZE / $MAX_SIZE |"
echo ""
echo "| Size | Count | % |"
echo "|------|-------|---|"
printf "| S (≤50) | %d | %d%% |\n" "$SIZE_S" "$((SIZE_S * 100 / PR_COUNT))"
printf "| M (51–200) | %d | %d%% |\n" "$SIZE_M" "$((SIZE_M * 100 / PR_COUNT))"
printf "| L (201–400) | %d | %d%% |\n" "$SIZE_L" "$((SIZE_L * 100 / PR_COUNT))"
printf "| XL (>400) | %d | %d%% |\n" "$SIZE_XL" "$((SIZE_XL * 100 / PR_COUNT))"
echo ""

# ============================================================
# 2. Cycle Time (first commit → merged)
# Broken down into coding time and review time.
# ============================================================

format_hours() {
  local h=$1
  if [ "$h" -lt 0 ]; then h=0; fi
  if [ "$h" -lt 24 ]; then
    echo "${h}h"
  else
    echo "$((h / 24))d $((h % 24))h"
  fi
}

CYCLE_HOURS=""
CODING_HOURS=""
REVIEW_HOURS_CT=""
CYCLE_COUNT=0

for PR_NUM in $(echo "$MERGED_PRS" | jq -r '.[].number'); do
  PR_CREATED=$(echo "$MERGED_PRS" | jq -r --argjson n "$PR_NUM" '.[] | select(.number == $n) | .createdAt')
  PR_MERGED=$(echo "$MERGED_PRS" | jq -r --argjson n "$PR_NUM" '.[] | select(.number == $n) | .mergedAt')

  # Get first commit on the PR
  FIRST_COMMIT=$(gh api "repos/$REPO/pulls/$PR_NUM/commits" --jq '.[0].commit.committer.date' 2>/dev/null || echo "")

  if [ -n "$FIRST_COMMIT" ] && [ "$FIRST_COMMIT" != "null" ]; then
    # Full cycle: first commit → merged
    TOTAL_H=$(jq -n --arg fc "$FIRST_COMMIT" --arg m "$PR_MERGED" \
      '((($m | fromdateiso8601) - ($fc | fromdateiso8601)) / 3600) | round')
    # Coding time: first commit → PR opened
    CODE_H=$(jq -n --arg fc "$FIRST_COMMIT" --arg c "$PR_CREATED" \
      '((($c | fromdateiso8601) - ($fc | fromdateiso8601)) / 3600) | round')
    # Review time: PR opened → merged
    REV_H=$(jq -n --arg c "$PR_CREATED" --arg m "$PR_MERGED" \
      '((($m | fromdateiso8601) - ($c | fromdateiso8601)) / 3600) | round')

    if [ "$TOTAL_H" -ge 0 ]; then
      CYCLE_HOURS="$CYCLE_HOURS $TOTAL_H"
      CODING_HOURS="$CODING_HOURS $CODE_H"
      REVIEW_HOURS_CT="$REVIEW_HOURS_CT $REV_H"
      CYCLE_COUNT=$((CYCLE_COUNT + 1))
    fi
  fi
done

calc_stats() {
  local data="$1"
  local avg med p90
  avg=$(echo "$data" | tr ' ' '\n' | awk 'NF{s+=$1;n++} END{if(n>0) print int(s/n); else print 0}')
  med=$(echo "$data" | tr ' ' '\n' | sort -n | awk 'NF{a[NR]=$1} END{if(NR%2==0) print int((a[NR/2]+a[NR/2+1])/2); else print a[int(NR/2)+1]}')
  p90=$(echo "$data" | tr ' ' '\n' | sort -n | awk 'NF{a[NR]=$1} END{print a[int(NR*0.9)+1]}')
  echo "$avg $med $p90"
}

echo "### 2. Cycle Time (first commit → merged)"
echo ""

if [ "$CYCLE_COUNT" -gt 0 ]; then
  read CYC_AVG CYC_MED CYC_P90 <<< "$(calc_stats "$CYCLE_HOURS")"
  read CODE_AVG CODE_MED CODE_P90 <<< "$(calc_stats "$CODING_HOURS")"
  read REVCT_AVG REVCT_MED REVCT_P90 <<< "$(calc_stats "$REVIEW_HOURS_CT")"

  echo "| Phase | Avg | Median | p90 |"
  echo "|-------|-----|--------|-----|"
  echo "| Coding (first commit → PR opened) | **$(format_hours "$CODE_AVG")** | $(format_hours "$CODE_MED") | $(format_hours "$CODE_P90") |"
  echo "| Review (PR opened → merged) | **$(format_hours "$REVCT_AVG")** | $(format_hours "$REVCT_MED") | $(format_hours "$REVCT_P90") |"
  echo "| **Total cycle** | **$(format_hours "$CYC_AVG")** | $(format_hours "$CYC_MED") | $(format_hours "$CYC_P90") |"
else
  echo "No commit data available for this period."
fi
echo ""

# ============================================================
# 3. Time to First Review
# ============================================================
echo "### 3. Time to First Review"
echo ""

REVIEW_TIMES=""
REVIEW_COUNT=0
REVIEW_TOTAL_HOURS=0

for PR_NUM in $(echo "$MERGED_PRS" | jq -r '.[].number'); do
  PR_CREATED=$(echo "$MERGED_PRS" | jq -r --argjson n "$PR_NUM" '.[] | select(.number == $n) | .createdAt')

  # Get first review timestamp
  FIRST_REVIEW=$(gh api "repos/$REPO/pulls/$PR_NUM/reviews" --jq '.[0].submitted_at' 2>/dev/null || echo "")

  if [ -n "$FIRST_REVIEW" ] && [ "$FIRST_REVIEW" != "null" ]; then
    # Calculate hours using jq for date math
    HOURS=$(jq -n --arg created "$PR_CREATED" --arg review "$FIRST_REVIEW" \
      '((($review | fromdateiso8601) - ($created | fromdateiso8601)) / 3600) | round')

    if [ "$HOURS" -ge 0 ]; then
      REVIEW_TIMES="$REVIEW_TIMES $HOURS"
      REVIEW_COUNT=$((REVIEW_COUNT + 1))
      REVIEW_TOTAL_HOURS=$((REVIEW_TOTAL_HOURS + HOURS))
    fi
  fi
done

if [ "$REVIEW_COUNT" -gt 0 ]; then
  AVG_REVIEW=$((REVIEW_TOTAL_HOURS / REVIEW_COUNT))
  MEDIAN_REVIEW=$(echo "$REVIEW_TIMES" | tr ' ' '\n' | sort -n | awk '{a[NR]=$1} END{if(NR%2==0) print int((a[NR/2]+a[NR/2+1])/2); else print a[int(NR/2)+1]}')
  P90_REVIEW=$(echo "$REVIEW_TIMES" | tr ' ' '\n' | sort -n | awk '{a[NR]=$1} END{print a[int(NR*0.9)+1]}')

  echo "| Metric | Value |"
  echo "|--------|-------|"
  echo "| Average | **$(format_hours "$AVG_REVIEW")** |"
  echo "| Median | **$(format_hours "$MEDIAN_REVIEW")** |"
  echo "| p90 | $(format_hours "${P90_REVIEW:-0}") |"
  echo "| PRs with reviews | $REVIEW_COUNT / $PR_COUNT |"
else
  echo "No review data available for this period."
fi
echo ""

# ============================================================
# 4. Deployment Frequency
# ============================================================
echo "### 4. Deployment Frequency"
echo ""

# Count merges to main as deployments (most common proxy)
DEPLOYS=$PR_COUNT
DEPLOYS_PER_DAY=$(jq -n "$DEPLOYS / $DAYS * 10 | round | . / 10")

# Also check for deployment workflow runs
DEPLOY_RUNS=$(gh run list --repo "$REPO" --workflow deploy --limit 200 --json createdAt,conclusion \
  --jq "[.[] | select(.createdAt >= \"$SINCE\" and .conclusion == \"success\")] | length" 2>/dev/null || echo "0")

if [ "$DEPLOY_RUNS" -gt 0 ] && [ "$DEPLOY_RUNS" != "0" ]; then
  DEPLOY_RUNS_PER_DAY=$(jq -n "$DEPLOY_RUNS / $DAYS * 10 | round | . / 10")
  echo "| Metric | Value |"
  echo "|--------|-------|"
  echo "| Merges to main | **$DEPLOYS** ($DEPLOYS_PER_DAY/day) |"
  echo "| Deploy workflow runs | **$DEPLOY_RUNS** ($DEPLOY_RUNS_PER_DAY/day) |"
else
  echo "| Metric | Value |"
  echo "|--------|-------|"
  echo "| Merges to main | **$DEPLOYS** ($DEPLOYS_PER_DAY/day) |"
fi
echo ""

# ============================================================
# 5. Type Distribution
# ============================================================
echo "### 5. Type Distribution"
echo ""

TYPE_DATA=$(echo "$MERGED_PRS" | jq -r '
  [.[] | {
    title: .title,
    branch: .headRefName
  } | .branch_lower = (.branch | ascii_downcase) | .title_lower = (.title | ascii_downcase) |
  if   (.branch_lower | test("^(feat|feature)[/_-]")) or (.title_lower | test("^(feat|feature)[:/]")) or (.branch_lower | test("^[0-9]{2}-[0-9]{2}-(feat|feature)[/_-]"))
  then "feature"
  elif (.branch_lower | test("^(fix|bugfix|hotfix)[/_-]")) or (.title_lower | test("^(fix|bugfix)[:/]")) or (.branch_lower | test("^[0-9]{2}-[0-9]{2}-(fix|bugfix)[/_-]"))
  then "fix"
  elif (.branch_lower | test("^refactor[/_-]")) or (.title_lower | test("^refactor[:/]")) or (.branch_lower | test("^[0-9]{2}-[0-9]{2}-refactor[/_-]"))
  then "refactor"
  elif (.branch_lower | test("^chore[/_-]")) or (.title_lower | test("^chore[:/]")) or (.branch_lower | test("^[0-9]{2}-[0-9]{2}-chore[/_-]"))
  then "chore"
  elif (.branch_lower | test("^ci[/_-]")) or (.title_lower | test("^ci[:/]")) or (.branch_lower | test("^[0-9]{2}-[0-9]{2}-ci[/_-]"))
  then "ci"
  elif (.branch_lower | test("^docs[/_-]")) or (.title_lower | test("^docs[:/]")) or (.branch_lower | test("^[0-9]{2}-[0-9]{2}-docs[/_-]"))
  then "docs"
  else "other"
  end
  ] | group_by(.) | map({type: .[0], count: length}) | sort_by(-.count)')

echo "| Type | Count | % |"
echo "|------|-------|---|"
echo "$TYPE_DATA" | jq -r --argjson total "$PR_COUNT" '.[] | "| \(.type) | \(.count) | \(.count * 100 / $total | round)% |"'
echo ""

# ============================================================
# Top 5 largest PRs
# ============================================================
echo "### 📋 Largest PRs"
echo ""
echo "| PR | Lines | Type | Author |"
echo "|----|-------|------|--------|"

echo "$MERGED_PRS" | jq -r '
  [.[] | {
    number: .number,
    total: (.additions + .deletions),
    title: .title,
    author: .mergedBy.login,
    branch: .headRefName
  }] | sort_by(-.total) | .[0:5] | .[] |
  "| [#\(.number)](../pull/\(.number)) \(.title | .[0:50]) | \(.total) | — | \(.author) |"'

echo ""
echo "---"
echo "*Generated by [engineering-metrics](https://github.com/ayunis-core/engineering-metrics)*"
