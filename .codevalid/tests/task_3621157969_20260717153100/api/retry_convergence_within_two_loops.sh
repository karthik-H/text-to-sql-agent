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
echo "STEP: Given — verify service health and prepare retry-prone playlist duration question"
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
{"question":"What is the total duration of all tracks in the playlist named 'Music'?","case_id":"retry_convergence_within_two_loops-${CASE_SUFFIX}"}
EOF

# When
echo "STEP: When — submit playlist duration question that may require retry/correction"
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
echo "STEP: Then — assert convergence within retry limit and readable duration answer"
[ "$HTTP_CODE" = "200" ] || { echo "ASSERTION_FAILED: expected HTTP 200 got ${HTTP_CODE}"; exit 1; }
if grep -Eiq 'syntax error|no such table|no such column|sqlite error|operationalerror' "$RESPONSE_BODY"; then
  echo "ASSERTION_FAILED: final response indicates agent failed to converge to executable SQL"
  exit 1
fi
RETRY_MENTIONS="$(grep -Eo 'retry|attempt|correction|corrected' "$RESPONSE_BODY" | wc -l | tr -d ' ')"
[ "$RETRY_MENTIONS" -le 2 ] || { echo "ASSERTION_FAILED: expected <= 2 retry-loop indicators, got ${RETRY_MENTIONS}"; exit 1; }
grep -Eiq 'music' "$RESPONSE_BODY" || { echo "ASSERTION_FAILED: expected response to mention playlist Music"; exit 1; }
grep -Eiq 'millisecond|second|minute|hour' "$RESPONSE_BODY" || { echo "ASSERTION_FAILED: expected readable duration wording in response"; exit 1; }

# Cleanup
echo "STEP: Cleanup — no cleanup required for stateless API invocation"

echo "CODEVALID_TEST_ASSERTION_OK:retry_convergence_within_two_loops"
