#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
CASE_SUFFIX="$(date +%s)_$$"
CASE_ID="special_characters_in_question_${CASE_SUFFIX}"
QUESTION="What's the average track length in minutes? (include milliseconds conversion)"
TMP_DIR="$(mktemp -d)"
STDOUT_FILE="$TMP_DIR/stdout.txt"
STDERR_FILE="$TMP_DIR/stderr.txt"
cleanup_tmp() {
  rm -rf "$TMP_DIR"
}
trap cleanup_tmp EXIT

# Given — verify CLI prerequisites

echo "STEP: Given — verify special character question prerequisites"
echo "PREREQ: checking agent.py exists"
[ -f /app/agent.py ] || { echo "ASSERTION_FAILED: expected /app/agent.py to exist"; exit 1; }
echo "PREREQ: checking chinook.db exists"
[ -f /app/chinook.db ] || { echo "ASSERTION_FAILED: expected /app/chinook.db to exist"; exit 1; }

# When — invoke CLI with punctuation and parentheses in the question

echo "STEP: When — execute CLI with special characters in natural language question"
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

# Then — assert successful parsing and readable answer

echo "STEP: Then — verify special characters are handled without parsing failures"
[ "$EXIT_CODE" = "0" ] || { echo "ASSERTION_FAILED: expected exit code 0 got ${EXIT_CODE}"; exit 1; }
grep -F "What's the average track length in minutes? (include milliseconds conversion)" "$STDOUT_FILE" >/dev/null 2>&1 || { echo "ASSERTION_FAILED: expected stdout to echo full question text with special characters"; exit 1; }
grep -F 'Answer:' "$STDOUT_FILE" >/dev/null 2>&1 || { echo "ASSERTION_FAILED: expected stdout to contain Answer label"; exit 1; }
if grep -Ei 'minute|millisecond|average|track length' "$STDOUT_FILE" >/dev/null 2>&1; then :; else echo "ASSERTION_FAILED: expected stdout to contain average track length content"; exit 1; fi
if grep -Ei 'syntax error|Traceback|Error:' "$STDOUT_FILE" "$STDERR_FILE" >/dev/null 2>&1; then echo "ASSERTION_FAILED: did not expect parsing or SQL syntax errors for special-character question"; exit 1; fi

# Cleanup — no side effects to undo

echo "STEP: Cleanup — no cleanup required for read-only CLI query"
echo "CODEVALID_TEST_ASSERTION_OK:special_characters_in_question"
