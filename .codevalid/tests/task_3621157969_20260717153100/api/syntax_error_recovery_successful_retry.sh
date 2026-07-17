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
echo "STEP: Given — verify service health and prepare special-character city question"
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
{"question":"Find all customers who live in cities with names containing special characters like São José dos Campos","case_id":"syntax_error_recovery_successful_retry-${CASE_SUFFIX}"}
EOF

# When
echo "STEP: When — submit question likely to require corrected SQLite string handling"
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
echo "STEP: Then — assert final query succeeded and unicode match is reflected in answer"
[ "$HTTP_CODE" = "200" ] || { echo "ASSERTION_FAILED: expected HTTP 200 got ${HTTP_CODE}"; exit 1; }
if grep -Eiq 'near ".*": syntax error|sqlite error|operationalerror' "$RESPONSE_BODY"; then
  echo "ASSERTION_FAILED: final response still reports SQLite syntax failure"
  exit 1
fi
grep -Fqi 'São José dos Campos' "$RESPONSE_BODY" || { echo "ASSERTION_FAILED: expected response to mention São José dos Campos"; exit 1; }
grep -Fqi 'Luís Gonçalves' "$RESPONSE_BODY" || { echo "ASSERTION_FAILED: expected response to include Luís Gonçalves"; exit 1; }

# Cleanup
echo "STEP: Cleanup — no cleanup required for stateless API invocation"

echo "CODEVALID_TEST_ASSERTION_OK:syntax_error_recovery_successful_retry"
