# Portal Relay Assist Worker

This worker implements zero-setup relay assist for Portal boosted-group auto-invite.

## Endpoints
- `POST /relay/bootstrap`: returns a short-lived websocket token and url
- `GET /relay/ws?token=...`: upgrades to websocket and routes to Durable Object room by `groupId`

## Environment variables
- `RELAY_TOKEN_SECRET` (required): HMAC secret for token signing
- `PORTAL_APP_SECRET` (required): shared secret clients must send in `x-app-secret` header to authenticate bootstrap requests
- `RELAY_RUNTIME_ENABLED` (optional): `"true"` or `"false"`, defaults to `true`

## Deploy
```bash
cd workers/relay_assist
wrangler deploy
```

## Client configuration
Portal uses a built-in production bootstrap endpoint by default. Use this Flutter define only to override for local/dev/staging:
```bash
--dart-define=PORTAL_RELAY_BOOTSTRAP_URL=https://<worker-domain>/relay/bootstrap
```
