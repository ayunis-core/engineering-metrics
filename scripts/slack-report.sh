#!/usr/bin/env bash
# Generate a Slack Block Kit payload from the weekly metrics markdown report and post it.
set -euo pipefail

REPORT_FILE="${1:?Usage: slack-report.sh <report-markdown-file>}"
REPO="${GITHUB_REPOSITORY}"
REPO_NAME="${REPO#*/}"

if [ -z "${SLACK_WEBHOOK_URL:-}" ]; then
  echo "SLACK_WEBHOOK_URL not set, skipping Slack notification"
  exit 0
fi

REPORT=$(cat "$REPORT_FILE")

# --- Helper: extract value between ** in a section ---
# Usage: metric_in_section "PR Size" "Average"
metric_in_section() {
  local section="$1" field="$2"
  echo "$REPORT" | awk "/$section/{f=1;next} f&&/^###/{exit} f" | grep "| $field " | head -1 | sed 's/.*\*\*\([^*]*\)\*\*.*/\1/'
}

# Usage: raw_in_section "PR Size" "p90"
raw_in_section() {
  local section="$1" field="$2"
  echo "$REPORT" | awk "/$section/{f=1;next} f&&/^###/{exit} f" | grep "| $field " | head -1 | sed 's/.*| *\([^|]*\) *|$/\1/' | xargs
}

# --- Extract metrics ---
PR_COUNT=$(echo "$REPORT" | grep -o '[0-9]* PRs merged' | head -1 | grep -o '[0-9]*')

AVG_SIZE=$(metric_in_section "PR Size" "Average")
MEDIAN_SIZE=$(metric_in_section "PR Size" "Median")
SIZE_S=$(echo "$REPORT" | grep "S (≤50)" | grep -o '| [0-9]*%' | grep -o '[0-9]*')
SIZE_M=$(echo "$REPORT" | grep "M (51" | grep -o '| [0-9]*%' | grep -o '[0-9]*')
SIZE_L=$(echo "$REPORT" | grep "L (201" | grep -o '| [0-9]*%' | grep -o '[0-9]*')
SIZE_XL=$(echo "$REPORT" | grep "XL (>400)" | grep -o '| [0-9]*%' | grep -o '[0-9]*')

# Cycle time is now a 3-row table: Coding, Review, Total cycle
CODING_AVG=$(echo "$REPORT" | awk '/Cycle Time/{f=1;next} f&&/^###/{exit} f' | grep "Coding" | head -1 | sed 's/.*\*\*\([^*]*\)\*\*.*/\1/')
REVIEW_CT_AVG=$(echo "$REPORT" | awk '/Cycle Time/{f=1;next} f&&/^###/{exit} f' | grep "Review" | head -1 | sed 's/.*\*\*\([^*]*\)\*\*.*/\1/')
TOTAL_CYCLE_AVG=$(echo "$REPORT" | awk '/Cycle Time/{f=1;next} f&&/^###/{exit} f' | grep "Total cycle" | head -1 | sed 's/.*\*\*\([^*]*\)\*\*.*/\1/')
TOTAL_CYCLE_MED=$(echo "$REPORT" | awk '/Cycle Time/{f=1;next} f&&/^###/{exit} f' | grep "Total cycle" | head -1 | sed 's/.*\*\* *| *\([^|]*\) *|.*/\1/' | xargs)

AVG_REVIEW=$(metric_in_section "First Review" "Average")
MEDIAN_REVIEW=$(metric_in_section "First Review" "Median")
REVIEWED_COUNT=$(raw_in_section "First Review" "PRs with reviews")

DEPLOY_COUNT=$(echo "$REPORT" | grep "Merges to main" | sed 's/.*\*\*\([0-9]*\)\*\*.*/\1/')
DEPLOY_RATE=$(echo "$REPORT" | grep "Merges to main" | grep -o '([^)]*day)' || echo "")

# Type distribution — extract type and percentage, format for Slack
TYPES=$(echo "$REPORT" | awk '/Type Distribution/{f=1;next} f&&/^###/{exit} f' | grep '^| [a-z]' | \
  sed 's/^| *\([^ ]*\) *| *\([0-9]*\) *| *\([0-9]*%\) *|$/\1 \3/' | \
  awk '{printf "%s %s  ", $1, $2}' | sed 's/  $//')

# Largest PRs — top 3
LARGEST=$(echo "$REPORT" | awk '/Largest PRs/{f=1;next} f&&/^---/{exit} f' | grep '\[#' | head -3 | \
  sed 's/^| \[#\([0-9]*\)\]([^)]*) \(.*\)| \([0-9]*\) |.*$/• #\1 \2(\3 lines)/' | \
  sed 's/  */ /g')

# --- Build Slack Block Kit payload ---
REPO_URL="https://github.com/$REPO"

PAYLOAD=$(jq -n \
  --arg repo_name "$REPO_NAME" \
  --arg pr_count "${PR_COUNT:-0}" \
  --arg avg_size "${AVG_SIZE:-—}" \
  --arg median_size "${MEDIAN_SIZE:-—}" \
  --arg size_s "${SIZE_S:-0}" \
  --arg size_m "${SIZE_M:-0}" \
  --arg size_l "${SIZE_L:-0}" \
  --arg size_xl "${SIZE_XL:-0}" \
  --arg coding_avg "${CODING_AVG:-—}" \
  --arg review_ct_avg "${REVIEW_CT_AVG:-—}" \
  --arg total_cycle_avg "${TOTAL_CYCLE_AVG:-—}" \
  --arg total_cycle_med "${TOTAL_CYCLE_MED:-—}" \
  --arg avg_review "${AVG_REVIEW:-—}" \
  --arg median_review "${MEDIAN_REVIEW:-—}" \
  --arg reviewed "${REVIEWED_COUNT:-—}" \
  --arg deploys "${DEPLOY_COUNT:-0}" \
  --arg deploy_rate "${DEPLOY_RATE:-}" \
  --arg types "$TYPES" \
  --arg largest "$LARGEST" \
  --arg repo_url "$REPO_URL" \
  '{
    blocks: [
      {
        type: "header",
        text: { type: "plain_text", text: ("📊 Weekly Metrics — " + $repo_name), emoji: true }
      },
      {
        type: "context",
        elements: [
          { type: "mrkdwn", text: ($pr_count + " PRs merged · " + $deploys + " deploys " + $deploy_rate) }
        ]
      },
      { type: "divider" },
      {
        type: "section",
        fields: [
          { type: "mrkdwn", text: ("*📏 PR Size*\nAvg: " + $avg_size + "\nMedian: " + $median_size + "\n`S` " + $size_s + "% · `M` " + $size_m + "% · `L` " + $size_l + "% · `XL` " + $size_xl + "%") },
          { type: "mrkdwn", text: ("*⏱️ Cycle Time*\nCoding: " + $coding_avg + "\nReview: " + $review_ct_avg + "\nTotal: " + $total_cycle_avg + " (med " + $total_cycle_med + ")") }
        ]
      },
      {
        type: "section",
        fields: [
          { type: "mrkdwn", text: ("*👀 First Review*\nAvg: " + $avg_review + "\nMedian: " + $median_review + "\nReviewed: " + $reviewed) },
          { type: "mrkdwn", text: ("*🏷️ Types*\n" + $types) }
        ]
      },
      { type: "divider" },
      {
        type: "section",
        text: { type: "mrkdwn", text: ("*📋 Largest PRs*\n" + $largest) }
      },
      {
        type: "context",
        elements: [
          { type: "mrkdwn", text: ("<" + $repo_url + "/actions|View in Actions>") }
        ]
      }
    ]
  }')

# --- Post to Slack ---
HTTP_CODE=$(curl -s -o /tmp/slack-response.txt -w "%{http_code}" \
  -X POST "$SLACK_WEBHOOK_URL" \
  -H "Content-Type: application/json" \
  -d "$PAYLOAD")

if [ "$HTTP_CODE" = "200" ]; then
  echo "✅ Posted metrics report to Slack"
else
  echo "❌ Slack webhook returned HTTP $HTTP_CODE"
  cat /tmp/slack-response.txt
  exit 1
fi
