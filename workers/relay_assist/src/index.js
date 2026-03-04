const TOKEN_TTL_SECONDS = 120;
const HINT_TTL_MS = 60_000;
const MAX_PAYLOAD_BYTES = 2048;
const MAX_PUBLISH_PER_WINDOW = 10;
const PUBLISH_WINDOW_MS = 10_000;
const BOOTSTRAP_WINDOW_MS = 10_000;
const MAX_BOOTSTRAP_PER_WINDOW = 8;

const bootstrapRateLimitByIp = new Map();

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    if (url.pathname === '/relay/bootstrap' && request.method === 'POST') {
      return handleBootstrap(request, env);
    }

    if (url.pathname === '/relay/ws') {
      return handleWebSocketUpgrade(request, env);
    }

    return json({ error: 'not_found' }, 404);
  },
};

async function handleBootstrap(request, env) {
  if (!isRelayEnabled(env)) {
    return json({ relayEnabled: false, retryAfterSeconds: 60 }, 503);
  }

  if (!env.PORTAL_APP_SECRET) {
    return json({ error: 'missing_secret' }, 500);
  }

  const appSecret = `${request.headers.get('x-app-secret') || ''}`;
  if (!timingSafeEqual(appSecret, env.PORTAL_APP_SECRET)) {
    return json({ error: 'unauthorized' }, 401);
  }

  const ip = request.headers.get('CF-Connecting-IP') || 'unknown';
  if (!checkRateLimit(bootstrapRateLimitByIp, ip, BOOTSTRAP_WINDOW_MS, MAX_BOOTSTRAP_PER_WINDOW)) {
    return json({ error: 'bootstrap_rate_limited' }, 429);
  }

  let payload;
  try {
    payload = await request.json();
  } catch {
    return json({ error: 'invalid_json' }, 400);
  }

  const groupId = `${payload?.groupId || ''}`.trim();
  const clientId = `${payload?.clientId || ''}`.trim();
  if (!groupId || !clientId || groupId.length > 128 || clientId.length > 128) {
    return json({ error: 'invalid_bootstrap_payload' }, 400);
  }

  if (!env.RELAY_TOKEN_SECRET) {
    return json({ error: 'missing_secret' }, 500);
  }

  const nowSeconds = Math.floor(Date.now() / 1000);
  const claims = {
    v: 1,
    groupId,
    clientId,
    canPublish: true,
    quota: MAX_PUBLISH_PER_WINDOW,
    exp: nowSeconds + TOKEN_TTL_SECONDS,
  };

  const token = await signToken(claims, env.RELAY_TOKEN_SECRET);
  const wsUrl = new URL('/relay/ws', request.url);
  wsUrl.protocol = wsUrl.protocol === 'https:' ? 'wss:' : 'ws:';
  wsUrl.searchParams.set('token', token);

  return json({
    relayEnabled: true,
    wsUrl: wsUrl.toString(),
    tokenExpiresAtMs: (claims.exp ?? nowSeconds) * 1000,
  });
}

async function handleWebSocketUpgrade(request, env) {
  if (request.headers.get('Upgrade') !== 'websocket') {
    return new Response('Expected websocket upgrade', { status: 426 });
  }

  if (!isRelayEnabled(env)) {
    return json({ error: 'relay_disabled' }, 503);
  }

  const url = new URL(request.url);
  const token = url.searchParams.get('token') || '';
  if (!token) {
    return json({ error: 'missing_token' }, 401);
  }

  if (!env.RELAY_TOKEN_SECRET) {
    return json({ error: 'missing_secret' }, 500);
  }

  const claims = await verifyToken(token, env.RELAY_TOKEN_SECRET);
  if (!claims || !claims.groupId || !claims.clientId) {
    return json({ error: 'invalid_token' }, 401);
  }

  const nowSeconds = Math.floor(Date.now() / 1000);
  if (claims.exp <= nowSeconds) {
    return json({ error: 'expired_token' }, 401);
  }

  const roomId = env.RELAY_ROOM.idFromName(`group:${claims.groupId}`);
  const roomStub = env.RELAY_ROOM.get(roomId);

  const headers = new Headers(request.headers);
  headers.set('x-relay-claims', JSON.stringify(claims));
  headers.set('x-relay-ip', request.headers.get('CF-Connecting-IP') || 'unknown');

  const doRequest = new Request(request.url, {
    method: request.method,
    headers,
  });

  return roomStub.fetch(doRequest);
}

function isRelayEnabled(env) {
  return `${env.RELAY_RUNTIME_ENABLED ?? 'true'}`.toLowerCase() !== 'false';
}

function checkRateLimit(map, key, windowMs, maxRequests) {
  const now = Date.now();
  const current = map.get(key);
  if (!current || current.windowStart + windowMs <= now) {
    map.set(key, { windowStart: now, count: 1 });
    return true;
  }

  if (current.count >= maxRequests) {
    return false;
  }

  current.count += 1;
  return true;
}

function json(data, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { 'content-type': 'application/json' },
  });
}

async function signToken(claims, secret) {
  const encodedClaims = base64UrlEncode(JSON.stringify(claims));
  const signature = await hmacSha256(encodedClaims, secret);
  return `${encodedClaims}.${signature}`;
}

async function verifyToken(token, secret) {
  const [encodedClaims, signature] = token.split('.');
  if (!encodedClaims || !signature) {
    return null;
  }

  const expected = await hmacSha256(encodedClaims, secret);
  if (!timingSafeEqual(signature, expected)) {
    return null;
  }

  try {
    return JSON.parse(base64UrlDecode(encodedClaims));
  } catch {
    return null;
  }
}

async function hmacSha256(payload, secret) {
  const enc = new TextEncoder();
  const key = await crypto.subtle.importKey(
    'raw',
    enc.encode(secret),
    { name: 'HMAC', hash: 'SHA-256' },
    false,
    ['sign'],
  );

  const sig = await crypto.subtle.sign('HMAC', key, enc.encode(payload));
  return bytesToBase64Url(new Uint8Array(sig));
}

function base64UrlEncode(value) {
  return bytesToBase64Url(new TextEncoder().encode(value));
}

function base64UrlDecode(value) {
  const normalized = value.replace(/-/g, '+').replace(/_/g, '/');
  const pad = normalized.length % 4;
  const padded = pad ? normalized + '='.repeat(4 - pad) : normalized;
  const binary = atob(padded);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i += 1) {
    bytes[i] = binary.charCodeAt(i);
  }
  return new TextDecoder().decode(bytes);
}

function bytesToBase64Url(bytes) {
  let binary = '';
  for (const byte of bytes) {
    binary += String.fromCharCode(byte);
  }
  return btoa(binary).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/g, '');
}

function timingSafeEqual(a, b) {
  if (a.length !== b.length) {
    return false;
  }
  let result = 0;
  for (let i = 0; i < a.length; i += 1) {
    result |= a.charCodeAt(i) ^ b.charCodeAt(i);
  }
  return result === 0;
}

export class RelayRoom {
  constructor(state) {
    this.state = state;
    this.recentHints = new Map();
    this.publishWindowByClient = new Map();

    for (const ws of this.state.getWebSockets()) {
      const attachment = ws.deserializeAttachment() || {};
      if (attachment.clientId) {
        this.publishWindowByClient.set(attachment.clientId, {
          windowStart: Date.now(),
          count: 0,
        });
      }
    }
  }

  async fetch(request) {
    if (request.headers.get('Upgrade') !== 'websocket') {
      return new Response('Expected websocket upgrade', { status: 426 });
    }

    const claimsRaw = request.headers.get('x-relay-claims');
    if (!claimsRaw) {
      return new Response('Missing relay claims', { status: 401 });
    }

    let claims;
    try {
      claims = JSON.parse(claimsRaw);
    } catch {
      return new Response('Invalid relay claims', { status: 401 });
    }

    const pair = new WebSocketPair();
    const client = pair[0];
    const server = pair[1];

    server.serializeAttachment({
      clientId: claims.clientId,
      canPublish: claims.canPublish === true,
      groupId: claims.groupId,
      ip: request.headers.get('x-relay-ip') || 'unknown',
    });

    this.state.acceptWebSocket(server);

    server.send(JSON.stringify({ type: 'ack', connectedAtMs: Date.now() }));
    return new Response(null, { status: 101, webSocket: client });
  }

  webSocketMessage(ws, message) {
    if (typeof message !== 'string') {
      return;
    }

    if (message.length > MAX_PAYLOAD_BYTES) {
      ws.send(JSON.stringify({ type: 'error', code: 'payload_too_large' }));
      return;
    }

    let data;
    try {
      data = JSON.parse(message);
    } catch {
      ws.send(JSON.stringify({ type: 'error', code: 'invalid_json' }));
      return;
    }

    const type = `${data?.type || ''}`;
    if (type === 'ping') {
      ws.send(JSON.stringify({ type: 'pong', ts: Date.now() }));
      return;
    }

    if (type !== 'publish_hint') {
      ws.send(JSON.stringify({ type: 'error', code: 'unsupported_message_type' }));
      return;
    }

    const metadata = ws.deserializeAttachment() || {};
    if (metadata.canPublish !== true) {
      ws.send(JSON.stringify({ type: 'error', code: 'forbidden_publish' }));
      return;
    }

    const now = Date.now();
    if (!this.#canPublish(metadata.clientId, now)) {
      ws.send(
        JSON.stringify({
          type: 'error',
          code: 'publish_rate_limited',
          retryAfterSeconds: 10,
        }),
      );
      return;
    }

    const hint = data.payload;
    if (!this.#isValidHint(hint, metadata.groupId, now)) {
      ws.send(JSON.stringify({ type: 'error', code: 'invalid_hint_payload' }));
      return;
    }

    if (this.recentHints.get(hint.hintId) > now) {
      return;
    }

    this.recentHints.set(hint.hintId, now + HINT_TTL_MS);
    this.#pruneHintCache(now);

    const outbound = JSON.stringify({ type: 'hint', payload: hint });
    for (const socket of this.state.getWebSockets()) {
      socket.send(outbound);
    }
  }

  webSocketClose(ws) {
    const metadata = ws.deserializeAttachment() || {};
    if (metadata.clientId) {
      this.publishWindowByClient.delete(metadata.clientId);
    }
  }

  #canPublish(clientId, now) {
    if (!clientId) {
      return false;
    }

    const existing = this.publishWindowByClient.get(clientId);
    if (!existing || existing.windowStart + PUBLISH_WINDOW_MS <= now) {
      this.publishWindowByClient.set(clientId, {
        windowStart: now,
        count: 1,
      });
      return true;
    }

    if (existing.count >= MAX_PUBLISH_PER_WINDOW) {
      return false;
    }

    existing.count += 1;
    return true;
  }

  #isValidHint(hint, expectedGroupId, now) {
    if (!hint || typeof hint !== 'object') {
      return false;
    }

    const hintId = `${hint.hintId || ''}`;
    const groupId = `${hint.groupId || ''}`;
    const worldId = `${hint.worldId || ''}`;
    const instanceId = `${hint.instanceId || ''}`;
    const sourceClientId = `${hint.sourceClientId || ''}`;
    const expiresAtMs = Number(hint.expiresAtMs || 0);

    if (!hintId || !groupId || !worldId || !instanceId || !sourceClientId) {
      return false;
    }

    if (groupId !== expectedGroupId) {
      return false;
    }

    if (!Number.isFinite(expiresAtMs) || expiresAtMs <= now) {
      return false;
    }

    if (expiresAtMs - now > HINT_TTL_MS + 10_000) {
      return false;
    }

    return true;
  }

  #pruneHintCache(now) {
    for (const [key, expiresAt] of this.recentHints.entries()) {
      if (expiresAt <= now) {
        this.recentHints.delete(key);
      }
    }
  }
}
