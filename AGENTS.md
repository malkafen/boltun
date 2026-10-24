# Boltun — contributor guide

Boltun is a native macOS client for Mattermost, written in Swift (AppKit + SwiftUI). It replaces the Electron-based
[mattermost/desktop](https://github.com/mattermost/desktop) for text messaging across multiple servers. It talks to the
Mattermost REST API v4 and WebSocket directly; there is no web view.

## Rules

- Everything in the repository is in English: code, identifiers, docs, commit messages, PRs.
- No comments in source code. Make the code self-explanatory with naming and small functions.
- Swift 6 language mode, strict concurrency. UI state is `@MainActor`.
- Dark appearance only (`.preferredColorScheme(.dark)` / `NSAppearance(named: .darkAqua)`).
- Maximize test coverage. Every new type or behavior gets tests (Swift Testing: `import Testing`, `@Test`, `#expect`).
- Prefer performance and low resource use: lazy lists, no polling, cache images, avoid needless re-rendering.
- Audio/video calls are out of scope.

## Layout

| Target | Purpose |
| --- | --- |
| `BoltunKit` | Models, REST client (`APIClient`), WebSocket (`RealtimeClient`), state (`ServerSession`, `AppModel`), storage. No UI. |
| `BoltunMarkup` | Mattermost markdown → `AttributedString`, emoji, mentions. |
| `BoltunUI` | SwiftUI/AppKit views, windows, menus, notifications, dock badge. |
| `Boltun` | Executable entry point only. |

Tests live in `Tests/<Target>Tests`. Network is mocked with `HTTPTransport` / `WebSocketConnector` fakes.

## Building and testing

Swift is only available on the macOS build host. Sync the working tree and run commands there:

```bash
MAC_DIR=boltun-<yourname> scripts/mac.sh 'swift build'
MAC_DIR=boltun-<yourname> scripts/mac.sh 'scripts/test.sh'
MAC_DIR=boltun-<yourname> scripts/mac.sh 'scripts/coverage.sh'
MAC_DIR=boltun-<yourname> scripts/mac.sh 'scripts/build-app.sh'
```

Use a distinct `MAC_DIR` per parallel worker so builds do not collide.

## Test servers

Two Mattermost servers run in Docker on the Linux dev host (`scripts/testenv/up.sh`):

- `http://192.168.15.101:8065` (3 teams) and `http://192.168.15.101:8066` (2 teams)
- user `boltun` / `Boltun-pass1` (system admin), sample users `sysadmin` / `Sys@dmin-sample1`
- `scripts/testenv/chatter.py <url> <count> <delay>` posts live traffic (mentions, DMs, markdown) as `sysadmin`.
