#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
CASE_SUFFIX="$(date +%s)_$$"
CASE_ID="model_api_failure_handling_${CASE_SUFFIX}"
QUESTION='How many tracks are in the database?'
TMP_DIR="$(mktemp -d)"
STDOUT_FILE="$TMP_DIR/stdout.txt"
STDERR_FILE="$TMP_DIR/stderr.txt"
cleanup_tmp() {
  rm -rf "$TMP_DIR"
}
trap cleanup_tmp EXIT

# Given — force invalid model credentials for this invocation

echo "STEP: Given — configure invalid Anthropic credentials to trigger model API failure"
echo "PREREQ: checking agent.py exists"
[ -f /app/agent.py ] || { echo "ASSERTION_FAILED: expected /app/agent.py to exist"; exit 1; }
export ANTHROPIC_API_KEY="codevalid_invalid_key_${CASE_SUFFIX}"

# When — invoke CLI while model API should fail

echo "STEP: When — execute CLI with invalid model credentials"
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

# Then — assert graceful error panel and non-zero exit

echo "STEP: Then — verify model API failure is surfaced via error panel"
[ "$EXIT_CODE" = "1" ] || { echo "ASSERTION_FAILED: expected exit code 1 got ${EXIT_CODE}"; exit 1; }
grep -F 'Creating SQL Agent...' "$STDOUT_FILE" >/dev/null 2>&1 || { echo "ASSERTION_FAILED: expected stdout to contain creation status"; exit 1; }
grep -F 'Processing query...' "$STDOUT_FILE" >/dev/null 2>&1 || { echo "ASSERTION_FAILED: expected stdout to contain processing status"; exit 1; }
grep -F 'Error:' "$STDOUT_FILE" >/dev/null 2>&1 || { echo "ASSERTION_FAILED: expected stdout to contain Error panel label"; exit 1; }
if grep -Ei 'auth|authentication|api key|unauthorized|forbidden|network|anthropic|error' "$STDOUT_FILE" "$STDERR_FILE" >/dev/null 2>&1; then :; else echo "ASSERTION_FAILED: expected output to mention model API failure details"; exit 1; fi
if grep -F 'Answer:' "$STDOUT_FILE" >/dev/null 2>&1; then echo "ASSERTION_FAILED: did not expect Answer panel on API failure"; exit 1; fi

# Cleanup — unset injected invalid credential

echo "STEP: Cleanup — remove invalid Anthropic credential override"
unset ANTHROPIC_API_KEY
echo "CODEVALID_TEST_ASSERTION_OK:model_api_failure_handling"
