# Boltun

A fast, native macOS client for [Mattermost](https://mattermost.com), built with Swift, SwiftUI and AppKit.
It is a lightweight replacement for the Electron-based [Mattermost Desktop](https://github.com/mattermost/desktop):
no bundled browser, no web view, just the Mattermost REST API and WebSocket.

## Features

- Multiple servers side by side, each with its own session and unread/mention badges
- Teams in a vertical team sidebar with icons and unread badges (⌃⌘1…9 jumps to a team, ⌃⌘↑/↓ cycles teams)
- Sidebar categories (favorites, channels, direct messages), unread and mention counters
- Real-time messages, edits, deletions, reactions and typing indicators over WebSocket
- Markdown rendering, emoji, @mentions, code blocks, links, file attachments and image previews
- Threads, search, quick channel switcher
- Native notifications and a dock badge
- Dark theme

Audio and video calls are not supported.

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
