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

## Relay Protocol Contract

The Flutter client and this Worker both enforce the same wire-level rules.

- Bootstrap `groupId` must match `grp_<uuid>` using lowercase hex.
- Relay hint payloads require non-empty `hintId`, `groupId`, `worldId`, `instanceId`, and `sourceClientId`.
- `hintId` must be at most 256 characters.
- `worldId` must match `wrld_<uuid>`; matching is case-insensitive.
- `instanceId` must start with one or more digits.
- Client-to-worker WebSocket payloads must be at most `2048` bytes.
- Portal publishes hints with a 45 second TTL.
- The Worker rejects hints that are already expired and rejects hints whose expiry is implausibly far in the future (more than 70 seconds ahead of worker time).
- Portal consumers allow a 5 second grace window when checking hint expiry to tolerate minor clock skew.

Relevant worker-side error codes and responses:

- Bootstrap may return `unauthorized`, `bootstrap_rate_limited`, `invalid_json`, `invalid_bootstrap_payload`, `invalid_group_id_format`, or `missing_secret`.
- Bootstrap may also return `relayEnabled: false` with `retryAfterSeconds` when relay is runtime-disabled.
- WebSocket error frames may contain `payload_too_large`, `invalid_json`, `unsupported_message_type`, `forbidden_publish`, `publish_rate_limited`, or `invalid_hint_payload`.

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
