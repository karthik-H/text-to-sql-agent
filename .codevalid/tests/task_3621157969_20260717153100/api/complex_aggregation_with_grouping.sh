#!/usr/bin/env sh
set -eu

BASE_URL="${BASE_URL:-http://app:6713}"
CASE_SUFFIX="$(date +%s)-$$"
TMP_DIR="$(mktemp -d)"
RESPONSE_HEADERS="$TMP_DIR/response_headers.txt"
RESPONSE_BODY="$TMP_DIR/response_body.txt"
REQUEST_BODY_FILE="$TMP_DIR/request.json"

cleanup_tmp() {
  rm -rf "$TMP_DIR"
}
trap cleanup_tmp EXIT

# Given
echo "STEP: Given — verify service health and prepare complex employee revenue question"
echo "PREREQ: confirming app health endpoint is available at ${BASE_URL}/health"
echo "REQUEST_HEADERS: Accept: */*"
echo "REQUEST_BODY:"
printf '\n'
HEALTH_CODE="$(curl -sS -D "$TMP_DIR/health_headers.txt" -o "$TMP_DIR/health_body.txt" -w '%{http_code}' "$BASE_URL/health")"
echo "RESPONSE_STATUS: $HEALTH_CODE"
echo "RESPONSE_HEADERS:"; cat "$TMP_DIR/health_headers.txt"
echo "RESPONSE_BODY:"; cat "$TMP_DIR/health_body.txt"
[ "$HEALTH_CODE" = "200" ] || { echo "ASSERTION_FAILED: expected health HTTP 200 got ${HEALTH_CODE}"; exit 1; }

cat > "$REQUEST_BODY_FILE" <<EOF
{"question":"Which employee generated the most revenue?","case_id":"complex_aggregation_with_grouping-${CASE_SUFFIX}"}
EOF

# When
echo "STEP: When — submit aggregation and grouping question about employee revenue"
echo "REQUEST_HEADERS: Content-Type: application/json"
echo "REQUEST_BODY:"; cat "$REQUEST_BODY_FILE"
HTTP_CODE="$(curl -sS -D "$RESPONSE_HEADERS" -o "$RESPONSE_BODY" -w '%{http_code}' \
  -X POST "$BASE_URL/invoke" \
  -H 'Content-Type: application/json' \
  --data @"$REQUEST_BODY_FILE")"
echo "RESPONSE_STATUS: $HTTP_CODE"
echo "RESPONSE_HEADERS:"; cat "$RESPONSE_HEADERS"
echo "RESPONSE_BODY:"; cat "$RESPONSE_BODY"

# Then
echo "STEP: Then — assert grouped revenue query succeeded and identifies Jane Peacock"
[ "$HTTP_CODE" = "200" ] || { echo "ASSERTION_FAILED: expected HTTP 200 got ${HTTP_CODE}"; exit 1; }
if grep -Eiq 'syntax error|no such table|no such column|sqlite error|operationalerror' "$RESPONSE_BODY"; then
  echo "ASSERTION_FAILED: response indicates grouped SQL failed to execute"
  exit 1
fi
grep -Fqi 'Jane Peacock' "$RESPONSE_BODY" || { echo "ASSERTION_FAILED: expected top employee Jane Peacock in response"; exit 1; }
grep -Eiq '\$|833\.04|revenue|total' "$RESPONSE_BODY" || { echo "ASSERTION_FAILED: expected revenue amount/details in response"; exit 1; }

# Cleanup
echo "STEP: Cleanup — no cleanup required for stateless API invocation"

echo "CODEVALID_TEST_ASSERTION_OK:complex_aggregation_with_grouping"
