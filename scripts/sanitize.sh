#!/usr/bin/env bash
set -euo pipefail
: "${PROJECT_ID:?Задай PROJECT_ID}"
PROJECT_NUMBER="${PROJECT_NUMBER:-$(gcloud projects describe "$PROJECT_ID" --format='value(projectNumber)' 2>/dev/null || true)}"

in="${1:--}"
sed -E \
  -e "s/${PROJECT_ID}/PROJECT_ID/g" \
  -e "s/[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}/REDACTED_EMAIL/g" \
  -e 's/\b([0-9]{1,3}\.){3}[0-9]{1,3}\b/REDACTED_IP/g' \
  -e 's/[0-9A-F]{6}-[0-9A-F]{6}-[0-9A-F]{6}/REDACTED_BILLING/g' \
  ${PROJECT_NUMBER:+-e "s/${PROJECT_NUMBER}/PROJECT_NUMBER/g"} \
  -e 's/ya29\.[A-Za-z0-9._-]+/REDACTED_TOKEN/g' \
  "$in"
