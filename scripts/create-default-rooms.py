#!/usr/bin/env python3
"""
create-default-rooms.py — Create the default Space and rooms for a fresh community.

Prerequisites:
    pip3 install matrix-nio

Usage:
    python3 scripts/create-default-rooms.py

Reads admin credentials from compose/.env
"""

import asyncio
import os
import sys
from pathlib import Path

try:
    from nio import AsyncClient, RoomCreateResponse
except ImportError:
    print("ERROR: matrix-nio not installed. Run: pip3 install matrix-nio")
    sys.exit(1)


def load_env():
    env_path = Path(__file__).resolve().parent.parent / "compose" / ".env"
    if not env_path.exists():
        print(f"ERROR: {env_path} not found.")
        sys.exit(1)
    env = {}
    with open(env_path) as f:
        for line in f:
            line = line.strip()
            if line and not line.startswith("#") and "=" in line:
                key, _, value = line.partition("=")
                env[key.strip()] = value.strip().strip('"').strip("'")
    return env


# Room definitions: (name, topic, encrypted, public)
ROOMS = [
    ("Lobby", "Welcome! Introduce yourself and hang out.", True, True),
    ("Announcements", "Official announcements from the team. Read-only for members.", True, True),
    ("General", "General discussion — anything goes.", True, True),
    ("Support", "Ask questions and get help.", True, True),
    ("Off Topic", "Memes, random links, and everything else.", True, True),
    ("Voice", "Voice/video calls — join the room and start a call.", True, True),
]

SPACE_NAME = "YourBrand Community"
SPACE_TOPIC = "The official community space. Browse rooms below."


async def main():
    env = load_env()

    homeserver = env.get("PUBLIC_BASEURL", "https://matrix.example.com")
    admin_user = env.get("ADMIN_USER", "admin")
    admin_pass = env.get("ADMIN_PASSWORD", "")
    server_name = env.get("SYNAPSE_SERVER_NAME", "example.com")

    if not admin_pass or admin_pass.startswith("__"):
        print("ERROR: ADMIN_PASSWORD not set in .env")
        sys.exit(1)

    user_id = f"@{admin_user}:{server_name}"
    client = AsyncClient(homeserver, user_id)

    print(f"Logging in as {user_id} at {homeserver}...")
    resp = await client.login(admin_pass)
    if hasattr(resp, "access_token"):
        print("Logged in successfully.")
    else:
        print(f"Login failed: {resp}")
        await client.close()
        sys.exit(1)

    # Create the Space
    print(f"\nCreating Space: {SPACE_NAME}")
    space_resp = await client.room_create(
        name=SPACE_NAME,
        topic=SPACE_TOPIC,
        space=True,
        visibility="private",
        initial_state=[
            {
                "type": "m.room.history_visibility",
                "content": {"history_visibility": "shared"},
            }
        ],
    )

    if not isinstance(space_resp, RoomCreateResponse):
        print(f"Failed to create space: {space_resp}")
        await client.close()
        sys.exit(1)

    space_id = space_resp.room_id
    print(f"  Space created: {space_id}")

    # Create rooms and add them to the space
    for name, topic, encrypted, public in ROOMS:
        print(f"Creating room: #{name}")

        initial_state = [
            {
                "type": "m.room.history_visibility",
                "content": {"history_visibility": "shared"},
            },
        ]

        if encrypted:
            initial_state.append(
                {
                    "type": "m.room.encryption",
                    "content": {"algorithm": "m.megolm.v1.aes-sha2"},
                }
            )

        # For Announcements, restrict who can post
        power_overrides = None
        if name == "Announcements":
            power_overrides = {
                "events_default": 50,  # Only mods+ can send messages
            }

        room_resp = await client.room_create(
            name=name,
            topic=topic,
            visibility="private",
            initial_state=initial_state,
            power_level_override=power_overrides,
        )

        if isinstance(room_resp, RoomCreateResponse):
            room_id = room_resp.room_id
            print(f"  Room created: {room_id}")

            # Add room as child of the Space
            await client.room_put_state(
                space_id,
                "m.space.child",
                {"via": [server_name], "suggested": True},
                state_key=room_id,
            )
            # Set the space as parent of the room
            await client.room_put_state(
                room_id,
                "m.space.parent",
                {"via": [server_name], "canonical": True},
                state_key=space_id,
            )
            print(f"  Added to space.")
        else:
            print(f"  Failed to create room: {room_resp}")

    print(f"\nDone! Space and {len(ROOMS)} rooms created.")
    print(f"Share the space invite with your community members.")
    await client.close()


if __name__ == "__main__":
    asyncio.run(main())
