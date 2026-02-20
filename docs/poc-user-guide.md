# POC User Guide — YourBrand Chat

This guide helps testers access and evaluate the YourBrand Chat platform.

## Getting Started

### 1. Open the App

Open your browser and go to:

```
http://ec2-23-20-14-90.compute-1.amazonaws.com
```

You should see the YourBrand Chat login screen with a dark indigo/slate theme.

### 2. Create Your Account

Registration is invite-only. You need a **registration token** from your admin.

1. On the login screen, click **"Create account"**
2. Fill in:
   - **Username** — pick something short (e.g. `jane`)
   - **Password** — choose a strong password
   - **Registration token** — paste the token your admin gave you
3. Click **"Register"**

> Each token can only be used once. Ask the admin for a new token if yours doesn't work.

### 3. Log In

If you already have an account, enter your username and password on the login screen and click **"Sign in"**.

Your homeserver is already configured — you don't need to change any server settings.

## Using the App

### Finding Rooms

After logging in, look at the left sidebar. You should see:

- **YourBrand Community** (Space) — the main community hub
  - **Lobby** — welcome area
  - **Announcements** — admin updates
  - **General** — main chat
  - **Support** — help and questions
  - **Off Topic** — casual conversation
  - **Voice** — voice/video calls

Click any room name to enter it.

### Sending Messages

1. Click on a room (e.g. **General**)
2. Type your message in the text box at the bottom
3. Press **Enter** to send

### Encrypted Messages (E2EE)

All rooms use **end-to-end encryption** by default. You'll see a small **lock icon** on each message — this means only the people in the room can read it, not even the server.

When you first log in, Element may ask you to **set up key backup** or **verify your session**. This is normal:

- **Set up key backup** — recommended so you don't lose message history
- **Verify this session** — if you log in from another device, you can verify it to access encrypted history

> If you ever see "Unable to decrypt" on a message, try refreshing the page. First-time key exchange can take a moment.

## Tips for Testers

### What to Test

- [ ] Can you register with your invite token?
- [ ] Can you log in and see the YourBrand Community space?
- [ ] Can you send and receive messages in a room?
- [ ] Do you see the lock icon on messages (E2EE working)?
- [ ] Does the branding look correct (YourBrand Chat, dark theme)?
- [ ] Can you have a conversation with another user?

### Known Limitations (POC)

- **No HTTPS** — this is a proof-of-concept running over HTTP. Do not use real passwords you use elsewhere.
- **No email/password recovery** — if you forget your password, ask the admin to reset it.
- **No push notifications** — you need to keep the browser tab open.
- **Single server** — no federation with other Matrix servers.

### Reporting Issues

If something doesn't work, note:
1. What you were trying to do
2. What happened instead
3. Any error messages on screen
4. Your browser name and version

Send your findings to the admin.

## Quick Reference

| Item | Value |
|------|-------|
| App URL | `http://ec2-23-20-14-90.compute-1.amazonaws.com` |
| Registration | Invite token required (ask admin) |
| Encryption | On by default (lock icon = encrypted) |
| Rooms | 6 rooms inside YourBrand Community space |

## Admin: Generating Registration Tokens

Each tester needs a unique single-use registration token. SSH into the EC2 instance and run:

### Step 1: Get an Admin Access Token

```bash
# Log in as admin to get an access token
curl -s -X POST "http://localhost/_matrix/client/r0/login" \
  -H "Content-Type: application/json" \
  -d '{
    "type": "m.login.password",
    "user": "admin",
    "password": "YOUR_ADMIN_PASSWORD"
  }' | jq -r '.access_token'
```

Save the access token — you'll use it in the next step.

### Step 2: Create a Token

```bash
# Generate a single-use registration token
curl -s -X POST "http://localhost/_synapse/admin/v1/registration_tokens/new" \
  -H "Authorization: Bearer YOUR_ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"uses_allowed": 1}' | jq '.token'
```

This returns a token string like `"AbCdEf123456"`. Send this to the tester.

### Batch: Multiple Tokens at Once

To generate tokens for several testers at once:

```bash
ACCESS_TOKEN="YOUR_ACCESS_TOKEN"

for i in $(seq 1 5); do
  TOKEN=$(curl -s -X POST "http://localhost/_synapse/admin/v1/registration_tokens/new" \
    -H "Authorization: Bearer $ACCESS_TOKEN" \
    -H "Content-Type: application/json" \
    -d '{"uses_allowed": 1}' | jq -r '.token')
  echo "Tester $i: $TOKEN"
done
```

### List Existing Tokens

```bash
curl -s "http://localhost/_synapse/admin/v1/registration_tokens" \
  -H "Authorization: Bearer YOUR_ACCESS_TOKEN" | jq '.registration_tokens[] | {token, uses_allowed, pending, completed}'
```

### Admin Password

The admin password is stored in `compose/.env` as `ADMIN_PASSWORD`. You can view it with:

```bash
grep ADMIN_PASSWORD compose/.env
```

---

*For full operational procedures, see the [ops runbook](runbook.md).*
