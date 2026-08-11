# ManibelApp backend — auth module

Node.js + Express + TypeScript + Prisma/PostgreSQL. Covers commuter and
driver signup/login/OTP/password-reset only, matching the Flutter app's
`auth` feature screens. Everything else (trips, driver ops log,
notifications, etc.) is not built yet.

## 1. Get Postgres running (one-time)

This machine doesn't have Docker installed yet. To install it:

1. Download Docker Desktop for Windows: https://www.docker.com/products/docker-desktop/
2. Run the installer. Windows will prompt for admin permission (UAC) — accept it.
3. Follow the installer's prompts (it may ask to enable WSL2 — accept that too).
4. Restart your machine if it asks you to.
5. Launch **Docker Desktop** from the Start menu and wait for it to say "Docker Desktop is running".

Once Docker Desktop is running, start Postgres from this `backend/` folder:

```sh
docker compose up -d
```

This starts a `postgres:16` container on `localhost:5432` with the
credentials already wired up in `.env` (db/user/password all `manibelapp`).

## 2. Install dependencies (already done if you're reading this after setup)

```sh
npm install
```

## 3. Create the database tables

```sh
npx prisma migrate dev --name init
```

This also seeds nothing by itself — run the seed separately:

```sh
npm run prisma:seed
```

That creates one demo driver account (drivers don't self-register — see
`prisma/seed.ts`):

- Mobile: `+639171234567` (or `09171234567`, both normalize the same)
- Password: `Driver@123`

Commuters self-register via `/auth/commuter/signup`, so there's nothing to
seed for them.

## 4. Run the server

```sh
npm run dev
```

Starts on `http://localhost:4000`. `GET /health` returns `{"ok":true}` once
it's up — that works even before Postgres is connected; anything hitting
the database will 500 until step 1 is done.

## Endpoints

All bodies are JSON. Mobile numbers accept either `09XXXXXXXXX` or
`+63XXXXXXXXXX` — the server normalizes both the same way the Flutter app's
`PhoneUtils.toE164` does.

### Commuter (`/auth/commuter`)

| Method | Path                  | Body                                              | Notes |
|--------|-----------------------|----------------------------------------------------|-------|
| POST   | `/signup`             | `fullName, mobileNumber, password, dateOfBirth?`   | Returns `{ token, commuter }` immediately (not blocked on OTP) and also fires a `SIGNUP_VERIFICATION` OTP. The client's next screen is `CommuterOtpVerificationScreen`, which must clear `/verify-signup-otp` before moving on to ID + face verification. |
| POST   | `/verify-signup-otp`  | `mobileNumber, code`                               | Marks the account's `mobileVerifiedAt`. Returns `{ commuter }` |
| POST   | `/resend-signup-otp`  | `mobileNumber`                                     | Re-sends the signup OTP |
| POST   | `/login`              | `mobileNumber, password`                           | Returns `{ token, commuter }` |
| POST   | `/forgot-password`    | `mobileNumber`                                     | Sends a password-reset OTP |
| POST   | `/verify-reset-otp`   | `mobileNumber, code`                               | Returns a short-lived `{ resetToken }` (10 min) |
| POST   | `/reset-password`     | `resetToken, newPassword`                          | |
| GET    | `/me`                 | — (`Authorization: Bearer <token>`)               | Current commuter profile |

### Driver (`/auth/driver`)

Same shape as commuter, minus `/signup` — driver accounts are provisioned
out-of-band (see `prisma/seed.ts`), not self-registered.

| Method | Path                | Body                       |
|--------|---------------------|-----------------------------|
| POST   | `/login`            | `mobileNumber, password`   |
| POST   | `/forgot-password`  | `mobileNumber`             |
| POST   | `/verify-reset-otp` | `mobileNumber, code`       |
| POST   | `/reset-password`   | `resetToken, newPassword`  |
| GET    | `/me`                | — (`Authorization: Bearer <token>`) |

### Password policy

Same rule the signup screen already enforces client-side (`≥8 chars, no
spaces, upper+lower+digit+special char`) — re-checked server-side in
`src/lib/validation.ts` so it can't be bypassed by calling the API directly.

### OTP in local dev

There's no SMS gateway wired up. Every OTP (signup verification and
password reset alike) is printed to the server console instead
(`[OTP] SIGNUP_VERIFICATION code for +639...: 123456 ...`) — read it from
there while testing.

## Trying it end-to-end

```sh
# 1. Sign up — returns a token right away, and logs a SIGNUP_VERIFICATION
#    OTP to the server console
curl -X POST http://localhost:4000/auth/commuter/signup \
  -H "Content-Type: application/json" \
  -d '{"fullName":"Test User","mobileNumber":"09171234567","password":"Str0ng!Pass"}'

# 2. Verify the OTP printed in the server console
curl -X POST http://localhost:4000/auth/commuter/verify-signup-otp \
  -H "Content-Type: application/json" \
  -d '{"mobileNumber":"09171234567","code":"123456"}'

# 3. Log in
curl -X POST http://localhost:4000/auth/commuter/login \
  -H "Content-Type: application/json" \
  -d '{"mobileNumber":"09171234567","password":"Str0ng!Pass"}'
```

## Connecting the Flutter app

Wired up — see `lib/core/network/api_client.dart` and
`lib/core/services/auth_api.dart`, called from the signup/login/forgot-password/
OTP/reset-password screens under `lib/features/auth/screens/`. `UserSession`
and `DriverSession` (`lib/core/services/`) now hold the JWT this API returns
alongside the profile fields they already tracked.

By default the app points at `http://localhost:4000` (or `10.0.2.2:4000` on
an Android emulator, which is that OS's alias for the host machine). Running
on a physical device requires pointing it at your dev machine's LAN IP
instead — set `ApiClient.baseUrlOverride` (`lib/core/network/api_client.dart`)
before the first request.
