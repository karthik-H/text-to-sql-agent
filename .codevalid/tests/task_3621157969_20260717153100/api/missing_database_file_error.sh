#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
CASE_SUFFIX="$(date +%s)_$$"
CASE_ID="missing_database_file_error_${CASE_SUFFIX}"
QUESTION='How many albums are in the database?'
TMP_DIR="$(mktemp -d)"
STDOUT_FILE="$TMP_DIR/stdout.txt"
STDERR_FILE="$TMP_DIR/stderr.txt"
RESTORE_PATH="/app/chinook.db.codevalid_backup_${CASE_SUFFIX}"
cleanup_restore() {
  if [ -f "$RESTORE_PATH" ]; then
    mv "$RESTORE_PATH" /app/chinook.db
  fi
  rm -rf "$TMP_DIR"
}
trap cleanup_restore EXIT

# Given — temporarily remove database file

echo "STEP: Given — move chinook.db away to simulate missing database file"
echo "PREREQ: checking original chinook.db exists before rename"
[ -f /app/chinook.db ] || { echo "ASSERTION_FAILED: expected /app/chinook.db to exist before test"; exit 1; }
mv /app/chinook.db "$RESTORE_PATH"
[ ! -f /app/chinook.db ] || { echo "ASSERTION_FAILED: expected /app/chinook.db to be absent after rename"; exit 1; }

# When — invoke CLI while database file is missing

echo "STEP: When — execute CLI with missing database file"
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

# Then — assert graceful error handling

echo "STEP: Then — verify error panel is displayed and process exits non-zero"
[ "$EXIT_CODE" = "1" ] || { echo "ASSERTION_FAILED: expected exit code 1 got ${EXIT_CODE}"; exit 1; }
grep -F 'Question:' "$STDOUT_FILE" >/dev/null 2>&1 || { echo "ASSERTION_FAILED: expected stdout to contain Question label before failure"; exit 1; }
grep -F 'Creating SQL Agent...' "$STDOUT_FILE" >/dev/null 2>&1 || { echo "ASSERTION_FAILED: expected stdout to contain creation status before failure"; exit 1; }
grep -F 'Error:' "$STDOUT_FILE" >/dev/null 2>&1 || { echo "ASSERTION_FAILED: expected stdout to contain Error panel label"; exit 1; }
if grep -Ei 'no such table|unable to open database file|database|sqlite' "$STDOUT_FILE" "$STDERR_FILE" >/dev/null 2>&1; then :; else echo "ASSERTION_FAILED: expected output to mention database failure details"; exit 1; fi
if grep -F 'Answer:' "$STDOUT_FILE" >/dev/null 2>&1; then echo "ASSERTION_FAILED: did not expect Answer panel on missing database path"; exit 1; fi

# Cleanup — restore database file

echo "STEP: Cleanup — restore original chinook.db file"
mv "$RESTORE_PATH" /app/chinook.db
[ -f /app/chinook.db ] || { echo "ASSERTION_FAILED: expected chinook.db to be restored during cleanup"; exit 1; }
echo "CODEVALID_TEST_ASSERTION_OK:missing_database_file_error"
