#!/bin/bash
set -e

NAMESPACE="${1:-asiayo}"
PRIMARY_SVC="mysql-primary"
SECONDARY_SVC="mysql-secondary"
ROOT_PASSWORD=$(kubectl get secret mysql-secret -n "$NAMESPACE" -o jsonpath='{.data.MYSQL_ROOT_PASSWORD}' | base64 -d)
APP_PASSWORD=$(kubectl get secret mysql-secret -n "$NAMESPACE" -o jsonpath='{.data.MYSQL_PASSWORD}' | base64 -d)
TEST_DB="appdb"
TEST_TABLE="rw_test"
TEST_VALUE="hello-$(date +%s)"
PASSED=0
FAILED=0

pass() { echo "  ✅ PASS: $1"; PASSED=$((PASSED+1)); }
fail() { echo "  ❌ FAIL: $1"; FAILED=$((FAILED+1)); }

# Run SQL and show command + output
# Verbose info goes to stderr (always visible), SQL result goes to stdout (capturable)
# Usage: run_sql <pod> <user> <password> <sql>
run_sql() {
  local pod="$1" user="$2" pass="$3" sql="$4"
  echo "  [CMD] kubectl exec ${pod} -n ${NAMESPACE} -- mysql -u${user} -p*** -N -e \"${sql}\"" >&2
  local output exit_code=0
  output=$(kubectl exec "$pod" -n "$NAMESPACE" -- mysql -u"$user" -p"$pass" -N -e "$sql" 2>&1) || exit_code=$?
  if [ $exit_code -ne 0 ]; then
    echo "  [EXIT] ${exit_code}" >&2
    echo "$output" | sed 's/^/  [OUTPUT] /' >&2
    return $exit_code
  fi
  if [ -n "$output" ]; then
    echo "$output" | sed 's/^/  [OUTPUT] /' >&2
  else
    echo "  [OUTPUT] (empty - command succeeded)" >&2
  fi
  echo "$output"
  return 0
}

# Run SQL with full output (no -N, for SHOW STATUS etc.)
# Verbose info goes to stderr, full result goes to stdout
run_sql_full() {
  local pod="$1" user="$2" pass="$3" sql="$4"
  echo "  [CMD] kubectl exec ${pod} -n ${NAMESPACE} -- mysql -u${user} -p*** -e \"${sql}\"" >&2
  local output exit_code=0
  output=$(kubectl exec "$pod" -n "$NAMESPACE" -- bash -c "mysql -u${user} -p'${pass}' -e '${sql}' 2>/dev/null" 2>/dev/null) || exit_code=$?
  if [ $exit_code -ne 0 ]; then
    echo "  [EXIT] ${exit_code}" >&2
    return $exit_code
  fi
  if [ -n "$output" ]; then
    echo "$output" | sed 's/^/  [OUTPUT] /' >&2
  else
    echo "  [OUTPUT] (empty)" >&2
  fi
  echo "$output"
  return 0
}

echo "=========================================="
echo " MySQL Read/Write Separation Test"
echo " Namespace: ${NAMESPACE}"
echo " Primary:   mysql-primary-0"
echo " Secondary: mysql-secondary-0"
echo " Test DB:   ${TEST_DB}"
echo " Test Value: ${TEST_VALUE}"
echo "=========================================="

# --- Test 1: Primary is writable ---
echo ""
echo "[Test 1] Primary - Write (CREATE TABLE + INSERT)"
SQL="USE ${TEST_DB}; CREATE TABLE IF NOT EXISTS ${TEST_TABLE} (id INT AUTO_INCREMENT PRIMARY KEY, val VARCHAR(255), ts TIMESTAMP DEFAULT CURRENT_TIMESTAMP); INSERT INTO ${TEST_TABLE} (val) VALUES ('${TEST_VALUE}');"
if run_sql mysql-primary-0 root "$ROOT_PASSWORD" "$SQL" >/dev/null; then
  pass "Primary accepts writes"
else
  fail "Primary rejects writes"
fi

# --- Test 2: Read from Primary ---
echo ""
echo "[Test 2] Primary - Read"
SQL="SELECT val FROM ${TEST_DB}.${TEST_TABLE} ORDER BY id DESC LIMIT 1;"
RESULT=$(run_sql mysql-primary-0 root "$ROOT_PASSWORD" "$SQL" | tail -1)
if [ "$RESULT" = "$TEST_VALUE" ]; then
  pass "Primary read returns correct value"
else
  fail "Primary read returned unexpected value (expected: ${TEST_VALUE}, got: ${RESULT})"
fi

# --- Test 3: Replication check - Read from Secondary ---
echo ""
echo "[Test 3] Secondary - Read (replication check)"
echo "  Waiting 5s for replication sync..."
sleep 5
SQL="SELECT val FROM ${TEST_DB}.${TEST_TABLE} ORDER BY id DESC LIMIT 1;"
RESULT=$(run_sql mysql-secondary-0 root "$ROOT_PASSWORD" "$SQL" | tail -1)
if [ "$RESULT" = "$TEST_VALUE" ]; then
  pass "Secondary replicated data correctly"
else
  fail "Secondary data mismatch (expected: ${TEST_VALUE}, got: ${RESULT})"
fi

# --- Test 4: Secondary rejects writes ---
echo ""
echo "[Test 4] Secondary - Write (should fail)"
SQL="INSERT INTO ${TEST_DB}.${TEST_TABLE} (val) VALUES ('should-fail');"
if run_sql mysql-secondary-0 root "$ROOT_PASSWORD" "$SQL" >/dev/null 2>/dev/null; then
  fail "Secondary accepted write (should be read-only)"
else
  pass "Secondary correctly rejects writes (read-only)"
fi

# --- Test 5: Replication status on Secondary ---
echo ""
echo "[Test 5] Secondary - Replication Status"
REPL_OUTPUT=$(run_sql_full mysql-secondary-0 root "$ROOT_PASSWORD" "SHOW REPLICA STATUS\G" || \
              run_sql_full mysql-secondary-0 root "$ROOT_PASSWORD" "SHOW SLAVE STATUS\G" || true)
IO_RUNNING=$(echo "$REPL_OUTPUT" | grep -oP "(Replica_IO|Slave_IO)_Running:\s*Yes" || true)
SQL_RUNNING=$(echo "$REPL_OUTPUT" | grep -oP "(Replica_SQL|Slave_SQL)_Running:\s*Yes" || true)
if [ -n "$IO_RUNNING" ] && [ -n "$SQL_RUNNING" ]; then
  pass "Replication IO & SQL threads running"
else
  echo "  Debug - key replication fields:"
  echo "$REPL_OUTPUT" | grep -iE "(running|error|behind|state|host|port)" | sed 's/^/    /' || echo "    (empty - replication not configured)"
  fail "Replication threads not healthy (IO: ${IO_RUNNING:-No}, SQL: ${SQL_RUNNING:-No})"
fi

# --- Test 6: appuser can read/write via Primary ---
echo ""
echo "[Test 6] appuser - Write via Primary"
SQL="INSERT INTO ${TEST_DB}.${TEST_TABLE} (val) VALUES ('appuser-write');"
if run_sql mysql-primary-0 appuser "$APP_PASSWORD" "$SQL" >/dev/null; then
  pass "appuser can write to Primary"
else
  fail "appuser cannot write to Primary"
fi

# --- Test 7: appuser can read via Secondary ---
echo ""
echo "[Test 7] appuser - Read via Secondary"
echo "  Waiting 3s for replication sync..."
sleep 3
SQL="SELECT val FROM ${TEST_DB}.${TEST_TABLE} WHERE val='appuser-write' LIMIT 1;"
RESULT=$(run_sql mysql-secondary-0 appuser "$APP_PASSWORD" "$SQL" | tail -1)
if [ "$RESULT" = "appuser-write" ]; then
  pass "appuser can read from Secondary"
else
  fail "appuser cannot read from Secondary (got: ${RESULT})"
fi

# --- Test 8: appuser write to Secondary should fail ---
echo ""
echo "[Test 8] appuser - Write via Secondary (should fail)"
SQL="INSERT INTO ${TEST_DB}.${TEST_TABLE} (val) VALUES ('appuser-should-fail');"
if run_sql mysql-secondary-0 appuser "$APP_PASSWORD" "$SQL" >/dev/null 2>/dev/null; then
  fail "appuser can write to Secondary (should be read-only)"
else
  pass "appuser correctly blocked from writing to Secondary"
fi

# --- Cleanup ---
echo ""
echo "[Cleanup] Dropping test table..."
run_sql mysql-primary-0 root "$ROOT_PASSWORD" "DROP TABLE IF EXISTS ${TEST_DB}.${TEST_TABLE};" >/dev/null || true

# --- Summary ---
echo ""
echo "=========================================="
echo " Results: ${PASSED} passed, ${FAILED} failed"
echo "=========================================="

if [ "$FAILED" -gt 0 ]; then
  exit 1
fi
