#!/usr/bin/env bash
set -euo pipefail

# Required env vars:
# DOJO_URL, DOJO_TOKEN, DOJO_PRODUCT_ID, DOJO_ENGAGEMENT_ID
# SCAN_TYPE_SONAR, SCAN_TYPE_TRIVY, SCAN_TYPE_ZAP
# RUN_OUTPUT_DIR

required_vars=(
  DOJO_URL DOJO_TOKEN DOJO_PRODUCT_ID DOJO_ENGAGEMENT_ID
  SCAN_TYPE_SONAR SCAN_TYPE_TRIVY SCAN_TYPE_ZAP
  RUN_OUTPUT_DIR
)

for v in "${required_vars[@]}"; do
  if [[ -z "${!v:-}" ]]; then
    echo "ERROR: Missing env var: $v"
    exit 1
  fi
done

echo "RUN_OUTPUT_DIR=${RUN_OUTPUT_DIR}"
if [[ ! -d "${RUN_OUTPUT_DIR}" ]]; then
  echo "ERROR: RUN_OUTPUT_DIR does not exist: ${RUN_OUTPUT_DIR}"
  exit 1
fi

ls -la "${RUN_OUTPUT_DIR}"

# Verify files exist and are not empty
for f in sonarqube_issues.json trivy.json zap.xml; do
  if [[ ! -s "${RUN_OUTPUT_DIR}/${f}" ]]; then
    echo "ERROR: missing/empty file: ${RUN_OUTPUT_DIR}/${f}"
    exit 1
  fi
  echo "OK: ${f} ($(wc -c < "${RUN_OUTPUT_DIR}/${f}") bytes)"
done

import_scan () {
  local scan_type="$1"
  local file_path="$2"
  local min_sev="$3"
  local mime="$4"

  echo "Importing: ${scan_type} -> ${file_path}"
  curl --fail-with-body -sS -X POST "${DOJO_URL}/api/v2/import-scan/" \
    -H "Authorization: Token ${DOJO_TOKEN}" \
    -F "active=true" \
    -F "verified=false" \
    -F "scan_type=${scan_type}" \
    -F "minimum_severity=${min_sev}" \
    -F "product=${DOJO_PRODUCT_ID}" \
    -F "engagement=${DOJO_ENGAGEMENT_ID}" \
    -F "file=@${file_path};type=${mime}"
}

# Imports
import_scan "${SCAN_TYPE_SONAR}" "${RUN_OUTPUT_DIR}/sonarqube_issues.json" "Info" "application/json"
import_scan "${SCAN_TYPE_TRIVY}" "${RUN_OUTPUT_DIR}/trivy.json"           "Low"  "application/json"
import_scan "${SCAN_TYPE_ZAP}"   "${RUN_OUTPUT_DIR}/zap.xml"             "Low"  "text/xml"

echo "All imports completed successfully."
