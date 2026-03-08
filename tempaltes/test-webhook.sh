#!/bin/bash
# ═══════════════════════════════════════════════════════════════
# Тестирование remnawave-webhook шаблона
# Имитирует запросы от Remnawave с правильной HMAC подписью
# ═══════════════════════════════════════════════════════════════

BASE_URL="https://admin.ev-agency.io/shm/v1/public/remnawave-webhook"
SECRET="vsmu67Kmg6R8FjIOF1WUY8LWBHie4scdEqrfsKmyf4IAf8dY3nFS0wwYHkhh6ZvQ"

# Цвета для вывода
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

send_webhook() {
    local test_name="$1"
    local body="$2"
    local extra_header="${3:-}"

    # HMAC-SHA256 подпись (как Remnawave)
    local signature
    signature=$(printf '%s' "$body" | openssl dgst -sha256 -hmac "$SECRET" -hex 2>/dev/null | awk '{print $NF}')

    echo -e "\n${CYAN}━━━ TEST: ${test_name} ━━━${NC}"

    local headers=(-H "Content-Type: application/json" -H "X-Remnawave-Signature: ${signature}")
    if [ -n "$extra_header" ]; then
        headers+=(-H "$extra_header")
    fi

    local response
    response=$(curl -s -w "\n%{http_code}" -X POST "$BASE_URL" "${headers[@]}" -d "$body" 2>&1)

    local http_code
    http_code=$(echo "$response" | tail -1)
    local body_response
    body_response=$(echo "$response" | sed '$d')

    if echo "$body_response" | grep -q '"success"'; then
        echo -e "  ${GREEN}✅ PASS${NC} (HTTP $http_code)"
    elif echo "$body_response" | grep -q '"skip"'; then
        echo -e "  ${YELLOW}⏭️  SKIP${NC} (HTTP $http_code)"
    elif echo "$body_response" | grep -q '"error"'; then
        echo -e "  ${RED}❌ ERROR${NC} (HTTP $http_code)"
    else
        echo -e "  ${YELLOW}⚠️  UNKNOWN${NC} (HTTP $http_code)"
    fi
    echo "  Response: $body_response"
}

echo -e "${CYAN}╔══════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║     REMNAWAVE WEBHOOK — INTEGRATION TESTS           ║${NC}"
echo -e "${CYAN}║     URL: ${BASE_URL}${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════════════════╝${NC}"


# ─── TEST 0: Без подписи — должен вернуть Unauthorized ───
echo -e "\n${CYAN}━━━ TEST 0: Missing signature (security check) ━━━${NC}"
response=$(curl -s -X POST "$BASE_URL" \
    -H "Content-Type: application/json" \
    -d '{"event":"user.not_connected","scope":"user","data":{"username":"HACK_ATTEMPT"}}' 2>&1)
if echo "$response" | grep -q 'Unauthorized'; then
    echo -e "  ${GREEN}✅ PASS${NC} — Rejected without signature"
else
    echo -e "  ${RED}❌ FAIL${NC} — Should have been rejected!"
fi
echo "  Response: $response"


# ─── TEST 1: user.not_connected — стадия 1 (6ч) ───
send_webhook "not_connected: stage 1 (6h)" '{
    "scope": "user",
    "event": "user.not_connected",
    "timestamp": "2026-03-08T17:00:00Z",
    "data": {
        "uuid": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
        "username": "HQVPN_TEST001",
        "telegramId": null,
        "status": "ACTIVE",
        "subscriptionUrl": "https://p.z-hq.com/sub/test-sub-url",
        "userTraffic": {
            "firstConnectedAt": null,
            "onlineAt": null,
            "usedTrafficBytes": 0
        },
        "trafficLimitBytes": 107374182400
    },
    "meta": {
        "notConnectedAfterHours": 6
    }
}'


# ─── TEST 2: user.not_connected — стадия 2 (24ч) ───
send_webhook "not_connected: stage 2 (24h)" '{
    "scope": "user",
    "event": "user.not_connected",
    "timestamp": "2026-03-08T17:00:00Z",
    "data": {
        "uuid": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
        "username": "HQVPN_TEST001",
        "telegramId": null,
        "status": "ACTIVE",
        "subscriptionUrl": "https://p.z-hq.com/sub/test-sub-url",
        "userTraffic": {
            "firstConnectedAt": null,
            "onlineAt": null,
            "usedTrafficBytes": 0
        },
        "trafficLimitBytes": 107374182400
    },
    "meta": {
        "notConnectedAfterHours": 24
    }
}'


# ─── TEST 3: user.not_connected — стадия 3 (48ч) ───
send_webhook "not_connected: stage 3 (48h)" '{
    "scope": "user",
    "event": "user.not_connected",
    "timestamp": "2026-03-08T17:00:00Z",
    "data": {
        "uuid": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
        "username": "HQVPN_TEST001",
        "telegramId": null,
        "status": "ACTIVE",
        "subscriptionUrl": "https://p.z-hq.com/sub/test-sub-url",
        "userTraffic": {
            "firstConnectedAt": null,
            "onlineAt": null,
            "usedTrafficBytes": 0
        },
        "trafficLimitBytes": 107374182400
    },
    "meta": {
        "notConnectedAfterHours": 48
    }
}'


# ─── TEST 4: user.not_connected — не ACTIVE (skip) ───
send_webhook "not_connected: not ACTIVE (should skip)" '{
    "scope": "user",
    "event": "user.not_connected",
    "timestamp": "2026-03-08T17:00:00Z",
    "data": {
        "uuid": "b2c3d4e5-f6a7-8901-bcde-f12345678901",
        "username": "HQVPN_TEST002",
        "telegramId": null,
        "status": "DISABLED",
        "subscriptionUrl": "",
        "userTraffic": {},
        "trafficLimitBytes": 0
    },
    "meta": {
        "notConnectedAfterHours": 6
    }
}'


# ─── TEST 5: user.first_connected ───
send_webhook "first_connected" '{
    "scope": "user",
    "event": "user.first_connected",
    "timestamp": "2026-03-08T18:00:00Z",
    "data": {
        "uuid": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
        "username": "HQVPN_TEST001",
        "telegramId": null,
        "status": "ACTIVE",
        "subscriptionUrl": "https://p.z-hq.com/sub/test-sub-url",
        "userTraffic": {
            "firstConnectedAt": "2026-03-08T18:00:00Z",
            "onlineAt": "2026-03-08T18:00:00Z",
            "usedTrafficBytes": 1048576
        },
        "trafficLimitBytes": 107374182400
    },
    "meta": {}
}'


# ─── TEST 6: user.bandwidth_usage_threshold_reached — 80% ───
send_webhook "bandwidth 80%" '{
    "scope": "user",
    "event": "user.bandwidth_usage_threshold_reached",
    "timestamp": "2026-03-08T20:00:00Z",
    "data": {
        "uuid": "c3d4e5f6-a7b8-9012-cdef-123456789012",
        "username": "HQVPN_TEST003",
        "telegramId": null,
        "status": "ACTIVE",
        "subscriptionUrl": "https://p.z-hq.com/sub/test-sub-url-3",
        "userTraffic": {
            "firstConnectedAt": "2026-03-01T10:00:00Z",
            "onlineAt": "2026-03-08T20:00:00Z",
            "usedTrafficBytes": 85899345920
        },
        "trafficLimitBytes": 107374182400
    },
    "meta": {
        "thresholdPercent": 80
    }
}'


# ─── TEST 7: user.bandwidth_usage_threshold_reached — 95% ───
send_webhook "bandwidth 95% (critical)" '{
    "scope": "user",
    "event": "user.bandwidth_usage_threshold_reached",
    "timestamp": "2026-03-08T22:00:00Z",
    "data": {
        "uuid": "c3d4e5f6-a7b8-9012-cdef-123456789012",
        "username": "HQVPN_TEST003",
        "telegramId": null,
        "status": "ACTIVE",
        "subscriptionUrl": "https://p.z-hq.com/sub/test-sub-url-3",
        "userTraffic": {
            "firstConnectedAt": "2026-03-01T10:00:00Z",
            "onlineAt": "2026-03-08T22:00:00Z",
            "usedTrafficBytes": 102005473280
        },
        "trafficLimitBytes": 107374182400
    },
    "meta": {
        "thresholdPercent": 95
    }
}'


# ─── TEST 8: user.expired ───
send_webhook "user.expired" '{
    "scope": "user",
    "event": "user.expired",
    "timestamp": "2026-03-08T23:00:00Z",
    "data": {
        "uuid": "d4e5f6a7-b8c9-0123-defa-234567890123",
        "username": "HQVPN_TEST004",
        "telegramId": null,
        "status": "EXPIRED",
        "subscriptionUrl": "",
        "userTraffic": {},
        "trafficLimitBytes": 0
    },
    "meta": {}
}'


# ─── TEST 9: user.expires_in_24h ───
send_webhook "user.expires_in_24h" '{
    "scope": "user",
    "event": "user.expires_in_24h",
    "timestamp": "2026-03-08T12:00:00Z",
    "data": {
        "uuid": "e5f6a7b8-c9d0-1234-efab-345678901234",
        "username": "HQVPN_TEST005",
        "telegramId": null,
        "status": "ACTIVE",
        "subscriptionUrl": "https://p.z-hq.com/sub/test-sub-url-5",
        "userTraffic": {},
        "trafficLimitBytes": 107374182400
    },
    "meta": {}
}'


# ─── TEST 10: Ignored user.* event (should be silently skipped) ───
send_webhook "user.updated (ignored)" '{
    "scope": "user",
    "event": "user.updated",
    "timestamp": "2026-03-08T15:00:00Z",
    "data": {
        "uuid": "f6a7b8c9-d0e1-2345-fabc-456789012345",
        "username": "HQVPN_TEST006",
        "status": "ACTIVE"
    },
    "meta": {}
}'

# ─── TEST 11: Non-user event (catch-all → admin log) ───
send_webhook "system event (catch-all)" '{
    "scope": "system",
    "event": "system.startup",
    "timestamp": "2026-03-08T15:00:00Z",
    "data": {},
    "meta": {}
}'

# ─── TEST 12: Missing event field ───
send_webhook "missing event (should error)" '{
    "scope": "user",
    "data": {
        "username": "HQVPN_BAD"
    }
}'


echo -e "\n${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${CYAN}  Tests complete! Check admin Telegram for messages.${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
