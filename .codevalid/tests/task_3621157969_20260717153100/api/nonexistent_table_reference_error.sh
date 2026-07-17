#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
CASE_SUFFIX="$(date +%s)_$$"
CASE_ID="nonexistent_table_reference_error_${CASE_SUFFIX}"
QUESTION='Show me all products in the catalog'
TMP_DIR="$(mktemp -d)"
STDOUT_FILE="$TMP_DIR/stdout.txt"
STDERR_FILE="$TMP_DIR/stderr.txt"
cleanup_tmp() {
  rm -rf "$TMP_DIR"
}
trap cleanup_tmp EXIT

# Given — verify CLI prerequisites

echo "STEP: Given — verify nonexistent table question prerequisites"
echo "PREREQ: checking agent.py exists"
[ -f /app/agent.py ] || { echo "ASSERTION_FAILED: expected /app/agent.py to exist"; exit 1; }
echo "PREREQ: checking chinook.db exists"
[ -f /app/chinook.db ] || { echo "ASSERTION_FAILED: expected /app/chinook.db to exist"; exit 1; }

# When — invoke CLI with question implying a nonexistent table

echo "STEP: When — execute CLI for nonexistent products catalog question"
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

# Then — assert informative handling without raw SQL leak

echo "STEP: Then — verify nonexistent schema mismatch is handled informatively"
if [ "$EXIT_CODE" = "0" ] || [ "$EXIT_CODE" = "1" ]; then :; else echo "ASSERTION_FAILED: expected graceful exit code 0 or 1, got ${EXIT_CODE}"; exit 1; fi
if grep -F 'Answer:' "$STDOUT_FILE" >/dev/null 2>&1 || grep -F 'Error:' "$STDOUT_FILE" >/dev/null 2>&1; then :; else echo "ASSERTION_FAILED: expected stdout to contain either Answer or Error panel"; exit 1; fi
if grep -Ei 'products|catalog|table|schema|available' "$STDOUT_FILE" >/dev/null 2>&1; then :; else echo "ASSERTION_FAILED: expected user-facing output to mention the requested domain or schema mismatch"; exit 1; fi
if grep -Ei 'Traceback|stack trace' "$STDOUT_FILE" "$STDERR_FILE" >/dev/null 2>&1; then echo "ASSERTION_FAILED: did not expect traceback leakage"; exit 1; fi

# Cleanup — no side effects to undo

echo "STEP: Cleanup — no cleanup required for read-only CLI query"
echo "CODEVALID_TEST_ASSERTION_OK:nonexistent_table_reference_error"
