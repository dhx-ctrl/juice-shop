#!/usr/bin/env bash
set -euo pipefail

required_vars=(
  DOJO_URL DOJO_TOKEN DOJO_PRODUCT_ID
  DOJO_ENGAGEMENT_NAME DOJO_ENGAGEMENT_LEAD_USERNAME
  SCAN_TYPE_TRIVY SCAN_TYPE_ZAP SCAN_TYPE_SEMGREP
  RUN_OUTPUT_DIR
)

for v in "${required_vars[@]}"; do
  if [[ -z "${!v:-}" ]]; then
    echo "ERROR: Missing env var: $v"
    exit 1
  fi
done

urlencode() {
  python3 - "$1" <<'PY'
import sys
from urllib.parse import quote
print(quote(sys.argv[1]))
PY
}

extract_first_id() {
  python3 - <<'PY'
import json, sys
raw = sys.stdin.read().strip()
if not raw:
    sys.exit(0)
try:
    payload = json.loads(raw)
except json.JSONDecodeError as e:
    print(f"ERROR: invalid JSON from API: {e}\nRaw response: {raw[:300]}", file=sys.stderr)
    sys.exit(1)
results = payload.get("results") or []
print(results[0].get("id", "") if results else "")
PY
}

extract_id() {
  python3 - <<'PY'
import json, sys
raw = sys.stdin.read().strip()
if not raw:
    sys.exit(0)
try:
    payload = json.loads(raw)
except json.JSONDecodeError as e:
    print(f"ERROR: invalid JSON from API: {e}\nRaw response: {raw[:300]}", file=sys.stderr)
    sys.exit(1)
print(payload.get("id", ""))
PY
}

echo "Checking DefectDojo connectivity..."
http_code=$(curl -o /tmp/dojo_check.txt -sS -w "%{http_code}" \
  -H "Authorization: Token ${DOJO_TOKEN}" \
  "${DOJO_URL}/api/v2/users/?limit=1")

if [[ "$http_code" != "200" ]]; then
  echo "ERROR: DefectDojo returned HTTP $http_code — check DOJO_URL and DOJO_TOKEN"
  cat /tmp/dojo_check.txt
  exit 1
fi
echo "DefectDojo reachable (HTTP $http_code)"

get_or_create_engagement() {
  local encoded_name
  encoded_name=$(urlencode "$DOJO_ENGAGEMENT_NAME")

  local existing
  existing=$(curl --fail-with-body -sS \
    -H "Authorization: Token ${DOJO_TOKEN}" \
    "${DOJO_URL}/api/v2/engagements/?name=${encoded_name}&product=${DOJO_PRODUCT_ID}&limit=1") \
    || { echo "ERROR: engagement lookup failed" >&2; exit 1; }

  local engagement_id
  engagement_id=$(echo "$existing" | extract_first_id)

  if [[ -n "$engagement_id" ]]; then
    echo "$engagement_id"
    return 0
  fi

  local encoded_lead
  encoded_lead=$(urlencode "$DOJO_ENGAGEMENT_LEAD_USERNAME")

  local lead_payload
  lead_payload=$(curl --fail-with-body -sS \
    -H "Authorization: Token ${DOJO_TOKEN}" \
    "${DOJO_URL}/api/v2/users/?username=${encoded_lead}&limit=1") \
    || { echo "ERROR: user lookup failed" >&2; exit 1; }

  echo "DEBUG lead_payload: $lead_payload" >&2

  local lead_id
  lead_id=$(echo "$lead_payload" | extract_first_id)

  echo "DEBUG lead_id: $lead_id" >&2

  if [[ -z "$lead_id" ]]; then
    echo "ERROR: Could not find DefectDojo user: ${DOJO_ENGAGEMENT_LEAD_USERNAME}" >&2
    exit 1
  fi

  local target_start target_end
  target_start=$(date -u +%Y-%m-%d)
  target_end=$(date -u -d "+7 days" +%Y-%m-%d)

  local payload
  payload=$(TARGET_START="$target_start" TARGET_END="$target_end" LEAD_ID="$lead_id" python3 - <<'PY'
import json, os
print(json.dumps({
    "name": os.environ["DOJO_ENGAGEMENT_NAME"],
    "product": int(os.environ["DOJO_PRODUCT_ID"]),
    "status": "In Progress",
    "engagement_type": "CI/CD",
    "target_start": os.environ["TARGET_START"],
    "target_end": os.environ["TARGET_END"],
    "lead": int(os.environ["LEAD_ID"]),
}))
PY
)

  local created
  created=$(curl --fail-with-body -sS -X POST "${DOJO_URL}/api/v2/engagements/" \
    -H "Authorization: Token ${DOJO_TOKEN}" \
    -H "Content-Type: application/json" \
    -d "$payload") || { echo "ERROR: engagement creation failed: $created" >&2; exit 1; }

  echo "$created" | extract_id
}

echo "RUN_OUTPUT_DIR=${RUN_OUTPUT_DIR}"
if [[ ! -d "${RUN_OUTPUT_DIR}" ]]; then
  echo "ERROR: RUN_OUTPUT_DIR does not exist: ${RUN_OUTPUT_DIR}"
  exit 1
fi

DOJO_ENGAGEMENT_ID=$(get_or_create_engagement)
if [[ -z "$DOJO_ENGAGEMENT_ID" ]]; then
  echo "ERROR: Failed to resolve engagement ID"
  exit 1
fi
export DOJO_ENGAGEMENT_ID

ls -la "${RUN_OUTPUT_DIR}"

for f in semgrep.json trivy_fs.json trivy_image.json zap.xml; do
  if [[ ! -s "${RUN_OUTPUT_DIR}/${f}" ]]; then
    echo "ERROR: missing/empty file: ${RUN_OUTPUT_DIR}/${f}"
    exit 1
  fi
  echo "OK: ${f} ($(wc -c < "${RUN_OUTPUT_DIR}/${f}") bytes)"
done

import_scan() {
  local scan_type="$1"
  local file_path="$2"
  local min_sev="$3"
  local mime="$4"

  echo "Importing: ${scan_type} -> ${file_path}"
  curl --fail-with-body -sS -X POST "${DOJO_URL}/api/v2/import-scan/" \
    -H "Authorization: Token ${DOJO_TOKEN}" \
    -F "active=true" \
    -F "verified=false" \
    -F "reimport=true" \
    -F "scan_type=${scan_type}" \
    -F "minimum_severity=${min_sev}" \
    -F "product=${DOJO_PRODUCT_ID}" \
    -F "engagement=${DOJO_ENGAGEMENT_ID}" \
    -F "file=@${file_path};type=${mime}"
}

import_scan "${SCAN_TYPE_SEMGREP}" "${RUN_OUTPUT_DIR}/semgrep.json"     "Low" "application/json"
import_scan "${SCAN_TYPE_TRIVY}"   "${RUN_OUTPUT_DIR}/trivy_fs.json"    "Low" "application/json"
import_scan "${SCAN_TYPE_TRIVY}"   "${RUN_OUTPUT_DIR}/trivy_image.json" "Low" "application/json"
import_scan "${SCAN_TYPE_ZAP}"     "${RUN_OUTPUT_DIR}/zap.xml"          "Low" "text/xml"

echo "All imports completed successfully."
