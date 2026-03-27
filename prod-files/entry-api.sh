#!/bin/sh -e

# Add IP addresses to geo block for rate limit exclusion
if [ -n "$TRUSTED_IPS" ]; then
    for ip in $(echo "$TRUSTED_IPS" | tr ',' ' '); do
        ip=$(echo "$ip" | tr -d ' ')
        if [ -n "$ip" ]; then
            sed -i "/default \$binary_remote_addr;/i\\        $ip \"\";" /etc/nginx/nginx.conf
        fi
    done
fi

# Replace TRUSTED_IPS placeholder
if [ -n "$TRUSTED_IPS" ]; then
    sed -i "s|TRUSTED_IPS_PLACEHOLDER|$TRUSTED_IPS|g" /etc/nginx/nginx.conf
else
    sed -i "s|TRUSTED_IPS_PLACEHOLDER||g" /etc/nginx/nginx.conf
fi

# Disable rate limiting if not enabled
if [ "$ENABLE_RATE_LIMIT" != "true" ]; then
    sed -i 's/limit_req_zone/#limit_req_zone/' /etc/nginx/nginx.conf
    sed -i 's/limit_req zone/#limit_req zone/' /etc/nginx/nginx.conf
    sed -i 's/limit_req_status/#limit_req_status/' /etc/nginx/nginx.conf
    sed -i 's/limit_req_log_level/#limit_req_log_level/' /etc/nginx/nginx.conf
fi

# Inject WebSocket location if config file exists (only once)
if [ -f /etc/nginx/ws-location.conf ] && ! grep -q "ws-location" /etc/nginx/nginx.conf; then
    sed -i '/location = \/shm\/healthcheck.cgi/i \        include /etc/nginx/ws-location.conf;' /etc/nginx/nginx.conf
    echo "WebSocket location injected into nginx.conf"
fi

# Inject SSE location if config file exists (only once)
if [ -f /etc/nginx/sse-location.conf ] && ! grep -q "sse-location" /etc/nginx/nginx.conf; then
    sed -i '/location = \/shm\/healthcheck.cgi/i \        include /etc/nginx/sse-location.conf;' /etc/nginx/nginx.conf
    echo "SSE location injected into nginx.conf"
fi

nginx -g "daemon off;"
