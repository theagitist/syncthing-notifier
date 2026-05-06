# Syncthing Notifier

macOS notifications when remote Syncthing devices finish receiving updates from
*this* machine. Notifications are attributed to a real `.app` bundle so you can
target them with Focus filters.

## What you get

A notification like *"Syncthing: FolderLabel1 — DEVICE finished receiving
updates"* every time a remote device transitions to fully synced (100%, no
needBytes/needItems remaining) for one of the watched folders.

## Architecture

- **`notifier.py`** — long-poll daemon that subscribes to Syncthing's
  `FolderCompletion` events on `http://127.0.0.1:8384/rest/events`, filters to
  watched folders, and detects per-device transitions from <100% to fully
  synced. Runs under launchd.
- **`notifier_app.swift`** — tiny Swift CLI built into a `.app` bundle that
  posts notifications via `UNUserNotificationCenter`. Bundled and signed
  ad-hoc so macOS registers it as a distinct app for permissions and Focus.
- **`launchd.plist.template`** — launchd agent that runs the Python daemon
  at login and keeps it alive. Bundle ID and home path are substituted into
  the deployed copy by `install.sh`.

The Python daemon shells out to the Swift app for every notification, passing
title and message as argv.

## Install

```sh
cp config.env.example config.env       # edit if you want a different bundle ID
cp folders.json.example folders.json   # edit with your real Syncthing folder IDs
./install.sh
```

Both `config.env` and `folders.json` are gitignored — your bundle ID and the
list of watched folders stay local. `install.sh` warns if `folders.json`
still contains the placeholder IDs.

This builds the `.app`, copies the daemon to `~/Library/Application
Support/syncthing-notifier/`, drops the launchd plist into
`~/Library/LaunchAgents/`, and (re)loads the agent.

**First install:** `install.sh` fires a test notification at the end of
the run, which triggers the macOS permission prompt — click **Allow**.
Then add Syncthing Notifier to your Focus filters at **System Settings →
Focus → \[mode\] → Apps**.

## Configure

Watched folders live in `folders.json` (gitignored). Edit it and re-run
`./install.sh`:

```json
{
    "REPLACE_FOLDER_ID_1": "FolderLabel1",
    "REPLACE_FOLDER_ID_2": "FolderLabel2"
}
```

Keys are Syncthing folder IDs (Syncthing GUI → folder → *Folder ID*).
Values are the labels shown in notifications.

Notification text is controlled by `NOTIFICATION_TITLE_FMT` and
`NOTIFICATION_BODY_FMT` near the top of `notifier.py`. Available
placeholders: `{folder_name}`, `{device_name}`, `{completion}`. Defaults:

```python
NOTIFICATION_TITLE_FMT = "Syncthing: {folder_name}"
NOTIFICATION_BODY_FMT = "{device_name} finished receiving updates"
```

## Operate

```sh
# tail logs
tail -f ~/Library/Logs/syncthing-notifier.log

# check the agent
launchctl list | grep syncthing-notifier

# kick it (e.g. after editing notifier.py and re-running install.sh)
launchctl kickstart -k "gui/$(id -u)/$(. ./config.env && echo "$BUNDLE_ID")"

# fire a manual test notification (also re-triggers permission prompt)
python3 ~/Library/Application\ Support/syncthing-notifier/notifier.py --test
```

## Uninstall

```sh
./uninstall.sh
```

Removes the launchd agent, the runtime daemon, and the `.app` bundle.
Notification permission entry can be cleared with
`tccutil reset All "$BUNDLE_ID"` (where `$BUNDLE_ID` is the value from
`config.env`).

## Requirements

- macOS 11+
- Syncthing running with the GUI on `127.0.0.1:8384` (default)
- `swiftc` (ships with Xcode Command Line Tools)
- `/usr/bin/python3` (preinstalled)

## Notes

- The Syncthing API key is read at runtime from
  `~/Library/Application Support/Syncthing/config.xml`, not embedded.
- Only outbound completion is signaled. Inbound (this device finishing a pull
  from a remote) is filtered out by comparing the event's `device` field to
  `myID` from `/rest/system/status`.
- If a remote is offline when you push changes, the notification fires when
  it next comes online and finishes pulling.
