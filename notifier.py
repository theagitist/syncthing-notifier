#!/usr/bin/env python3
"""Notify when remote devices finish receiving changes for watched folders."""
import json
import logging
import os
import subprocess
import sys
import time
import urllib.error
import urllib.request
import xml.etree.ElementTree as ET
from pathlib import Path
from urllib.parse import urlencode

GUI = "http://127.0.0.1:8384"
CONFIG_XML = os.path.expanduser("~/Library/Application Support/Syncthing/config.xml")
FOLDERS_PATH = Path(__file__).resolve().parent / "folders.json"

NOTIFIER_APP = os.path.expanduser(
    "~/Applications/Syncthing Notifier.app/Contents/MacOS/notifier"
)

# Notification text. Available placeholders: {folder_name}, {device_name},
# {completion}. Edit to taste; defaults below are used when these are unset.
NOTIFICATION_TITLE_FMT = "Syncthing: {folder_name}"
NOTIFICATION_BODY_FMT = "{device_name} finished receiving updates"

NETWORK_ERRORS = (urllib.error.URLError, ConnectionError, TimeoutError)

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(message)s",
    stream=sys.stdout,
)
log = logging.getLogger("syncthing-notifier")


def load_folders():
    return json.loads(FOLDERS_PATH.read_text())


def load_api_key():
    while True:
        try:
            return ET.parse(CONFIG_XML).getroot().find("gui").findtext("apikey")
        except (FileNotFoundError, ET.ParseError, AttributeError) as e:
            log.info("can't read api key from %s (%s); retrying in 10s", CONFIG_XML, e)
            time.sleep(10)


def api_get(api_key, path, params=None, timeout=70):
    url = f"{GUI}{path}"
    if params:
        url += "?" + urlencode(params)
    req = urllib.request.Request(url, headers={"X-API-Key": api_key})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return json.loads(r.read())


def notify(title, message):
    subprocess.Popen([NOTIFIER_APP, title, message])


def wait_for_syncthing(api_key):
    while True:
        try:
            return api_get(api_key, "/rest/system/status", timeout=5)
        except NETWORK_ERRORS as e:
            log.info("syncthing not reachable (%s), retrying in 10s", e)
            time.sleep(10)


def prime_state(api_key, folders_to_devices):
    state = {}
    for folder, devices in folders_to_devices.items():
        for device in devices:
            try:
                r = api_get(
                    api_key,
                    "/rest/db/completion",
                    {"folder": folder, "device": device},
                    timeout=10,
                )
                state[(folder, device)] = r.get("completion", 100)
            except (*NETWORK_ERRORS, KeyError) as e:
                log.warning("prime failed for %s/%s: %s", folder, device[:7], e)
                state[(folder, device)] = 100
    return state


def latest_event_id(api_key):
    """Highest FolderCompletion event ID currently buffered by Syncthing.

    Used at startup to skip replay of pre-startup events: prime_state already
    captured the current ground truth, so re-processing buffered transitions
    would only generate spurious notifications.
    """
    try:
        events = api_get(
            api_key,
            "/rest/events",
            {"events": "FolderCompletion", "since": 0, "timeout": 1},
            timeout=10,
        )
        return events[-1]["id"] if events else 0
    except (*NETWORK_ERRORS, KeyError):
        return 0


def run_test():
    notify("Syncthing Notifier", "Test notification — installed and ready")


def main():
    if len(sys.argv) > 1 and sys.argv[1] == "--test":
        run_test()
        return

    watch_folders = load_folders()
    log.info("loaded %d watched folder(s) from %s", len(watch_folders), FOLDERS_PATH)

    api_key = load_api_key()
    status = wait_for_syncthing(api_key)
    my_id = status["myID"]
    log.info("local device id %s...", my_id[:7])

    cfg = api_get(api_key, "/rest/config")
    device_names = {
        d["deviceID"]: d.get("name") or d["deviceID"][:7]
        for d in cfg.get("devices", [])
    }
    folders_to_devices = {}
    for f in cfg.get("folders", []):
        if f["id"] not in watch_folders:
            continue
        folders_to_devices[f["id"]] = [
            d["deviceID"] for d in f.get("devices", []) if d["deviceID"] != my_id
        ]
    log.info("watching: %s", folders_to_devices)

    state = prime_state(api_key, folders_to_devices)
    log.info(
        "primed state: %s",
        {
            f"{watch_folders[k[0]]}/{device_names.get(k[1], k[1][:7])}": v
            for k, v in state.items()
        },
    )

    last_id = latest_event_id(api_key)
    log.info("starting from event id %d (skipping replay)", last_id)

    while True:
        try:
            events = api_get(
                api_key,
                "/rest/events",
                {"events": "FolderCompletion", "since": last_id, "timeout": 60},
                timeout=70,
            )
            for e in events:
                last_id = e["id"]
                d = e["data"]
                folder = d.get("folder")
                device = d.get("device")
                completion = d.get("completion", 0)
                need_bytes = d.get("needBytes", 0)
                need_items = d.get("needItems", 0)

                if folder not in watch_folders or device == my_id:
                    continue

                key = (folder, device)
                prev = state.get(key, 100)
                state[key] = completion

                fully_synced = (
                    completion >= 100 and need_bytes == 0 and need_items == 0
                )
                if prev < 100 and fully_synced:
                    folder_name = watch_folders[folder]
                    device_name = device_names.get(device, device[:7])
                    log.info("notify: %s -> %s synced", folder_name, device_name)
                    fmt_args = {
                        "folder_name": folder_name,
                        "device_name": device_name,
                        "completion": completion,
                    }
                    notify(
                        NOTIFICATION_TITLE_FMT.format(**fmt_args),
                        NOTIFICATION_BODY_FMT.format(**fmt_args),
                    )
        except NETWORK_ERRORS as e:
            log.warning("event poll failed (%s); reconnecting in 5s", e)
            time.sleep(5)
            wait_for_syncthing(api_key)
        except Exception as e:
            log.exception("unexpected error: %s", e)
            time.sleep(5)


if __name__ == "__main__":
    main()
