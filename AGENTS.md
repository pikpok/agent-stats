# AGENTS.md

## Build and verification
- SwiftPM product name is `AgentStatsBar`, but the packaged app is `dist/Agent Stats.app`. Use `swift run AgentStatsBar`; use the bundle name when opening/installing the built app.
- Run from source: `swift build && swift run AgentStatsBar`
- Build the release app bundle: `./scripts/build-app.sh`
- Install/reinstall the bundle: `./scripts/build-app.sh --install` (the script installs to the existing copy in `~/Applications` or `/Applications`, stops a running installed copy first, and relaunches it afterward if needed).
- Mirror CI for non-doc changes: `swift test` -> `./scripts/build-app.sh`. CI runs on macOS with Swift 6.3.1 and does not have separate lint/formatter/typecheck steps.
- Useful CLI checks: `swift run AgentStatsBar --dump-snapshot`, `--install-claude-helper`, `--enable-launch-at-login`, `--disable-launch-at-login`, `--launch-at-login-status`

## Repo shape
- This is a single SwiftPM executable package (`Package.swift`): macOS 14+, Swift language mode 6, source in `Sources/AgentStatsBar/`, tests in `Tests/AgentStatsBarTests/`.
- `Sources/AgentStatsBar/App/Main.swift` is the real entrypoint. It dispatches CLI-only modes before app launch; normal app launch opens the dashboard unless `--background` is present.
- `Sources/AgentStatsBar/App/AppModel.swift` is the central coordinator: it starts the 60-second polling loop, fetches Codex/Claude/Cursor concurrently, sorts by `ServiceKind.sortOrder`, and derives the menu bar text.
- `Sources/AgentStatsBar/Models/ServiceSnapshot.swift` is the shared provider/UI contract. Window titles (`5h`, `7d`, `Plan`, `Included`, `On-demand`) are semantic: `AppModel.compactValue` depends on them when choosing what appears in the menu bar.

## Service-specific gotchas
- Codex treats missing `~/.codex/auth.json` as logged out. It prefers live app-server rate limits, then falls back to the latest `token_count` event in `~/.codex/sessions/*.jsonl`; fallback snapshots older than 12 hours become `stale`.
- Claude prefers desktop-session usage fetches. Fallback data lives at `~/.claude/agent-stats/usage.json`.
- `swift run AgentStatsBar --install-claude-helper` writes `~/.claude/agent-stats/claude_statusline.py` and only auto-updates `~/.claude/settings.json` when there is no custom `statusLine.command`; existing custom status lines are left alone.
- Cursor auth is read from `~/Library/Application Support/Cursor/User/globalStorage/state.vscdb`, then the provider tries `https://cursor.com/api/usage-summary` before legacy `https://cursor.com/api/usage`. HTTP 401/403 is treated as logged out; an unparseable success response is treated as API drift/stale data.
- Launch at login writes `~/Library/LaunchAgents/com.pikpok.AgentStatsBar.plist` for the current executable path. Enable it from the built `.app`, not `swift run`, if you want the launch target to stay stable.

## Tests and generated outputs
- Tests use Swift Testing (`import Testing`), not XCTest.
- `Tests/AgentStatsBarTests/AgentStatsBarTests.swift` is the executable spec for provider payload shapes and menu bar precedence; update it whenever you change parsing or compact display logic.
- `.build/` and `dist/` are generated outputs; do not hand-edit packaged app contents.
