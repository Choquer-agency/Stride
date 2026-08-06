# APNs (Apple Push Notification service) integration

## Status

- **P8 auth key generated**: needs verification — search the Apple Developer portal for the key, ensure local + Railway both have access
- **Key in repo**: ☐ — **NOT FOUND** in current project tree as of Phase 0 setup
- **Key in Railway secrets**: ☐
- **Bundle ID configured**: ☐

## Day 0 action

If the P8 file is missing or you're not sure:

1. Go to [https://developer.apple.com/account/resources/authkeys/list](https://developer.apple.com/account/resources/authkeys/list)
2. Either generate a new key (`Keys` → `+`, name "Stride APNs", check `Apple Push Notifications service`, register, download `.p8`) or download the existing one
3. Note the **Key ID** (10-char identifier) and **Team ID** (10-char identifier — visible top-right of developer portal)
4. The Apple ID **bundle ID** must match the iOS app's bundle identifier (`com.stride-v.2.app` per `app/config.py:Settings.apple_bundle_id`)

## Where to put the P8 file

**DO NOT commit the .p8 file to git.** It's a private key that grants push permission to your bundle ID until expiry/revocation.

Two options:

### Option A — Railway secret file (recommended for production)
1. Railway dashboard → Stride backend service → Variables → Add reference → Secret File
2. Name: `APNS_P8_KEY` (mounted at `/etc/secrets/apns.p8` by default)
3. Paste the .p8 contents
4. Add the path to env: `APNS_KEY_PATH=/etc/secrets/apns.p8`

### Option B — Base64 env var (simpler for local development)
1. `base64 -i AuthKey_XXXXXXXXXX.p8 | pbcopy` (macOS)
2. Set env var `APNS_KEY_BASE64=<paste>`
3. Backend decodes at startup

Both options are supported by `app/services/push_service.py` — preference order: `APNS_KEY_PATH` → `APNS_KEY_BASE64` → fail loud at startup if neither set.

## Environment variables

```
APNS_KEY_ID=ABCDE12345                # 10-char Key ID from developer portal
APNS_TEAM_ID=ABCDE67890               # 10-char Team ID from developer portal
APNS_BUNDLE_ID=com.stride-v.2.app     # Must match iOS bundle ID
APNS_USE_SANDBOX=false                # true for development pushes; false for prod APNs
APNS_KEY_PATH=/etc/secrets/apns.p8    # OR
APNS_KEY_BASE64=<base64 encoded .p8>
```

## Local testing

After setting env vars:

```bash
python scripts/send_test_push.py <user_id> "Hello from coach" stride://coach/inbox
```

This uses the same `aioapns` client + key as production. Set `APNS_USE_SANDBOX=true` and run with a development build of the iOS app to test against Apple's sandbox APNs server.

## Device token registration flow (iOS)

1. iOS app on first authenticated open requests notification permission via `UNUserNotificationCenter`
2. On grant, iOS calls `application:didRegisterForRemoteNotificationsWithDeviceToken:`
3. iOS app converts token to hex string and POSTs to `/api/devices/register`
4. Backend stores hex on `users.apns_device_token`

If the token changes (device restore, OS update, app reinstall), the iOS app re-registers and overwrites the column.

## Notification rate limiting (`app/services/push_service.py`)

- Max 4 non-critical pushes per day per user (tracked via `coaching_events.notification_delivered`)
- Critical pushes (red flag, LEA pattern) bypass the rate limit
- Quiet hours: respects `users.quiet_hours_start` / `quiet_hours_end`
- Muted types: respects `users.muted_notification_types`
- Per-loop coaching mode: `shadow` / `off` skip push entirely; only `live` delivers

## Troubleshooting

- `BadDeviceToken` from APNs → token is for the wrong environment (sandbox vs prod). Check `APNS_USE_SANDBOX`.
- `Unregistered` from APNs → user uninstalled or revoked. Clear `users.apns_device_token`, wait for next iOS app open to re-register.
- 403 from APNs → P8 key is wrong, expired, or doesn't have APNs scope. Re-check Key ID + Team ID.
