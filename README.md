# Boltun

A fast, native macOS client for [Mattermost](https://mattermost.com), built with Swift, SwiftUI and AppKit.
It is a lightweight replacement for the Electron-based [Mattermost Desktop](https://github.com/mattermost/desktop):
no bundled browser, no web view, just the Mattermost REST API and WebSocket.

## Features

- Multiple servers side by side, each with its own session and unread/mention badges
- Teams in a vertical team sidebar with icons and unread badges (⌃⌘1…9 jumps to a team, ⌃⌘↑/↓ cycles teams); drag teams to reorder them and pin favorites above a divider
- Sidebar categories (favorites, channels, direct messages), unread and mention counters
- Real-time messages, edits, deletions, reactions and typing indicators over WebSocket
- Markdown rendering, emoji, @mentions, code blocks, links, file attachments and image previews
- Collapsed reply threads (on by default): replies open in the thread pane with participants, reply count and last reply time; turn it off in Settings to show replies inline
- Thread following: follow or unfollow a thread from its footer, the thread pane or the message menu; threads where you are mentioned, `@all`/`@channel` is used or one of your notification keywords appears are followed automatically, as the server's notification settings decide
- Presence: online, away and do-not-disturb dots on message avatars, direct messages and search results, and your own status picker in the sidebar header
- Message priority: send standard, important or urgent messages with an optional acknowledgement request and persistent notifications; priority labels appear next to the author
- Acknowledgements: acknowledge a message that asked for it, see the count and who acknowledged it and when, updated live
- Burn-on-read messages: recipients reveal a concealed message and watch its countdown, the sender sees how many recipients read it, and expired messages disappear by themselves
- Search, quick channel switcher
- Native notifications and a dock badge
- Dark theme

Priority, acknowledgements and burn-on-read follow the server: their controls stay hidden where the configuration or the
license does not offer them. Audio and video calls are not supported.

## Install

Download the latest `Boltun-*-macos-arm64.zip` from [Releases](https://github.com/malkafen/boltun/releases),
unzip it and move `Boltun.app` to `/Applications`. The app is ad-hoc signed, so on first launch right-click it and
choose **Open**, or run:

```bash
xattr -dr com.apple.quarantine /Applications/Boltun.app
```

Requires macOS 15 or later on Apple Silicon.

## Build from source

```bash
scripts/test.sh          # run the tests
scripts/coverage.sh      # tests with a coverage report
scripts/build-app.sh     # build/Boltun.app
```

See [AGENTS.md](AGENTS.md) for the project layout and conventions.

## License

Apache License 2.0, see [LICENSE](LICENSE).
