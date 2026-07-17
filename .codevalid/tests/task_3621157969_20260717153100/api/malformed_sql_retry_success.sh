#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
CASE_SUFFIX="$(date +%s)_$$"
CASE_ID="malformed_sql_retry_success_${CASE_SUFFIX}"
QUESTION='Show me all playlists that contain rock songs'
TMP_DIR="$(mktemp -d)"
STDOUT_FILE="$TMP_DIR/stdout.txt"
STDERR_FILE="$TMP_DIR/stderr.txt"
cleanup_tmp() {
  rm -rf "$TMP_DIR"
}
trap cleanup_tmp EXIT

# Given — verify CLI and database availability

echo "STEP: Given — verify retry scenario prerequisites"
echo "PREREQ: checking agent.py exists"
[ -f /app/agent.py ] || { echo "ASSERTION_FAILED: expected /app/agent.py to exist"; exit 1; }
echo "PREREQ: checking chinook.db exists"
[ -f /app/chinook.db ] || { echo "ASSERTION_FAILED: expected /app/chinook.db to exist"; exit 1; }

# When — invoke CLI with a query that may require correction/retry

echo "STEP: When — execute CLI for playlists containing rock songs"
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

# Then — assert user sees a successful answer, not a surfaced raw error

echo "STEP: Then — verify final output is successful and readable"
[ "$EXIT_CODE" = "0" ] || { echo "ASSERTION_FAILED: expected exit code 0 got ${EXIT_CODE}"; exit 1; }
grep -F 'Answer:' "$STDOUT_FILE" >/dev/null 2>&1 || { echo "ASSERTION_FAILED: expected stdout to contain Answer label"; exit 1; }
if grep -Ei 'playlist|rock' "$STDOUT_FILE" >/dev/null 2>&1; then :; else echo "ASSERTION_FAILED: expected stdout to mention playlists or rock songs"; exit 1; fi
if grep -F 'Error:' "$STDOUT_FILE" >/dev/null 2>&1; then echo "ASSERTION_FAILED: did not expect final stdout to contain Error panel"; exit 1; fi
if grep -Ei 'traceback|sqlite3\.OperationalError|syntax error' "$STDERR_FILE" >/dev/null 2>&1; then echo "ASSERTION_FAILED: did not expect raw SQL/runtime error leakage to stderr on successful retry path"; exit 1; fi

# Cleanup — no side effects to undo

echo "STEP: Cleanup — no cleanup required for read-only CLI query"
echo "CODEVALID_TEST_ASSERTION_OK:malformed_sql_retry_success"
