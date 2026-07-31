#!/usr/bin/env bash
set -euo pipefail

PR_NUMBER=$(jq -r '.pull_request.number' "$GITHUB_EVENT_PATH")
BASE_SHA=$(jq -r '.pull_request.base.sha' "$GITHUB_EVENT_PATH")
HEAD_SHA=$(jq -r '.pull_request.head.sha' "$GITHUB_EVENT_PATH")
PR_TITLE=$(jq -r '.pull_request.title' "$GITHUB_EVENT_PATH")
REPO="$GITHUB_REPOSITORY"

git fetch --no-tags --depth=50 origin "$BASE_SHA" "$HEAD_SHA" 2>/dev/null || true
DIFF_HASH=$(git diff "$BASE_SHA".."$HEAD_SHA" | openssl dgst -sha3-256 | awk '{print $2}')
FILES_CHANGED=$(git diff --name-only "$BASE_SHA".."$HEAD_SHA" | wc -l | tr -d ' ')

PAYLOAD=$(jq -n \
  --arg repo "$REPO" --arg pr "$PR_NUMBER" --arg title "$PR_TITLE" \
  --arg base "$BASE_SHA" --arg head "$HEAD_SHA" --arg diff_sha3 "$DIFF_HASH" \
  --arg files "$FILES_CHANGED" --arg agent "$AGENT_NAME" --arg model "$AGENT_MODEL" \
  --arg run_id "$GITHUB_RUN_ID" \
  '{
    sourceId: ("github:" + $repo + ":pr-" + $pr),
    data: {
      type: "ai-authored-pr",
      schema: "rubric.pr-provenance.v1",
      repository: $repo,
      pull_request: ($pr|tonumber),
      title: $title,
      base_sha: $base,
      head_sha: $head,
      diff_sha3_256: $diff_sha3,
      files_changed: ($files|tonumber),
      agent: { name: $agent, model: $model },
      ci_run_id: $run_id,
      attested_at: (now|todate)
    }
  }')

HTTP_CODE=$(curl -sS -o /tmp/rubric-resp.json -w '%{http_code}' \
  -X POST "$RUBRIC_ENDPOINT/v1/tiered-attest" \
  -H "Content-Type: application/json" \
  -H "X-API-Key: $RUBRIC_API_KEY" \
  -d "$PAYLOAD")
RESPONSE=$(cat /tmp/rubric-resp.json)

# quota/auth walls degrade to warning, never fail the PR check
if [ "$HTTP_CODE" -ge 400 ] && [ "$HTTP_CODE" -lt 500 ]; then
  echo "::warning::Rubric attestation skipped ($HTTP_CODE): $(echo "$RESPONSE" | jq -r '.error // "client error"')"
  exit 0
fi
if [ "$HTTP_CODE" -ge 500 ]; then
  echo "::error::Rubric attestation failed ($HTTP_CODE)"
  exit 1
fi

ATT_ID=$(echo "$RESPONSE" | jq -r '.attestationId // empty')
PAYLOAD_KEY=$(echo "$RESPONSE" | jq -r '.payloadKey // empty')
COMMITMENT=$(echo "$RESPONSE" | jq -r '.payloadCommitment // empty')
if [ -z "$ATT_ID" ]; then
  echo "::error::Attestation response missing attestationId: $RESPONSE"
  exit 1
fi
echo "attestation_id=$ATT_ID" >> "$GITHUB_OUTPUT"

BODY=$(jq -n --arg id "$ATT_ID" --arg agent "$AGENT_NAME" --arg model "$AGENT_MODEL" \
  --arg dh "$DIFF_HASH" --arg pk "$PAYLOAD_KEY" --arg cm "$COMMITMENT" \
  '{body: ("🛡️ **Rubric Attestation**\n\nThis PR was authored by `" + $agent + "` (" + $model + ") and its diff is sealed under a post-quantum attestation record anchored to Hedera.\n\n| | |\n|---|---|\n| Attestation ID | `" + $id + "` |\n| Diff SHA3-256 | `" + $dh + "` |\n| Payload commitment | `" + $cm + "` |\n| Payload key | `" + $pk + "` |\n\n_Record is independently verifiable at rubric-protocol.com/verify. Private repos: treat the payload key as sensitive._")}')

curl -sS -X POST \
  -H "Authorization: Bearer $GH_TOKEN" \
  -H "Accept: application/vnd.github+json" \
  "https://api.github.com/repos/$REPO/issues/$PR_NUMBER/comments" \
  -d "$BODY" > /dev/null

echo "Sealed PR #$PR_NUMBER → $ATT_ID"
