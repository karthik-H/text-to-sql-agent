#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
CASE_SUFFIX="$(date +%s)_$$"
CASE_ID="empty_question_argument_${CASE_SUFFIX}"
QUESTION=''
TMP_DIR="$(mktemp -d)"
STDOUT_FILE="$TMP_DIR/stdout.txt"
STDERR_FILE="$TMP_DIR/stderr.txt"
cleanup_tmp() {
  rm -rf "$TMP_DIR"
}
trap cleanup_tmp EXIT

# Given — verify CLI prerequisites

echo "STEP: Given — verify prerequisites for empty question invocation"
echo "PREREQ: checking agent.py exists"
[ -f /app/agent.py ] || { echo "ASSERTION_FAILED: expected /app/agent.py to exist"; exit 1; }
echo "PREREQ: checking chinook.db exists"
[ -f /app/chinook.db ] || { echo "ASSERTION_FAILED: expected /app/chinook.db to exist"; exit 1; }

# When — invoke CLI with an empty string argument

echo "STEP: When — execute CLI with empty question argument"
echo "REQUEST_HEADERS: CLI invocation has no HTTP headers"
echo "REQUEST_BODY: <empty string>"
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

# Then — assert graceful handling without crash

echo "STEP: Then — verify empty question is handled gracefully"
if [ "$EXIT_CODE" = "0" ] || [ "$EXIT_CODE" = "1" ]; then :; else echo "ASSERTION_FAILED: expected exit code 0 or 1 for graceful handling, got ${EXIT_CODE}"; exit 1; fi
grep -F 'Question:' "$STDOUT_FILE" >/dev/null 2>&1 || { echo "ASSERTION_FAILED: expected stdout to contain Question label"; exit 1; }
grep -F 'Creating SQL Agent...' "$STDOUT_FILE" >/dev/null 2>&1 || { echo "ASSERTION_FAILED: expected stdout to contain creation status"; exit 1; }
grep -F 'Processing query...' "$STDOUT_FILE" >/dev/null 2>&1 || { echo "ASSERTION_FAILED: expected stdout to contain processing status"; exit 1; }
if grep -F 'Answer:' "$STDOUT_FILE" >/dev/null 2>&1 || grep -F 'Error:' "$STDOUT_FILE" >/dev/null 2>&1; then :; else echo "ASSERTION_FAILED: expected stdout to contain either Answer or Error panel"; exit 1; fi
if grep -Ei 'traceback' "$STDOUT_FILE" "$STDERR_FILE" >/dev/null 2>&1; then echo "ASSERTION_FAILED: did not expect unhandled traceback for empty question"; exit 1; fi

# Cleanup — no side effects to undo

echo "STEP: Cleanup — no cleanup required for empty question test"
echo "CODEVALID_TEST_ASSERTION_OK:empty_question_argument"
