#!/usr/bin/env python3
"""Read-only imsg contract probe against a synthetic DB, never personal Messages."""
import json
import sqlite3
import sys
import tempfile
from pathlib import Path
sys.dont_write_bytecode = True
from contract_support import ImsgFixtureRPC

helper = Path(sys.argv[1])
output = Path(sys.argv[2])
output.mkdir(parents=True, exist_ok=True)

# Minimal Messages schema based on imsg v0.20.0's public database fixtures.
with tempfile.TemporaryDirectory(prefix="detach-imsg-contract-") as folder:
    database = Path(folder) / "fixture.db"
    connection = sqlite3.connect(database)
    connection.executescript("""
      PRAGMA journal_mode=WAL;
      CREATE TABLE message (ROWID INTEGER PRIMARY KEY, handle_id INTEGER,
        text TEXT, date INTEGER, is_from_me INTEGER, service TEXT);
      CREATE TABLE chat (ROWID INTEGER PRIMARY KEY, chat_identifier TEXT,
        guid TEXT, display_name TEXT, service_name TEXT, account_id TEXT,
        account_login TEXT, last_addressed_handle TEXT);
      CREATE TABLE handle (ROWID INTEGER PRIMARY KEY, id TEXT);
      CREATE TABLE chat_handle_join (chat_id INTEGER, handle_id INTEGER);
      CREATE TABLE chat_message_join (chat_id INTEGER, message_id INTEGER);
      CREATE TABLE message_attachment_join (message_id INTEGER, attachment_id INTEGER);
      CREATE TABLE attachment (ROWID INTEGER PRIMARY KEY, filename TEXT,
        transfer_name TEXT, uti TEXT, mime_type TEXT, total_bytes INTEGER, is_sticker INTEGER);
      INSERT INTO chat VALUES (42, '+14155550123', 'any;-;+14155550123',
        '', 'iMessage', NULL, 'fixture-agent@example.com', 'fixture-agent@example.com');
      INSERT INTO handle VALUES (1, '+14155550123');
      INSERT INTO chat_handle_join VALUES (42, 1);
    """)
    connection.commit()
    rpc = ImsgFixtureRPC(helper, database)
    request, receive = rpc.request, rpc.receive

    try:
        request(1, "watch.subscribe", {})
        subscribed = receive(lambda value: value.get("id") == 1)
        assert subscribed["result"]["subscription"] > 0
        request(2, "chats.get", {"chat_id": 42})
        identity = receive(lambda value: value.get("id") == 2)["result"]
        connection.execute(
            "INSERT INTO message VALUES (?, ?, ?, ?, ?, ?)",
            (10, 1, "pair DRIVER-CONTRACT-FIXTURE", 800_000_000_000_000_000, 0, "iMessage"))
        connection.execute("INSERT INTO chat_message_join VALUES (42, 10)")
        connection.commit()
        event = receive(lambda value: value.get("method") == "message")
        message = event["params"]["message"]
        assert message["chat_guid"].startswith("any;")
        assert message["is_group"] is False
        assert "service" not in message
        assert identity["service"] == "iMessage"
        request(3, "chats.list", {"limit": 20})
        routing = receive(lambda value: value.get("id") == 3)["result"]
        assert routing["chats"][0]["account_login"] == "fixture-agent@example.com"
        assert routing["chats"][0]["last_addressed_handle"] == "fixture-agent@example.com"
        for chat in routing["chats"]:
            chat.pop("name", None)
        (output / "account-routing.json").write_text(json.dumps(routing, indent=2) + "\n")
        # Avoid retaining optional contact names even for this reserved sample number.
        message.pop("sender_name", None)
        (output / "unqualified-watch.json").write_text(json.dumps(event, indent=2) + "\n")
        (output / "unqualified-chat.json").write_text(json.dumps(identity, indent=2) + "\n")
        print("Bundled imsg reproduced: direct iMessage -> any; GUID, no watch service field.")
        print("Exact chat lookup and local account-routing metadata verified. No real messages were read or sent.")
    finally:
        rpc.__exit__()
        connection.close()
