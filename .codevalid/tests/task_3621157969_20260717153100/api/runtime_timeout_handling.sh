#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
CASE_SUFFIX="$(date +%s)_$$"
CASE_ID="runtime_timeout_handling_${CASE_SUFFIX}"
QUESTION='Calculate total sales for each customer by combining all invoice line items with full customer details'
TMP_DIR="$(mktemp -d)"
STDOUT_FILE="$TMP_DIR/stdout.txt"
STDERR_FILE="$TMP_DIR/stderr.txt"
cleanup_tmp() {
  rm -rf "$TMP_DIR"
}
trap cleanup_tmp EXIT

# Given — verify CLI prerequisites and timeout tool availability

echo "STEP: Given — verify long-running query test prerequisites"
echo "PREREQ: checking agent.py exists"
[ -f /app/agent.py ] || { echo "ASSERTION_FAILED: expected /app/agent.py to exist"; exit 1; }
echo "PREREQ: checking chinook.db exists"
[ -f /app/chinook.db ] || { echo "ASSERTION_FAILED: expected /app/chinook.db to exist"; exit 1; }
TIMEOUT_BIN=''
if command -v timeout >/dev/null 2>&1; then
  TIMEOUT_BIN='timeout'
elif command -v gtimeout >/dev/null 2>&1; then
  TIMEOUT_BIN='gtimeout'
else
  echo 'ASSERTION_FAILED: expected timeout or gtimeout command to be available in seed-test image'
  exit 1
fi

echo "PREREQ: using timeout binary $TIMEOUT_BIN"

# When — invoke CLI under a bounded timeout

echo "STEP: When — execute CLI for potentially long-running query under timeout guard"
echo "REQUEST_HEADERS: CLI invocation has no HTTP headers"
echo "REQUEST_BODY: $QUESTION"
set +e
"$TIMEOUT_BIN" 90s python /app/agent.py "$QUESTION" >"$STDOUT_FILE" 2>"$STDERR_FILE"
EXIT_CODE="$?"
set -e

echo "RESPONSE_STATUS: process_exit_code=$EXIT_CODE"
echo "RESPONSE_HEADERS: CLI invocation has no HTTP response headers"
echo "RESPONSE_BODY_STDOUT_BEGIN"
cat "$STDOUT_FILE"
echo "RESPONSE_BODY_STDOUT_END"
echo "RESPONSE_BODY_STDERR_BEGIN"
cat "$STDERR_FILE"
echo "RESPONSE_BODY_STDERR_END"

# Then — assert either success or graceful timeout/error handling, but never hang indefinitely

echo "STEP: Then — verify bounded execution and graceful handling of slow query"
if [ "$EXIT_CODE" = "0" ]; then
  grep -F 'Answer:' "$STDOUT_FILE" >/dev/null 2>&1 || { echo "ASSERTION_FAILED: expected Answer label on successful execution"; exit 1; }
  if grep -Ei 'customer|sales|invoice|total' "$STDOUT_FILE" >/dev/null 2>&1; then :; else echo "ASSERTION_FAILED: expected successful output to contain customer sales content"; exit 1; fi
elif [ "$EXIT_CODE" = "1" ] || [ "$EXIT_CODE" = "124" ]; then
  if grep -F 'Error:' "$STDOUT_FILE" >/dev/null 2>&1 || [ "$EXIT_CODE" = "124" ]; then :; else echo "ASSERTION_FAILED: expected Error panel or timeout exit for unsuccessful execution"; exit 1; fi
else
  echo "ASSERTION_FAILED: expected exit code 0, 1, or 124 got ${EXIT_CODE}"
  exit 1
fi
if grep -Ei 'Traceback' "$STDERR_FILE" >/dev/null 2>&1; then echo "ASSERTION_FAILED: did not expect raw traceback leakage in stderr"; exit 1; fi

# Cleanup — no side effects to undo

echo "STEP: Cleanup — no cleanup required for long-running query test"
echo "CODEVALID_TEST_ASSERTION_OK:runtime_timeout_handling"
