# Debug automation

Boltun is developed on a build host that is reached over SSH, where screen capture and synthetic keyboard input are not
available. To drive and inspect the running app anyway, Boltun accepts `boltun://debug/...` URLs when debug automation
is enabled. With the flag off (the default) these URLs are ignored entirely.

## Enabling

```bash
defaults write io.github.malkafen.boltun BoltunDebugAutomation -bool YES
```

Disable it again with `defaults delete io.github.malkafen.boltun BoltunDebugAutomation`.

While the flag is on, session tokens are stored in
`~/Library/Application Support/Boltun/debug-credentials.json` (mode `0600`) instead of the Keychain. Every local build
gets a new ad-hoc code signature, and the Keychain would otherwise block the app on an access prompt that nobody can
answer over SSH.

## Sending commands

Build and launch the bundle, then open URLs with `open`. Passing the bundle with `-a` makes sure the URL reaches this
build even if another copy of Boltun is registered for the `boltun` scheme.

```bash
scripts/build-app.sh
APP=build/Boltun.app
open "$APP"
open -a "$APP" 'boltun://debug/add-server?url=http://192.168.15.101:8065'
open -a "$APP" 'boltun://debug/login?server=0&user=boltun&password=Boltun-pass1'
open -a "$APP" 'boltun://debug/select?server=0&team=ad-1&channel=town-square'
open -a "$APP" 'boltun://debug/snapshot?path=/tmp/boltun/main.png'
open -a "$APP" 'boltun://debug/state?path=/tmp/boltun/state.json'
```

Commands run asynchronously. Each result is appended to `/tmp/boltun-automation.log` as `ok <command> [detail]` or
`error <command> <reason>`, so a script can wait for and check the outcome.

From the Linux dev host, run the same commands through `ssh macbox@192.168.5.90` and copy outputs back with `scp`.

## Commands

| Command | Effect |
| --- | --- |
| `snapshot?path=/tmp/x.png[&window=main\|sheet\|settings\|key]` | Renders a window to PNG. `sheet` is the sheet attached to the main window. |
| `state?path=/tmp/x.json` | Dumps servers, connection states, selected team and channel, unread and mention counts, visible post count, badge, open sheet and window visibility. |
| `add-server?url=<url>[&name=<name>]` | Validates the server and adds it. The site name is used when `name` is omitted. |
| `login?server=<index>&user=<login>&password=<password>` | Logs in to the server at the given index (default 0). |
| `logout?server=<index>` | Logs out of a server. |
| `select?server=<index>[&team=<name>][&channel=<name>]` | Selects a server, and optionally a team and channel by name or display name. |
| `open?url=<percent-encoded url>` | Routes a `mattermost://`, `boltun://` or `https://` link as if it was opened from outside. |
| `present?sheet=add-server\|login[&server=<index>]` | Presents the add-server or login sheet. |
| `dismiss` | Dismisses the current sheet. |
| `settings[?tab=servers\|general\|about]` | Opens the Settings window on a tab. |
| `show` | Shows the main window. |
| `close` | Closes the main window, which hides it while the app keeps running. |
| `notify[?title=..&body=..]` | Delivers a test notification for the current channel. |
| `quit` | Terminates the app. |

Output paths must be absolute and inside `/tmp` or `/private/tmp`; paths containing `..` and existing symbolic links
are rejected.

## Example: full smoke run

```bash
APP=~/src/boltun/build/Boltun.app
d() { open -a "$APP" "boltun://debug/$1"; sleep "${2:-1.5}"; }
open "$APP"; sleep 4
d 'snapshot?path=/tmp/bs/welcome.png'
d 'add-server?url=http://192.168.15.101:8065' 3
d 'snapshot?path=/tmp/bs/login.png&window=sheet'
d 'login?server=0&user=boltun&password=Boltun-pass1' 5
d 'select?server=0&team=ad-1&channel=town-square' 3
d 'snapshot?path=/tmp/bs/main.png'
open -a "$APP" 'mattermost://192.168.15.101:8065/amet-2/channels/off-topic'; sleep 3
d 'state?path=/tmp/bs/state.json'
d 'settings?tab=general' 2
d 'snapshot?path=/tmp/bs/settings.png&window=settings'
cat /tmp/boltun-automation.log
```

## Snapshots in tests

UI tests render SwiftUI views offscreen with `Snapshot.png(_:size:)`. Set `BOLTUN_SNAPSHOT_DIR` to keep the images:

```bash
BOLTUN_SNAPSHOT_DIR=/tmp/boltun-test-shots swift test --filter BoltunUITests
```
