get_or_create_engagement() {
  local encoded_name
  encoded_name=$(urlencode "$DOJO_ENGAGEMENT_NAME")

  echo "DEBUG: looking up engagement..."
  local existing
  existing=$(curl --fail-with-body -sS \
    -H "Authorization: Token ${DOJO_TOKEN}" \
    "${DOJO_URL}/api/v2/engagements/?name=${encoded_name}&product=${DOJO_PRODUCT_ID}&limit=1") \
    || { echo "ERROR: engagement curl failed (HTTP error)"; exit 1; }

  echo "DEBUG: engagement response: $existing"

  local engagement_id
  engagement_id=$(echo "$existing" | extract_first_id) || { echo "ERROR: extract_first_id failed"; exit 1; }

  echo "DEBUG: engagement_id=$engagement_id"

  if [[ -n "$engagement_id" ]]; then
    echo "$engagement_id"
    return 0
  fi

  local encoded_lead
  encoded_lead=$(urlencode "$DOJO_ENGAGEMENT_LEAD_USERNAME")

  echo "DEBUG: looking up user..."
  local lead_payload
  lead_payload=$(curl --fail-with-body -sS \
    -H "Authorization: Token ${DOJO_TOKEN}" \
    "${DOJO_URL}/api/v2/users/?username=${encoded_lead}&limit=1") \
    || { echo "ERROR: user curl failed (HTTP error)"; exit 1; }

  echo "DEBUG: user response: $lead_payload"

  local lead_id
  lead_id=$(echo "$lead_payload" | extract_first_id) || { echo "ERROR: extract_first_id for user failed"; exit 1; }

  echo "DEBUG: lead_id=$lead_id"

  if [[ -z "$lead_id" ]]; then
    echo "ERROR: Could not find DefectDojo user: ${DOJO_ENGAGEMENT_LEAD_USERNAME}"
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

  echo "DEBUG: creating engagement with payload: $payload"

  local created
  created=$(curl --fail-with-body -sS -X POST "${DOJO_URL}/api/v2/engagements/" \
    -H "Authorization: Token ${DOJO_TOKEN}" \
    -H "Content-Type: application/json" \
    -d "$payload") || { echo "ERROR: engagement creation failed. Response: $created"; exit 1; }

  echo "DEBUG: create response: $created"
  echo "$created" | extract_id
}
