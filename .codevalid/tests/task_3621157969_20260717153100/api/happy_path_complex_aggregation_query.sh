#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
CASE_SUFFIX="$(date +%s)_$$"
CASE_ID="happy_path_complex_aggregation_query_${CASE_SUFFIX}"
QUESTION='What are the top 5 best-selling artists?'
TMP_DIR="$(mktemp -d)"
STDOUT_FILE="$TMP_DIR/stdout.txt"
STDERR_FILE="$TMP_DIR/stderr.txt"
cleanup_tmp() {
  rm -rf "$TMP_DIR"
}
trap cleanup_tmp EXIT

# Given — verify CLI assets exist

echo "STEP: Given — verify complex aggregation query prerequisites"
echo "PREREQ: checking agent.py exists"
[ -f /app/agent.py ] || { echo "ASSERTION_FAILED: expected /app/agent.py to exist"; exit 1; }
echo "PREREQ: checking chinook.db exists"
[ -f /app/chinook.db ] || { echo "ASSERTION_FAILED: expected /app/chinook.db to exist"; exit 1; }

# When — invoke CLI with top artists question

echo "STEP: When — execute CLI for top 5 best-selling artists"
echo "REQUEST_HEADERS: CLI invocation has no HTTP headers"
echo "REQUEST_BODY: $QUESTION"
set +e
python /app/agent.py "$QUESTION" >"$STDOUT_FILE" 2>"$STDERR_FILE"
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

# Then — assert readable answer with top-5 style content

echo "STEP: Then — verify artist aggregation answer is displayed"
[ "$EXIT_CODE" = "0" ] || { echo "ASSERTION_FAILED: expected exit code 0 got ${EXIT_CODE}"; exit 1; }
grep -F 'Question:' "$STDOUT_FILE" >/dev/null 2>&1 || { echo "ASSERTION_FAILED: expected stdout to contain Question label"; exit 1; }
grep -F 'What are the top 5 best-selling artists?' "$STDOUT_FILE" >/dev/null 2>&1 || { echo "ASSERTION_FAILED: expected stdout to contain the submitted question"; exit 1; }
grep -F 'Creating SQL Agent...' "$STDOUT_FILE" >/dev/null 2>&1 || { echo "ASSERTION_FAILED: expected stdout to contain creation status"; exit 1; }
grep -F 'Processing query...' "$STDOUT_FILE" >/dev/null 2>&1 || { echo "ASSERTION_FAILED: expected stdout to contain processing status"; exit 1; }
grep -F 'Answer:' "$STDOUT_FILE" >/dev/null 2>&1 || { echo "ASSERTION_FAILED: expected stdout to contain Answer label"; exit 1; }
if grep -Ei 'artist|sales|revenue|top 5' "$STDOUT_FILE" >/dev/null 2>&1; then :; else echo "ASSERTION_FAILED: expected stdout to mention artists or sales information"; exit 1; fi
if grep -Eq '[0-9]+' "$STDOUT_FILE"; then :; else echo "ASSERTION_FAILED: expected stdout to contain numeric sales/count data"; exit 1; fi
if grep -F 'Error:' "$STDOUT_FILE" >/dev/null 2>&1; then echo "ASSERTION_FAILED: did not expect error panel in stdout"; exit 1; fi

# Cleanup — no side effects to undo

echo "STEP: Cleanup — no cleanup required for read-only CLI query"
echo "CODEVALID_TEST_ASSERTION_OK:happy_path_complex_aggregation_query"
