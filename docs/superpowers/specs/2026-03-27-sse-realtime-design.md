# Dual-Protocol Realtime Server (SSE + WebSocket)

**Date:** 2026-03-27
**Status:** Approved

## Problem

SHM needs real-time notifications (balance updates, service status changes) from server to browser. WebSocket through `remnawave/caddy-with-auth` proxy fails — the caddy-security plugin breaks the WebSocket tunnel over HTTP/2. SSE works through any HTTP proxy without special protocol support.

## Solution

Single `realtime-server.pl` process that supports both SSE and WebSocket on the same port (9083). Determines protocol by HTTP headers on each connection. SSE is the default transport for the wbap frontend; WebSocket remains as a fallback for deployments without Caddy.

## Architecture

```
Browser (EventSource) → Caddy (z-hq.com/sse) → nginx (api:80, location /sse) → realtime-server.pl :9083
                                                                                 ↑
                                              Redis pub/sub (shm:events) ←── DataNotify.pm
```

## Server: realtime-server.pl

Replaces `ws-server.pl`. Same file, extended to handle both protocols.

### Protocol Detection

On `accept_client`, the server reads the HTTP request headers:
- If `Upgrade: websocket` header present → WebSocket handshake (existing logic)
- Otherwise → SSE response

### Client State

```perl
$clients{$fn} = {
    sock           => $sock,
    user_id        => 0,
    type           => undef,   # 'ws' | 'sse'
    buf            => '',
    handshake_done => 0,
};
```

### SSE Handshake

For SSE clients, `do_handshake` sends:

```
HTTP/1.1 200 OK\r\n
Content-Type: text/event-stream\r\n
Cache-Control: no-cache\r\n
Connection: keep-alive\r\n
Access-Control-Allow-Origin: *\r\n
X-Accel-Buffering: no\r\n
\r\n
```

`X-Accel-Buffering: no` tells nginx not to buffer the response. `user_id` is extracted from the query string (same as WebSocket).

### Event Dispatch

`dispatch_event` checks `$c->{type}`:
- **SSE:** `"data: $json\n\n"` (plain text, newline-delimited)
- **WS:** `ws_encode_text($json)` (binary WebSocket frame, existing logic)

### Keepalive

- **SSE:** send `:ping\n\n` (SSE comment, ignored by EventSource) every 30 seconds
- **WS:** send WebSocket ping frame every 30 seconds (existing logic)

### Cleanup

SSE clients are removed when `sysread` returns 0 (client disconnected). Same as WebSocket.

## Nginx: sse-location.conf

New file `prod-files/sse-location.conf`:

```nginx
location /sse {
    proxy_pass http://core:9083;
    proxy_http_version 1.1;
    proxy_set_header Connection '';
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_buffering off;
    proxy_cache off;
    proxy_read_timeout 86400s;
    proxy_send_timeout 86400s;
    chunked_transfer_encoding off;
}
```

Key differences from ws-location.conf: no `Upgrade` headers, `proxy_buffering off`, empty `Connection` header (keep-alive).

Injected into nginx.conf by `entry-api.sh` (same pattern as ws-location.conf).

## Caddy: z-hq.com block

Add before the catch-all `handle`:

```caddy
handle /sse {
    reverse_proxy http://api:80
}
```

No special WebSocket config needed — it's a regular HTTP long-lived response.

## Frontend

### useSSEUpdates.ts (new)

```typescript
export function useSSEUpdates(config) {
  // EventSource to /sse?user_id=N
  // Auto-reconnect is built into EventSource API
  // Parse JSON from event.data
  // Call shared handleRealtimeEvent()
}
```

### useWebSocketUpdates.ts (existing, keep)

Existing hook with exponential backoff fix. Used when `VITE_REALTIME_TRANSPORT=ws`.

### handleRealtimeEvent.ts (new, shared)

Extract event handling logic (balance_update, service_update, etc.) from useWebSocketUpdates into a shared function. Both SSE and WS hooks call it.

### RealTimeContext.tsx (modify)

```typescript
const transport = import.meta.env.VITE_REALTIME_TRANSPORT || 'sse';
const enableRealtime = import.meta.env.VITE_ENABLE_WEBSOCKET !== 'false';

// Use SSE by default, WS as fallback
const realtimeHook = transport === 'ws' ? useWebSocketUpdates : useSSEUpdates;
```

### Environment Variables

```
VITE_ENABLE_WEBSOCKET=true              # enable/disable realtime entirely
VITE_REALTIME_TRANSPORT=sse             # 'sse' (default) or 'ws'
VITE_SSE_URL=https://z-hq.com/sse      # SSE endpoint URL
VITE_WS_URL=wss://ws.ev-agency.io/ws   # WS endpoint URL (fallback)
```

## What Doesn't Change

- `DataNotify.pm` — no changes (hooks DB writes → Redis)
- `WebSocketNotify.pm` — no changes (publishes to Redis)
- `ws_init.pl` — no changes
- `docker-compose-prod.yml` — no changes (port 9083 already proxied via api container)
- Redis channel `shm:events` — same

## File Changes Summary

| File | Action |
|------|--------|
| `prod-files/ws-server.pl` → `prod-files/realtime-server.pl` | Rename + add SSE support |
| `prod-files/sse-location.conf` | New nginx config for /sse |
| `prod-files/entry-api.sh` | Inject sse-location.conf |
| `prod-files/entry-core.sh` | Update script name |
| `wbap/Caddyfile` | Add `handle /sse` to z-hq.com |
| `wbap/.env.prod` | Add VITE_SSE_URL, VITE_REALTIME_TRANSPORT |
| `wbap/src/hooks/realtime/useSSEUpdates.ts` | New SSE hook |
| `wbap/src/hooks/realtime/handleRealtimeEvent.ts` | New shared handler |
| `wbap/src/hooks/realtime/useWebSocketUpdates.ts` | Refactor to use shared handler |
| `wbap/src/contexts/RealTimeContext.tsx` | Transport selection logic |
