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

run_sql_primary() {
  kubectl exec mysql-primary-0 -n "$NAMESPACE" -- \
    mysql -uroot -p"$ROOT_PASSWORD" -N -e "$1" 2>/dev/null
}

run_sql_secondary() {
  kubectl exec mysql-secondary-0 -n "$NAMESPACE" -- \
    mysql -uroot -p"$ROOT_PASSWORD" -N -e "$1" 2>/dev/null
}

run_sql_appuser_primary() {
  kubectl exec mysql-primary-0 -n "$NAMESPACE" -- \
    mysql -uappuser -p"$APP_PASSWORD" -N -e "$1" 2>/dev/null
}

run_sql_appuser_secondary() {
  kubectl exec mysql-secondary-0 -n "$NAMESPACE" -- \
    mysql -uappuser -p"$APP_PASSWORD" -N -e "$1" 2>/dev/null
}

echo "=========================================="
echo " MySQL Read/Write Separation Test"
echo " Namespace: ${NAMESPACE}"
echo "=========================================="

# --- Test 1: Primary is writable ---
echo ""
echo "[Test 1] Primary - Write (CREATE TABLE + INSERT)"
if run_sql_primary "USE ${TEST_DB}; CREATE TABLE IF NOT EXISTS ${TEST_TABLE} (id INT AUTO_INCREMENT PRIMARY KEY, val VARCHAR(255), ts TIMESTAMP DEFAULT CURRENT_TIMESTAMP); INSERT INTO ${TEST_TABLE} (val) VALUES ('${TEST_VALUE}');"; then
  pass "Primary accepts writes"
else
  fail "Primary rejects writes"
fi

# --- Test 2: Read from Primary ---
echo ""
echo "[Test 2] Primary - Read"
RESULT=$(run_sql_primary "SELECT val FROM ${TEST_DB}.${TEST_TABLE} ORDER BY id DESC LIMIT 1;")
if [ "$RESULT" = "$TEST_VALUE" ]; then
  pass "Primary read returns correct value: ${RESULT}"
else
  fail "Primary read returned unexpected value: ${RESULT}"
fi

# --- Test 3: Replication check - Read from Secondary ---
echo ""
echo "[Test 3] Secondary - Read (replication check)"
echo "  Waiting for replication sync..."
sleep 3
RESULT=$(run_sql_secondary "SELECT val FROM ${TEST_DB}.${TEST_TABLE} ORDER BY id DESC LIMIT 1;")
if [ "$RESULT" = "$TEST_VALUE" ]; then
  pass "Secondary replicated data correctly: ${RESULT}"
else
  fail "Secondary read returned unexpected value: ${RESULT} (expected: ${TEST_VALUE})"
fi

# --- Test 4: Secondary rejects writes ---
echo ""
echo "[Test 4] Secondary - Write (should fail)"
if run_sql_secondary "INSERT INTO ${TEST_DB}.${TEST_TABLE} (val) VALUES ('should-fail');" 2>&1; then
  fail "Secondary accepted write (should be read-only)"
else
  pass "Secondary correctly rejects writes (read-only)"
fi

# --- Test 5: Replication status on Secondary ---
echo ""
echo "[Test 5] Secondary - Replication Status"
# Try SHOW REPLICA STATUS (MySQL 8.0.22+), fallback to SHOW SLAVE STATUS
REPL_OUTPUT=$(run_sql_secondary "SHOW REPLICA STATUS\G" 2>/dev/null || run_sql_secondary "SHOW SLAVE STATUS\G" 2>/dev/null || true)
IO_RUNNING=$(echo "$REPL_OUTPUT" | grep -oP "(Replica_IO|Slave_IO)_Running:\s*Yes" || true)
SQL_RUNNING=$(echo "$REPL_OUTPUT" | grep -oP "(Replica_SQL|Slave_SQL)_Running:\s*Yes" || true)
if [ -n "$IO_RUNNING" ] && [ -n "$SQL_RUNNING" ]; then
  pass "Replication IO & SQL threads running"
else
  echo "  Debug: replication output:"
  echo "$REPL_OUTPUT" | grep -iE "(running|error|behind)" || true
  fail "Replication threads not healthy (IO: ${IO_RUNNING:-No}, SQL: ${SQL_RUNNING:-No})"
fi

# --- Test 6: appuser can read/write via Primary ---
echo ""
echo "[Test 6] appuser - Write via Primary"
if run_sql_appuser_primary "INSERT INTO ${TEST_DB}.${TEST_TABLE} (val) VALUES ('appuser-write');"; then
  pass "appuser can write to Primary"
else
  fail "appuser cannot write to Primary"
fi

# --- Test 7: appuser can read via Secondary ---
echo ""
echo "[Test 7] appuser - Read via Secondary"
sleep 2
RESULT=$(run_sql_appuser_secondary "SELECT val FROM ${TEST_DB}.${TEST_TABLE} WHERE val='appuser-write' LIMIT 1;")
if [ "$RESULT" = "appuser-write" ]; then
  pass "appuser can read from Secondary"
else
  fail "appuser cannot read from Secondary (got: ${RESULT})"
fi

# --- Test 8: appuser write to Secondary should fail ---
echo ""
echo "[Test 8] appuser - Write via Secondary (should fail)"
if run_sql_appuser_secondary "INSERT INTO ${TEST_DB}.${TEST_TABLE} (val) VALUES ('appuser-should-fail');" 2>&1; then
  fail "appuser can write to Secondary (should be read-only)"
else
  pass "appuser correctly blocked from writing to Secondary"
fi

# --- Cleanup ---
echo ""
echo "[Cleanup] Dropping test table..."
run_sql_primary "DROP TABLE IF EXISTS ${TEST_DB}.${TEST_TABLE};" || true

# --- Summary ---
echo ""
echo "=========================================="
echo " Results: ${PASSED} passed, ${FAILED} failed"
echo "=========================================="

if [ "$FAILED" -gt 0 ]; then
  exit 1
fi
