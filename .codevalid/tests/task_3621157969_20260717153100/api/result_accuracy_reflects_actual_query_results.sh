#!/usr/bin/env sh
set -eu

BASE_URL="${BASE_URL:-http://app:6713}"
CASE_SUFFIX="$(date +%s)-$$"
TMP_DIR="$(mktemp -d)"
REQUEST_ONE="$TMP_DIR/request_one.json"
REQUEST_TWO="$TMP_DIR/request_two.json"
RESPONSE_ONE_HEADERS="$TMP_DIR/response_one_headers.txt"
RESPONSE_ONE_BODY="$TMP_DIR/response_one_body.txt"
RESPONSE_TWO_HEADERS="$TMP_DIR/response_two_headers.txt"
RESPONSE_TWO_BODY="$TMP_DIR/response_two_body.txt"

cleanup_tmp() {
  rm -rf "$TMP_DIR"
}
trap cleanup_tmp EXIT

# Given
echo "STEP: Given — verify service health and prepare two accuracy-check questions"
echo "PREREQ: confirming app health endpoint is available at ${BASE_URL}/health"
echo "REQUEST_HEADERS: Accept: */*"
echo "REQUEST_BODY:"
printf '\n'
HEALTH_CODE="$(curl -sS -D "$TMP_DIR/health_headers.txt" -o "$TMP_DIR/health_body.txt" -w '%{http_code}' "$BASE_URL/health")"
echo "RESPONSE_STATUS: $HEALTH_CODE"
echo "RESPONSE_HEADERS:"; cat "$TMP_DIR/health_headers.txt"
echo "RESPONSE_BODY:"; cat "$TMP_DIR/health_body.txt"
[ "$HEALTH_CODE" = "200" ] || { echo "ASSERTION_FAILED: expected health HTTP 200 got ${HEALTH_CODE}"; exit 1; }

cat > "$REQUEST_ONE" <<EOF
{"question":"How many employees are in the company?","case_id":"result_accuracy_reflects_actual_query_results-count-${CASE_SUFFIX}"}
EOF
cat > "$REQUEST_TWO" <<EOF
{"question":"Which employee has no manager?","case_id":"result_accuracy_reflects_actual_query_results-manager-${CASE_SUFFIX}"}
EOF

# When
echo "STEP: When — submit employee count question"
echo "REQUEST_HEADERS: Content-Type: application/json"
echo "REQUEST_BODY:"; cat "$REQUEST_ONE"
HTTP_CODE_ONE="$(curl -sS -D "$RESPONSE_ONE_HEADERS" -o "$RESPONSE_ONE_BODY" -w '%{http_code}' \
  -X POST "$BASE_URL/invoke" \
  -H 'Content-Type: application/json' \
  --data @"$REQUEST_ONE")"
echo "RESPONSE_STATUS: $HTTP_CODE_ONE"
echo "RESPONSE_HEADERS:"; cat "$RESPONSE_ONE_HEADERS"
echo "RESPONSE_BODY:"; cat "$RESPONSE_ONE_BODY"

echo "STEP: When — submit employee-without-manager question"
echo "REQUEST_HEADERS: Content-Type: application/json"
echo "REQUEST_BODY:"; cat "$REQUEST_TWO"
HTTP_CODE_TWO="$(curl -sS -D "$RESPONSE_TWO_HEADERS" -o "$RESPONSE_TWO_BODY" -w '%{http_code}' \
  -X POST "$BASE_URL/invoke" \
  -H 'Content-Type: application/json' \
  --data @"$REQUEST_TWO")"
echo "RESPONSE_STATUS: $HTTP_CODE_TWO"
echo "RESPONSE_HEADERS:"; cat "$RESPONSE_TWO_HEADERS"
echo "RESPONSE_BODY:"; cat "$RESPONSE_TWO_BODY"

# Then
echo "STEP: Then — assert natural language answers match known Chinook results exactly"
[ "$HTTP_CODE_ONE" = "200" ] || { echo "ASSERTION_FAILED: expected first HTTP 200 got ${HTTP_CODE_ONE}"; exit 1; }
[ "$HTTP_CODE_TWO" = "200" ] || { echo "ASSERTION_FAILED: expected second HTTP 200 got ${HTTP_CODE_TWO}"; exit 1; }
grep -Eq '\b8\b' "$RESPONSE_ONE_BODY" || { echo "ASSERTION_FAILED: expected employee count 8 in first response"; exit 1; }
if grep -Eiq 'approximately|around|about' "$RESPONSE_ONE_BODY"; then
  echo "ASSERTION_FAILED: first response used approximate language instead of exact result"
  exit 1
fi
grep -Fqi 'Andrew Adams' "$RESPONSE_TWO_BODY" || { echo "ASSERTION_FAILED: expected Andrew Adams in second response"; exit 1; }
if grep -Eiq 'syntax error|no such table|no such column|sqlite error|operationalerror' "$RESPONSE_ONE_BODY" "$RESPONSE_TWO_BODY"; then
  echo "ASSERTION_FAILED: one of the responses indicates SQL execution failure"
  exit 1
fi

# Cleanup
echo "STEP: Cleanup — no cleanup required for stateless API invocation"

echo "CODEVALID_TEST_ASSERTION_OK:result_accuracy_reflects_actual_query_results"
