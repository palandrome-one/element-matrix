# Discord to Matrix Migration Guide

## Overview

This guide helps Discord community admins replicate their community structure
on your self-hosted Matrix instance and onboard users smoothly.

---

## Phase 1: Plan the Migration

### Map Your Discord Structure to Matrix

| Discord Concept | Matrix Equivalent |
|----------------|-------------------|
| Server | Space |
| Category | Sub-Space (nested Space) |
| Text Channel | Room |
| Voice Channel | Room (with VoIP widget or Element Call) |
| Role | Power levels + room ACLs |
| @everyone | `@room` notification |
| Server Boost | Not applicable (self-hosted) |
| Bot | Matrix bot (mjolnir, hookshot, custom) |
| Webhook | Hookshot or appservice |

### Role/Permission Mapping

| Discord Role | Matrix Power Level | Capabilities |
|-------------|-------------------|--------------|
| Owner | 100 | Full admin, can change all settings |
| Admin | 95 | Manage rooms, kick/ban, change permissions |
| Moderator | 50 | Kick/ban, delete messages, manage room |
| Trusted | 10 | Can post in restricted rooms |
| Member (default) | 0 | Send messages, react, upload files |
| Muted | -1 | Read-only |

### Pre-Migration Checklist
- [ ] Inventory all Discord channels — decide which to replicate
- [ ] Identify moderators who will help manage the transition
- [ ] Choose a migration timeline (gradual overlap vs. hard cutover)
- [ ] Prepare announcement messaging for Discord
- [ ] Create invite tokens for initial wave

---

## Phase 2: Set Up Room Structure

### Using the Room Creation Script

The `scripts/create-default-rooms.py` script creates a standard community template.
Customize the `ROOMS` list in the script before running:

```python
ROOMS = [
    # (name, topic, encrypted, public)
    ("Lobby", "Welcome! Say hi.", True, True),
    ("Announcements", "Official posts.", True, True),
    ("General", "Main discussion.", True, True),
    # Add your custom channels:
    ("Gaming", "Game discussion and LFG.", True, True),
    ("Music", "Share and discuss music.", True, True),
    ("Dev", "Programming and tech.", True, True),
]
```

### Manual Room Creation (via Element)
1. Log in as admin at `https://chat.example.com`
2. Create a new Space (+ button → Create Space → Private)
3. Add rooms to the Space (Space settings → Add rooms)
4. Set power levels per room (Room settings → Roles & Permissions)

### Nested Spaces (Category Equivalent)
For large communities with categories:
```
YourBrand Community (Space)
├── General (Sub-Space)
│   ├── #lobby
│   ├── #announcements
│   └── #off-topic
├── Gaming (Sub-Space)
│   ├── #gaming-general
│   ├── #lfg
│   └── #voice-gaming
└── Creative (Sub-Space)
    ├── #art
    ├── #music
    └── #writing
```

---

## Phase 3: Onboard Users

### Invite Strategy

**Wave 1 — Staff & Mods (Week 1)**
1. Generate invite tokens (see runbook.md)
2. Share tokens privately with mods
3. Have mods set up Element, verify their sessions, join rooms
4. Mods provide feedback on room structure

**Wave 2 — Trusted Members (Week 2)**
1. Post announcement on Discord: "We're setting up an alternative community space"
2. Share invite link with trusted/active members
3. Provide setup guides (below)

**Wave 3 — General (Week 3+)**
1. Broader announcement with clear instructions
2. Pin setup guide in Discord channels
3. Set up a #matrix-help channel on Discord for questions

### User Setup Guide (share with your community)

```
Welcome to YourBrand Chat!

1. INSTALL ELEMENT
   - Desktop: https://element.io/download
   - iOS: App Store → "Element"
   - Android: Play Store or F-Droid → "Element"

2. SET YOUR SERVER
   - Open Element
   - Tap "Sign In" (or "Create Account" if you have an invite token)
   - Change the homeserver to: https://matrix.example.com
   - (Or just open https://chat.example.com in your browser)

3. CREATE YOUR ACCOUNT
   - Enter your invite token when prompted
   - Choose a username and password

4. VERIFY YOUR SESSION
   - After login, Element will ask you to set up key backup
   - IMPORTANT: Set up recovery key/passphrase — this protects your encrypted messages
   - Save your recovery key somewhere safe

5. JOIN THE COMMUNITY
   - Click "Explore Rooms" or search for "YourBrand Community"
   - Join the Space to see all available rooms

Questions? Ask in #support
```

---

## Phase 4: Bridges (Optional)

### Discord Bridge — Important Caveats

A Matrix-Discord bridge (like mautrix-discord) can relay messages between
Discord channels and Matrix rooms. However:

**Risks:**
- Discord ToS technically prohibits "self-bots" and unauthorized API usage
- Bridge reliability depends on Discord API changes
- Users on Discord won't benefit from E2EE
- Adds operational complexity

**Recommendation:** Use bridges as a **temporary** transition tool, not a permanent solution.
The goal is to move users off Discord, not maintain a permanent bridge.

### Safer Bridge Options

| Bridge | Use Case | Maturity |
|--------|----------|----------|
| mautrix-telegram | Telegram ↔ Matrix | Stable |
| mautrix-signal | Signal ↔ Matrix | Stable |
| matrix-hookshot | GitHub/GitLab notifications → Matrix | Stable |
| matrix-appservice-irc | IRC ↔ Matrix | Stable |
| mautrix-slack | Slack ↔ Matrix | Stable |

### Bot Alternatives to Discord Bots

| Discord Bot Function | Matrix Alternative |
|---------------------|-------------------|
| Moderation (MEE6, Dyno) | Mjolnir (anti-abuse) |
| Webhooks | Hookshot |
| Music | Not directly equivalent; use external links |
| Welcome messages | Synapse server notices or custom bot |
| Role assignment | Power level management via bot or admin |

---

## Migration Timeline Template

| Day | Action |
|-----|--------|
| D-14 | Infrastructure ready, rooms created, mods onboarded |
| D-7 | Announce migration to community, share user guide |
| D-3 | Open registration for Wave 2 (trusted members) |
| D-0 | Open registration for Wave 3 (general) |
| D+7 | First feedback check — adjust rooms, permissions |
| D+14 | Evaluate bridge needs; turn off Discord bridge if active |
| D+30 | Review: is Discord still needed? Plan sunset if appropriate |

---

## Common Questions

**Q: Can I import my Discord message history?**
A: Not directly. Matrix and Discord use different formats. Some tools exist
(like discord-to-matrix scripts) but they produce read-only archives, not
live chat history. Most communities start fresh.

**Q: Will my Discord Nitro / boosts / roles transfer?**
A: No. Matrix doesn't have a boost/subscription system. Roles are replicated
manually via power levels.

**Q: Can users keep their Discord username?**
A: Matrix usernames are separate. Users choose a new username on registration.
Display names can be set to anything.

**Q: What about file size limits?**
A: Default upload limit is 50 MB (configurable in homeserver.yaml).
For larger files, share external links.

**Q: Is there a mobile app?**
A: Yes — Element is available on iOS, Android, and desktop.
Other Matrix clients (FluffyChat, Nheko, etc.) also work.
