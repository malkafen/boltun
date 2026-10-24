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
| `remove-server?server=<index>` | Removes the server at the given index, as the Settings window does. |
| `setting?name=spellChecking\|collapsedThreads&value=0\|1` | Changes a preference: spell checking or collapsed reply threads. |
| `present?sheet=add-server\|login\|browse\|dm\|notifications[&server=<index>]` | Presents the add-server, login, browse-channels, direct-messages or channel notification preferences sheet. |
| `dismiss` | Dismisses the current sheet. |
| `settings[?tab=servers\|general\|about]` | Opens the Settings window on a tab. |
| `show` | Shows the main window. |
| `close` | Closes the main window, which hides it while the app keeps running. |
| `notify[?title=..&body=..]` | Delivers a test notification for the current channel. |
| `quit` | Terminates the app. |

### Workspace interaction

These commands act on the selected server's current channel. Commands that take `thread=1` target the reply composer
of the open thread instead of the channel composer. Flags accept `1`, `true`, `yes` or `on`. Post indexes count back
from the newest regular post, so `index=0` is the last one.

| Command | Effect |
| --- | --- |
| `send?text=<text>[&thread=1]` | Puts the text into the composer and sends it through the same queue as Enter. The log detail carries the session error, if any. |
| `type?text=<text>[&thread=1]` | Replaces the composer text, focuses it and emits a typing event, so autocomplete suggestions appear. |
| `key?name=enter\|up\|down\|tab\|escape[&mods=shift,option,command,control][&thread=1]` | Routes a key press through the composer key handling. The detail names the resulting action. |
| `upload?path=/tmp/<file>[&thread=1]` | Attaches a file to the composer. Send it afterwards with `send` or `key?name=enter`. |
| `edit-last?text=<text>` | Edits your newest post in the channel. |
| `delete-last` | Deletes your newest post in the channel. |
| `react?emoji=<name>[&index=<n>]` | Toggles a reaction on a post. |
| `open-thread[?index=<n>][&post=<id>]` | Opens the thread of a post in the right pane. |
| `close-pane` | Closes the right pane. |
| `scroll?to=top\|bottom\|<post id>` | Scrolls the message list to an edge, or centers and highlights a post. |
| `quickswitch[?query=<text>][&choose=1][&close=1]` | Opens the quick switcher with a query; `choose=1` opens the first result and `close=1` hides it. |
| `search?q=<terms>` | Runs a message search. The detail is the number of results. |
| `jump[?index=<n>]` | Jumps to a search result. |
| `join?channel=<name>` | Joins a public channel by name or display name. |
| `leave` | Leaves the current channel. |
| `favorite[?on=0]` | Adds the current channel to favorites, or removes it with `on=0`. |
| `mute[?on=0]` | Mutes the current channel, or unmutes it with `on=0`. The detail is the resulting state. |
| `notify-prefs[?mute=1][&desktop=default\|all\|mention\|none][&threads=default\|all\|mention][&ignore=1]` | Changes the current channel's notification preferences, as the Notification Preferences sheet does. `threads` also accepts `1`/`0` for all/mentions. The detail is the resulting settings. |
| `team-mute?team=<name>[&on=0]` | Mutes notifications for a team, or unmutes it with `on=0`. The detail is the resulting state. |
| `collapse?category=<title>[&collapsed=0]` | Collapses a sidebar category by title, or expands it with `collapsed=0`. `on` is accepted as an alias. |
| `team-favorite?team=<name>[&on=0]` | Pins a team to the favorites above the divider in the team sidebar, or unpins it with `on=0`. The detail is the resulting team order. |
| `team-move?team=<name>&to=<name>` | Moves a team onto another one, as dropping it there does. Use `end=favorites\|others` instead of `to` to move it to the end of a section. |
| `link?url=<percent-encoded url>` | Handles a link as if it was clicked in a message, including permalinks and channel links. |
| `notification-click?channel=<id>[&server=<index>][&team=<id>][&root=<id>]` | Routes a notification response the same way as clicking a delivered notification. |
| `follow[?on=0][&post=<root id>]` | Follows the open thread (or the given root post), or unfollows it with `on=0`. The detail is the resulting state. |
| `set-status?status=online\|away\|dnd\|offline` | Sets your own status, as the avatar menu in the sidebar header does. The detail is the resulting status. |
| `command?name=<name>[&number=<n>]` | Runs a menu or keyboard command, listed below. |

`command` names: `focus-search`, `focus-composer`, `quick-switcher`, `toggle-sidebar`, `toggle-pane`, `zoom-in`,
`zoom-out`, `zoom-reset`, `next-server`, `previous-server`, `server` (with `number`, 1-based), `next-channel`,
`previous-channel`, `next-unread`, `browse`, `direct-messages`, `close-sheets` and `preview-last-image`.

### UI state

`state` lists teams in sidebar order with `favoriteTeams` and `mutedTeams`, and also writes a `ui` object for the selected workspace. It includes the window title, first responder, open right
pane and thread posts, quick switcher and search results, the highlighted post, the scroll report (distances from
the top and bottom, content height, unseen count for the new-messages pill, older-page requests), timeline size and paging flags, the last posts with reactions and files, both composers (text, editing post,
suggestions, uploads, height), typing users, unread and mention channels, favorites, `mutedChannels`, collapsed categories, open sheets,
the last session error, the workspace and cached post counts, `editors`, the spell-checking and font size of every
live composer text view, `collapsedThreads`, `myStatus` and `threadFollowing` for the open thread. Post summaries carry
`replyCount`, the author's `status` and, for root posts, `following`.

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
