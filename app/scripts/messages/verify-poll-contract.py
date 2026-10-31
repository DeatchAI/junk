#!/usr/bin/env python3
"""Decode native polls/votes using the real bundled imsg and a synthetic database."""
import base64
import json
import plistlib
import sqlite3
import sys
import tempfile
from pathlib import Path
from urllib.parse import urlencode
sys.dont_write_bytecode = True
from contract_support import ImsgFixtureRPC

helper, output = Path(sys.argv[1]), Path(sys.argv[2])
output.mkdir(parents=True, exist_ok=True)


def payload(object, key="definition"):
    encoded = base64.urlsafe_b64encode(json.dumps(object, sort_keys=True).encode()).decode().rstrip("=")
    url = "messages-polls://poll?" + urlencode({"source": "sendMenu", key: encoded})
    return plistlib.dumps({"url": url}, fmt=plistlib.FMT_BINARY)


def save(name, envelope):
    envelope["params"]["message"].pop("sender_name", None)
    (output / name).write_text(json.dumps(envelope, indent=2) + "\n")


with tempfile.TemporaryDirectory(prefix="detach-poll-contract-") as folder:
    database = Path(folder) / "fixture.db"
    connection = sqlite3.connect(database)
    connection.executescript("""
      PRAGMA journal_mode=WAL;
      CREATE TABLE message (ROWID INTEGER PRIMARY KEY, handle_id INTEGER,
        text TEXT, guid TEXT, date INTEGER, is_from_me INTEGER, service TEXT,
        associated_message_guid TEXT, associated_message_type INTEGER,
        balloon_bundle_id TEXT, payload_data BLOB, message_summary_info BLOB,
        reply_to_guid TEXT, thread_originator_guid TEXT);
      CREATE TABLE chat (ROWID INTEGER PRIMARY KEY, chat_identifier TEXT,
        guid TEXT, display_name TEXT, service_name TEXT);
      CREATE TABLE handle (ROWID INTEGER PRIMARY KEY, id TEXT);
      CREATE TABLE chat_handle_join (chat_id INTEGER, handle_id INTEGER);
      CREATE TABLE chat_message_join (chat_id INTEGER, message_id INTEGER);
      CREATE TABLE message_attachment_join (message_id INTEGER, attachment_id INTEGER);
      CREATE TABLE attachment (ROWID INTEGER PRIMARY KEY, filename TEXT,
        transfer_name TEXT, uti TEXT, mime_type TEXT, total_bytes INTEGER, is_sticker INTEGER);
      INSERT INTO chat VALUES (42, '+14155550123', 'any;-;+14155550123', '', 'iMessage');
      INSERT INTO handle VALUES (1, '+14155550123'), (2, 'fixture-agent@example.com');
      INSERT INTO chat_handle_join VALUES (42, 1);
    """)
    connection.commit()
    with ImsgFixtureRPC(helper, database) as rpc:
        rpc.request(1, "watch.subscribe", {"chat_id": 42})
        subscription = rpc.receive(lambda value: value.get("id") == 1)["result"]["subscription"]

        def insert(row_id, blob, from_me, kind=None, reference=None, text="", reply=None):
            connection.execute("""
              INSERT INTO message(ROWID,handle_id,text,guid,date,is_from_me,service,
                associated_message_guid,associated_message_type,balloon_bundle_id,payload_data,reply_to_guid)
              VALUES (?,?,?,?,?,?,'iMessage',?,?,?,?,?)
            """, (row_id, 2 if from_me else 1, text,
                "NATIVE-FIXTURE-POLL" if row_id == 10 else "fixture-row-" + str(row_id),
                800_000_000_000_000_000 + row_id * 1_000_000_000, int(from_me), reference, kind,
                "com.apple.messages.Polls" if row_id == 10 else None, blob, reply))
            connection.execute("INSERT INTO chat_message_join VALUES (42,?)", (row_id,))
            connection.commit()

        definition = {"title": "", "orderedPollOptions": [
            {"optionIdentifier": "fixture-yes", "pollOptionText": "Approve once"},
            {"optionIdentifier": "fixture-no", "pollOptionText": "Deny"}]}
        insert(10, payload(definition), True)
        insert(11, None, True, kind=0, text="Detach synthetic approval [fixture]", reply="NATIVE-FIXTURE-POLL")
        created = rpc.receive(lambda value: value.get("method") == "message"
            and value["params"]["message"]["id"] == 10)
        rpc.request(2, "messages.history", {"chat_id": 42, "limit": 10})
        history = rpc.receive(lambda value: value.get("id") == 2)["result"]
        row = next(row for row in history["messages"] if row["id"] == 10)
        assert row["poll"]["kind"] == "created"
        assert row["poll"]["question"] == "Detach synthetic approval [fixture]"
        assert [option["id"] for option in row["poll"]["options"]] == ["fixture-yes", "fixture-no"]
        created["params"]["message"] = row
        save("native-poll-created.json", created)

        snapshot = {"votes": [
            {"voteOptionIdentifier": "fixture-yes", "participant": "someone-else@example.com"},
            {"voteOptionIdentifier": "fixture-no", "participant": "+14155550123"}]}
        insert(12, payload(snapshot, "response"), False, kind=4000, reference="p:0/NATIVE-FIXTURE-POLL")
        voted = rpc.receive(lambda value: value.get("method") == "message"
            and value["params"]["message"]["id"] == 12)
        poll = voted["params"]["message"]["poll"]
        assert poll["kind"] == "vote", poll
        assert poll["original_guid"] == "NATIVE-FIXTURE-POLL"
        assert len(poll["votes"]) == 2, poll
        assert poll["votes"][1]["option_id"] == "fixture-no"
        assert poll["votes"][1]["participant"] == "+14155550123"
        save("native-poll-vote.json", voted)

        insert(13, payload({"votes": []}, "response"), False, kind=4000, reference="p/NATIVE-FIXTURE-POLL")
        unvoted = rpc.receive(lambda value: value.get("method") == "message"
            and value["params"]["message"]["id"] == 13)
        assert unvoted["params"]["message"]["poll"]["kind"] == "vote"
        assert not unvoted["params"]["message"]["poll"].get("votes")
        save("native-poll-unvote.json", unvoted)
        print("Bundled imsg verified native poll caption, exact option IDs, full vote snapshot, and unvote.")
        print("Synthetic database only; no personal messages were read or sent.")
    connection.close()
