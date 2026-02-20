#!/usr/bin/env bash
# Convert the weekly metrics markdown report to Slack Block Kit and post it.
set -euo pipefail

REPORT_FILE="${1:?Usage: slack-report.sh <report-markdown-file>}"
REPO="${GITHUB_REPOSITORY}"
REPO_NAME="${REPO#*/}"

if [ -z "${SLACK_WEBHOOK_URL:-}" ]; then
  echo "SLACK_WEBHOOK_URL not set, skipping Slack notification"
  exit 0
fi

REPORT=$(cat "$REPORT_FILE")

# --- Extract key numbers for the header ---
PR_COUNT=$(echo "$REPORT" | grep -oP '\*\*\K[0-9]+ PRs merged' | head -1 || echo "0 PRs merged")
AVG_SIZE=$(echo "$REPORT" | grep "Average" | head -1 | grep -oP '\*\*\K[0-9]+ lines' || echo "— lines")
MEDIAN_CYCLE=$(echo "$REPORT" | sed -n '/Cycle Time/,/###/{/Median/p}' | grep -oP '\*\*\K[^*]+' || echo "—")

# --- Convert markdown to Slack mrkdwn ---
SLACK_BODY=$(echo "$REPORT" | \
  # Remove the title (we use it as header) and repo/period line
  sed '1,4d' | \
  # Convert ### headers to bold with emoji
  sed 's/^### 1\. PR Size/*📏 PR Size*/g' | \
  sed 's/^### 2\. Cycle Time.*/*⏱️ Cycle Time (opened → merged)*/g' | \
  sed 's/^### 3\. Time to First Review/*👀 Time to First Review*/g' | \
  sed 's/^### 4\. Deployment Frequency/*🚀 Deployment Frequency*/g' | \
  sed 's/^### 5\. Type Distribution/*🏷️ Type Distribution*/g' | \
  sed 's/^### 📋 Largest PRs/*📋 Largest PRs*/g' | \
  sed 's/^### Summary/*Summary*/g' | \
  # Remove markdown table headers and separator lines
  sed '/^| Metric | Value |$/d' | \
  sed '/^| Size | Count | % |$/d' | \
  sed '/^| Type | Count | % |$/d' | \
  sed '/^| PR | Lines | Type | Author |$/d' | \
  sed '/^|[-|]*|$/d' | \
  # Convert table rows to compact lines
  sed 's/^| \(.*\) |$/\1/' | \
  sed 's/ | / · /g' | \
  # Convert markdown links [text](url) to Slack format <url|text>
  sed 's/\[\([^]]*\)\](\([^)]*\))/<\2|\1>/g' | \
  # Remove the footer
  sed '/^---$/,$d' | \
  # Remove excessive blank lines
  cat -s)

# Truncate if needed (Slack 3000 char limit per block)
if [ ${#SLACK_BODY} -gt 2900 ]; then
  SLACK_BODY="${SLACK_BODY:0:2900}…"
fi

# --- Build Slack payload ---
REPO_URL="https://github.com/$REPO"
ACTIONS_URL="$REPO_URL/actions"

PAYLOAD=$(jq -n \
  --arg header "📊 Engineering Metrics — $REPO_NAME" \
  --arg summary "$PR_COUNT · avg $AVG_SIZE · median cycle $MEDIAN_CYCLE" \
  --arg body "$SLACK_BODY" \
  --arg actions_url "$ACTIONS_URL" \
  --arg repo_url "$REPO_URL" \
  '{
    blocks: [
      {
        type: "header",
        text: { type: "plain_text", text: $header, emoji: true }
      },
      {
        type: "context",
        elements: [
          { type: "mrkdwn", text: $summary }
        ]
      },
      { type: "divider" },
      {
        type: "section",
        text: { type: "mrkdwn", text: $body }
      },
      { type: "divider" },
      {
        type: "context",
        elements: [
          { type: "mrkdwn", text: ("<" + $actions_url + "|View in Actions> · <" + $repo_url + "|" + $repo_url + ">") }
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
