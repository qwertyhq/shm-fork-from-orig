# SSE + WebSocket Dual-Protocol Realtime Server

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add SSE support to realtime-server.pl so browsers can receive events through Caddy proxy, keeping WebSocket as fallback.

**Architecture:** Single Perl process on port 9083 detects protocol by HTTP headers (Upgrade: websocket → WS, else → SSE). Redis pub/sub dispatches events to both types. Frontend uses EventSource API by default.

**Tech Stack:** Perl 5.14+, IO::Select, Redis pub/sub, TypeScript/React, nginx, Caddy

---

### Task 1: Rename ws-server.pl → realtime-server.pl and add SSE support

**Files:**
- Modify: `prod-files/ws-server.pl` → rename to `prod-files/realtime-server.pl`

- [ ] **Step 1: Copy ws-server.pl to realtime-server.pl**

```bash
cp prod-files/ws-server.pl prod-files/realtime-server.pl
```

- [ ] **Step 2: Update header comment and log prefix**

In `prod-files/realtime-server.pl`, change line 1-9:

```perl
#!/usr/bin/perl

# Dual-protocol realtime server for SHM event delivery (SSE + WebSocket).
# Subscribes to Redis PubSub channel and fans out events to
# browser clients connected via SSE or WebSocket, routed by user_id.
#
# SSE is the default transport (works through any HTTP proxy).
# WebSocket is a fallback for deployments without Caddy.
#
# Runs inside the `core` container alongside shm-server.pl.
```

Change `log_msg` prefix:

```perl
sub log_msg { say STDERR "[realtime] @_" }
```

- [ ] **Step 3: Add `type` field to client state**

In `accept_client`, add `type => undef`:

```perl
sub accept_client {
    my $csock = $listen_sock->accept or return;
    $csock->blocking(0);
    my $fn = fileno($csock);
    $clients{$fn} = {
        sock           => $csock,
        user_id        => 0,
        type           => undef,   # 'ws' | 'sse'
        buf            => '',
        handshake_done => 0,
    };
    $select->add($csock);
}
```

- [ ] **Step 4: Replace do_handshake with dual-protocol detection**

Replace the entire `do_handshake` sub:

```perl
sub do_handshake {
    my $fn = shift;
    my $c  = $clients{$fn};

    # Wait for full HTTP request
    return unless $c->{buf} =~ /\r\n\r\n/;

    my ($header) = $c->{buf} =~ /^(.*?\r\n\r\n)/s;
    $c->{buf} = substr($c->{buf}, length($header));

    # Parse user_id from query string
    my ($query)   = $header =~ /GET\s+[^?\s]*\?(\S*)\s/;
    my ($user_id) = ($query // '') =~ /(?:^|&)user_id=(\d+)/;

    unless ($user_id && $user_id > 0) {
        $c->{sock}->syswrite("HTTP/1.1 400 Bad Request\r\nConnection: close\r\n\r\n");
        remove_client($fn);
        return;
    }

    # Detect protocol by Upgrade header
    if ($header =~ /Upgrade:\s*websocket/i) {
        # WebSocket handshake
        my ($key) = $header =~ /Sec-WebSocket-Key:\s*(\S+)/i;
        unless ($key) {
            $c->{sock}->syswrite("HTTP/1.1 400 Bad Request\r\nConnection: close\r\n\r\n");
            remove_client($fn);
            return;
        }
        my $accept = encode_base64(sha1($key . $WS_MAGIC), '');
        my $resp = "HTTP/1.1 101 Switching Protocols\r\n"
                 . "Upgrade: websocket\r\n"
                 . "Connection: Upgrade\r\n"
                 . "Sec-WebSocket-Accept: $accept\r\n"
                 . "\r\n";
        $c->{sock}->syswrite($resp);
        $c->{type} = 'ws';
        log_msg("WS client fd=$fn user=$user_id");
    } else {
        # SSE response
        my $resp = "HTTP/1.1 200 OK\r\n"
                 . "Content-Type: text/event-stream\r\n"
                 . "Cache-Control: no-cache\r\n"
                 . "Connection: keep-alive\r\n"
                 . "Access-Control-Allow-Origin: *\r\n"
                 . "X-Accel-Buffering: no\r\n"
                 . "\r\n";
        $c->{sock}->syswrite($resp);
        $c->{type} = 'sse';
        log_msg("SSE client fd=$fn user=$user_id");
    }

    $c->{user_id}        = $user_id;
    $c->{handshake_done} = 1;
    $user_socks{$user_id}{$fn} = 1;
}
```

- [ ] **Step 5: Update read_client to handle SSE clients**

SSE clients are read-only (server→client). After handshake, SSE clients only need disconnect detection:

```perl
sub read_client {
    my $fh = shift;
    my $fn = fileno($fh);
    my $c  = $clients{$fn};
    unless ($c) { $select->remove($fh); return }

    my $data;
    my $n = $fh->sysread($data, 65536);
    unless ($n) { remove_client($fn); return }

    $c->{buf} .= $data;

    if (!$c->{handshake_done}) {
        do_handshake($fn);
    } elsif ($c->{type} eq 'ws') {
        process_ws_frames($fn);
    }
    # SSE clients: ignore incoming data (read-only channel)
}
```

- [ ] **Step 6: Update dispatch_event for dual protocol**

```perl
sub dispatch_event {
    my $json = shift;
    my $event;
    eval { $event = decode_json($json) };
    return unless $event && $event->{user_id};

    my $uid = $event->{user_id};
    my $socks = $user_socks{$uid} or return;

    my $ws_frame  = ws_encode_text($json);
    my $sse_frame = "data: $json\n\n";

    for my $fn (keys %$socks) {
        my $c = $clients{$fn} or next;
        my $payload = $c->{type} eq 'sse' ? $sse_frame : $ws_frame;
        eval { $c->{sock}->syswrite($payload) };
        if ($@) { remove_client($fn) }
    }
}
```

- [ ] **Step 7: Update send_ping_all for dual protocol**

```perl
sub send_ping_all {
    my $ws_ping  = ws_ping_frame();
    my $sse_ping = ": ping\n\n";
    for my $fn (keys %clients) {
        my $c = $clients{$fn} or next;
        next unless $c->{handshake_done};
        my $payload = $c->{type} eq 'sse' ? $sse_ping : $ws_ping;
        eval { $c->{sock}->syswrite($payload) };
        if ($@) { remove_client($fn) }
    }
}
```

- [ ] **Step 8: Commit**

```bash
git add prod-files/realtime-server.pl
git commit -m "feat: dual-protocol realtime server (SSE + WebSocket)"
```

---

### Task 2: Nginx SSE location config

**Files:**
- Create: `prod-files/sse-location.conf`
- Modify: `prod-files/entry-api.sh`

- [ ] **Step 1: Create sse-location.conf**

```nginx
# SSE proxy to realtime-server.pl running in core container
location /sse {
    proxy_pass http://core:9083;
    proxy_http_version 1.1;
    proxy_set_header Connection '';
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_buffering off;
    proxy_cache off;
    proxy_read_timeout 86400s;
    proxy_send_timeout 86400s;
    chunked_transfer_encoding off;
}
```

- [ ] **Step 2: Add SSE injection to entry-api.sh**

After the existing WebSocket injection block (line 32), add:

```bash
# Inject SSE location if config file exists (only once)
if [ -f /etc/nginx/sse-location.conf ] && ! grep -q "sse-location" /etc/nginx/nginx.conf; then
    sed -i '/location = \/shm\/healthcheck.cgi/i \        include /etc/nginx/sse-location.conf;' /etc/nginx/nginx.conf
    echo "SSE location injected into nginx.conf"
fi
```

- [ ] **Step 3: Commit**

```bash
git add prod-files/sse-location.conf prod-files/entry-api.sh
git commit -m "feat: nginx SSE proxy config"
```

---

### Task 3: Update docker-compose and entry-core.sh

**Files:**
- Modify: `docker-compose-prod.yml`
- Modify: `prod-files/entry-core.sh`

- [ ] **Step 1: Update entry-core.sh script name**

Change `ws-server.pl` to `realtime-server.pl`:

```bash
    # Start realtime server in background (SSE + WebSocket)
    if [ -f /app/bin/realtime-server.pl ]; then
        perl /app/bin/realtime-server.pl &
        echo "Realtime server started on port ${WS_PORT:-9083}"
    fi
```

- [ ] **Step 2: Update docker-compose-prod.yml volumes**

In the `core` service, change:
```yaml
      - "./prod-files/realtime-server.pl:/app/bin/realtime-server.pl"
```

In the `api` service, add sse-location.conf volume:
```yaml
      - "./prod-files/sse-location.conf:/etc/nginx/sse-location.conf"
```

- [ ] **Step 3: Commit**

```bash
git add docker-compose-prod.yml prod-files/entry-core.sh
git commit -m "feat: docker config for realtime-server.pl + SSE"
```

---

### Task 4: Caddy SSE route

**Files:**
- Modify: `wbap/Caddyfile` (z-hq.com block)

- [ ] **Step 1: Add /sse handle before the catch-all**

In the `z-hq.com` block, add before `handle {` (the catch-all reverse_proxy to wbap-prod):

```caddy
    # SSE realtime events → SHM API (nginx → realtime-server.pl)
    handle /sse {
        reverse_proxy http://api:80
    }
```

- [ ] **Step 2: Remove ws.ev-agency.io block**

Delete the entire `ws.ev-agency.io` block (it was for WebSocket debugging, no longer needed through Caddy).

- [ ] **Step 3: Commit**

```bash
git add wbap/Caddyfile
git commit -m "feat: Caddy SSE route on z-hq.com/sse"
```

---

### Task 5: Frontend — shared event handler

**Files:**
- Create: `wbap/src/hooks/realtime/handleRealtimeEvent.ts`

- [ ] **Step 1: Create handleRealtimeEvent.ts**

Extract event handling logic from useWebSocketUpdates into a shared function:

```typescript
import { requestCache } from '../../lib/cache/RequestCache';

export interface RealtimeEvent {
  type?: string;
  action?: string;
  table?: string;
  user_id?: number;
  timestamp?: number;
  data?: any;
}

interface RealtimeHandlers {
  fetchUser: () => void;
  fetchServices: () => void;
}

export function handleRealtimeEvent(event: RealtimeEvent, handlers: RealtimeHandlers) {
  const { fetchUser, fetchServices } = handlers;

  // Handle by table (from DataNotify: action + table + user_id)
  if (event.table) {
    switch (event.table) {
      case 'users':
      case 'pays':
        requestCache.invalidateByTags(['user']);
        fetchUser();
        break;
      case 'user_services':
      case 'services':
        requestCache.invalidateByTags(['services']);
        fetchServices();
        break;
    }
    return;
  }

  // Handle by type (legacy format from useWebSocketUpdates)
  if (event.type) {
    switch (event.type) {
      case 'balance_update':
        requestCache.invalidateByTags(['user']);
        fetchUser();
        break;
      case 'service_update':
      case 'service_status':
        requestCache.invalidateByTags(['services']);
        fetchServices();
        break;
    }
  }
}
```

- [ ] **Step 2: Commit**

```bash
git add wbap/src/hooks/realtime/handleRealtimeEvent.ts
git commit -m "feat: shared realtime event handler"
```

---

### Task 6: Frontend — useSSEUpdates hook

**Files:**
- Create: `wbap/src/hooks/realtime/useSSEUpdates.ts`

- [ ] **Step 1: Create useSSEUpdates.ts**

```typescript
import { useEffect, useRef, useState, useCallback } from 'react';
import { useUserStore } from '../../store/user';
import { handleRealtimeEvent } from './handleRealtimeEvent';

interface SSEConfig {
  enabled?: boolean;
  url?: string;
}

export function useSSEUpdates(config: SSEConfig = {}) {
  const {
    enabled = true,
    url = import.meta.env.VITE_SSE_URL || `${location.protocol}//${location.host}/sse`,
  } = config;

  const { user, fetchUser, fetchServices } = useUserStore();
  const esRef = useRef<EventSource | null>(null);
  const [connectionStatus, setConnectionStatus] = useState<'connecting' | 'connected' | 'disconnected'>('disconnected');

  const disconnect = useCallback(() => {
    if (esRef.current) {
      esRef.current.close();
      esRef.current = null;
    }
    setConnectionStatus('disconnected');
  }, []);

  useEffect(() => {
    if (!enabled || !user?.user_id) {
      disconnect();
      return;
    }

    const sseUrl = `${url}?user_id=${user.user_id}`;
    const es = new EventSource(sseUrl);
    esRef.current = es;
    setConnectionStatus('connecting');

    es.onopen = () => {
      setConnectionStatus('connected');
      if (import.meta.env.DEV) {
        console.log('SSE connected');
      }
    };

    es.onmessage = (event) => {
      try {
        const data = JSON.parse(event.data);
        handleRealtimeEvent(data, { fetchUser, fetchServices });
      } catch {
        // ignore malformed messages
      }
    };

    es.onerror = () => {
      setConnectionStatus('disconnected');
      // EventSource auto-reconnects, no manual logic needed
    };

    return () => {
      es.close();
      esRef.current = null;
      setConnectionStatus('disconnected');
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [enabled, user?.user_id, url]);

  return {
    connectionStatus,
    isConnected: connectionStatus === 'connected',
    disconnect,
  };
}
```

- [ ] **Step 2: Commit**

```bash
git add wbap/src/hooks/realtime/useSSEUpdates.ts
git commit -m "feat: SSE realtime hook with EventSource"
```

---

### Task 7: Frontend — update RealTimeContext for transport selection

**Files:**
- Modify: `wbap/src/contexts/RealTimeContext.tsx`
- Modify: `wbap/src/hooks/realtime/useWebSocketUpdates.ts`

- [ ] **Step 1: Update useWebSocketUpdates to use shared handler**

In `useWebSocketUpdates.ts`, replace the `handleMessage` callback body to use `handleRealtimeEvent`:

Add import at top:
```typescript
import { handleRealtimeEvent } from './handleRealtimeEvent';
```

Replace `handleMessage`:
```typescript
  const handleMessage = useCallback((event: MessageEvent) => {
    try {
      const data = JSON.parse(event.data);
      handleRealtimeEvent(data, { fetchUser, fetchServices });
    } catch {
      // ignore malformed messages
    }
  }, [fetchUser, fetchServices]);
```

Remove the `notifications` import and usage from this hook (notifications are handled at the RealTimeContext level via polling `onDataChange`). Remove `WebSocketMessage` interface and `lastMessage` state.

- [ ] **Step 2: Update RealTimeContext.tsx**

```typescript
import { createContext, useContext, useEffect, useRef, ReactNode } from 'react';
import { useRealTimeUpdates } from '../hooks/realtime/useRealTimeUpdates';
import { useSSEUpdates } from '../hooks/realtime/useSSEUpdates';
import { useWebSocketUpdates } from '../hooks/realtime/useWebSocketUpdates';
import { useNotifications } from '../hooks/ui/useNotifications';
import { useAppConfigStore } from '../store/appConfig';
import { useAnnouncementsStore } from '../store/announcements';
import { getServiceName } from '../lib/utils/serviceNameTranslator';

interface RealTimeContextType {
  forceUpdate: () => Promise<void>;
  isActive: boolean;
  lastUpdateTime: Date;
}

const RealTimeContext = createContext<RealTimeContextType | undefined>(undefined);

interface RealTimeProviderProps {
  children: ReactNode;
}

export function RealTimeProvider({ children }: RealTimeProviderProps) {
  const notifications = useNotifications();
  const { settings } = useAppConfigStore();
  const { fetchAnnouncements, fetchReadIds } = useAnnouncementsStore();

  const parsedActive = parseInt(settings.shmUpdateInterval, 10);
  const parsedBackground = parseInt(settings.shmBackgroundUpdateInterval, 10);
  const activeInterval = Math.max(5000, isNaN(parsedActive) ? 5000 : parsedActive);
  const backgroundInterval = Math.max(10000, isNaN(parsedBackground) ? 60000 : parsedBackground);

  // Realtime transport selection
  const enableRealtime = import.meta.env.VITE_ENABLE_WEBSOCKET !== 'false';
  const transport = import.meta.env.VITE_REALTIME_TRANSPORT || 'sse';

  const sseResult = useSSEUpdates({ enabled: enableRealtime && transport === 'sse' });
  const wsResult = useWebSocketUpdates({ enabled: enableRealtime && transport === 'ws' });
  const realtimeConnected = transport === 'sse' ? sseResult.isConnected : wsResult.isConnected;

  // Polling — fallback (slower when realtime is connected)
  const { forceUpdate, isActive, lastUpdateTime } = useRealTimeUpdates({
    updateInterval: realtimeConnected ? 60000 : activeInterval,
    backgroundUpdateInterval: backgroundInterval,
    onDataChange: (type, data) => {
      switch (type) {
        case 'balance':
          if (data.diff > 0) {
            notifications.success(`Баланс пополнен: +${data.diff} р`, { duration: 5000 });
          } else if (data.diff < 0) {
            notifications.info(`Средства списаны: ${data.diff} р`, { duration: 4000 });
          }
          break;
        case 'services':
          if (data.new > data.old) {
            notifications.success('Новая подписка активирована!', { duration: 6000 });
          }
          break;
        case 'service_status': {
          const { service, newStatus } = data;
          if (newStatus === 'ACTIVE') {
            notifications.success(`"${getServiceName(service)}" активирована`, { duration: 4000 });
          }
          break;
        }
      }
    }
  });

  const fetchAnnouncementsRef = useRef(fetchAnnouncements);
  fetchAnnouncementsRef.current = fetchAnnouncements;

  useEffect(() => {
    fetchAnnouncementsRef.current();
    fetchReadIds();
    const id = setInterval(() => fetchAnnouncementsRef.current(), activeInterval);
    return () => clearInterval(id);
  }, [activeInterval]);

  const forceUpdateRef = useRef(forceUpdate);
  forceUpdateRef.current = forceUpdate;

  useEffect(() => {
    const handleForceUpdate = () => {
      forceUpdateRef.current();
      fetchAnnouncementsRef.current();
    };
    window.addEventListener('forceDataUpdate', handleForceUpdate);
    return () => window.removeEventListener('forceDataUpdate', handleForceUpdate);
  }, []);

  return (
    <RealTimeContext.Provider value={{ forceUpdate, isActive, lastUpdateTime }}>
      {children}
    </RealTimeContext.Provider>
  );
}

export function useRealTimeContext() {
  const context = useContext(RealTimeContext);
  if (context === undefined) {
    throw new Error('useRealTimeContext must be used within a RealTimeProvider');
  }
  return context;
}

export function triggerGlobalUpdate() {
  window.dispatchEvent(new CustomEvent('forceDataUpdate'));
}
```

- [ ] **Step 3: Commit**

```bash
git add wbap/src/hooks/realtime/useWebSocketUpdates.ts wbap/src/contexts/RealTimeContext.tsx
git commit -m "feat: transport selection (SSE default, WS fallback)"
```

---

### Task 8: Environment variables

**Files:**
- Modify: `wbap/.env.prod`

- [ ] **Step 1: Update .env.prod**

Replace existing WebSocket config:

```
# REALTIME CONFIGURATION
VITE_ENABLE_WEBSOCKET=true
VITE_REALTIME_TRANSPORT=sse
VITE_SSE_URL=https://z-hq.com/sse
VITE_WS_URL=wss://ws.ev-agency.io/ws
```

- [ ] **Step 2: Commit**

```bash
git add wbap/.env.prod
git commit -m "feat: SSE realtime env config"
```

---

### Task 9: Clean up old ws-server.pl

**Files:**
- Remove: `prod-files/ws-server.pl` (replaced by realtime-server.pl)

- [ ] **Step 1: Remove old file**

```bash
git rm prod-files/ws-server.pl
```

- [ ] **Step 2: Commit**

```bash
git commit -m "chore: remove old ws-server.pl (replaced by realtime-server.pl)"
```
