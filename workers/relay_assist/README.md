# Portal Relay Assist Worker

A Cloudflare Worker (Durable Objects) that relays new-instance hints from boosted VRChat group instances to waiting Portal clients over WebSocket — reducing direct VRChat API polling.

## How it works

1. A Portal client with boost mode active detects a new instance and publishes a hint to the Worker.
2. The Worker routes the hint into a Durable Object room keyed by `groupId`.
3. All other Portal clients subscribed to that room receive the hint immediately and can act without waiting for their next poll cycle.

## Endpoints

| Method | Path                    | Description                                                   |
| ------ | ----------------------- | ------------------------------------------------------------- |
| `POST` | `/relay/bootstrap`      | Returns a short-lived WebSocket token and connection URL      |
| `GET`  | `/relay/ws?token=…`     | Upgrades to WebSocket; routes to the Durable Object for the group |

## Environment variables

| Variable               | Required | Description                                                        |
| ---------------------- | -------- | ------------------------------------------------------------------ |
| `RELAY_TOKEN_SECRET`   | Yes      | HMAC secret used to sign and verify short-lived WebSocket tokens   |
| `PORTAL_APP_SECRET`    | Yes      | Shared secret clients must send in `x-app-secret` on bootstrap     |
| `RELAY_RUNTIME_ENABLED`| No       | `"true"` (default) or `"false"` — kill-switch to disable relay     |

## Deploy

```bash
cd workers/relay_assist
wrangler deploy
```

## Client configuration

Portal uses the built-in production bootstrap URL by default. Override it only for local or staging environments:

```bash
flutter run -d macos \
  --dart-define=PORTAL_RELAY_BOOTSTRAP_URL=https://<your-worker-domain>/relay/bootstrap \
  --dart-define=PORTAL_RELAY_APP_SECRET=<your-secret>
```

Portal now rejects plaintext relay transports by default. If you need to point the desktop app at a non-TLS local worker during development, add:

```bash
--dart-define=PORTAL_ALLOW_INSECURE_RELAY_TRANSPORT=true
```
