# reminders-stats

A small **macOS** CLI that reads [Apple Reminders](https://support.apple.com/guide/iphone/use-reminders-iph78ef25f1d/ios) on your Mac and publishes a **stats dashboard** to one [Notion](https://www.notion.com/) page.

Reminders stay in Apple’s app. Notion is a scoreboard, not a second task list.

Apple does not offer a public cloud API for Reminders. This tool reads lists locally with [EventKit](https://developer.apple.com/documentation/eventkit) (iCloud must already sync those lists to the Mac), then writes the page with the [Notion API](https://developers.notion.com/).

Not affiliated with Apple or Notion.

## Features

- Punctuality: on time vs late, plus still-open overdue
- Volume: completed this ISO week (Monday–Sunday) and this calendar month
- Mean early / late
- Breakdown by Reminders list (explicit allow-list)
- Read-only tables of overdue and still-open reminders (title, list, due, status as text — no checkboxes)
- Overdue KPI card links to the Overdue section
- Optional LaunchAgent: check often, publish at most every 12 hours

The next sync **replaces the Notion page body**. Complete tasks in Reminders. Optionally lock the Notion page (`•••` → Lock) so the snapshot is harder to edit by hand.

## Requirements

- macOS 14 or later
- [Xcode](https://developer.apple.com/xcode/) (the full app, not only Command Line Tools — `swift test` needs it)
- The Mac signed into the **same iCloud account** as the iPhone, with Reminders showing up in the Reminders app
- A Notion [internal integration](https://www.notion.so/my-integrations) and a page shared with that integration

## Quick start

```bash
git clone https://github.com/AurelienMarin/sync-reminders-notion.git
cd sync-reminders-notion

export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
swift test
swift build -c release
```

1. Create a Notion internal integration and copy the secret token.
2. Create a page, share it with the integration, copy the page id from the URL.
3. Keep secrets **out of the repo**:

   ```bash
   mkdir -p ~/.config/reminders-stats
   cp config.example.toml ~/.config/reminders-stats/config.toml
   # edit token, page id, and list names
   ```

4. Grant Reminders access when macOS prompts, then copy names exactly:

   ```bash
   .build/release/reminders-stats lists
   ```

5. Publish:

   ```bash
   .build/release/reminders-stats sync --force
   ```

6. Optional automatic refresh on this Mac:

   ```bash
   .build/release/reminders-stats install-agent
   ```

`NOTION_TOKEN` in the environment overrides `notion_token` in the file.

## Configuration

`~/.config/reminders-stats/config.toml` (see `config.example.toml`):

```toml
notion_token = "secret_…"
notion_page_id = "…"
lists = ["Work", "Personal"]
```

List names are case-sensitive and must match Reminders.

**Do not commit a real token or `config.toml`.** `.gitignore` already ignores `config.toml` and `.env`. If a token ever lands in git, revoke it in Notion and create a new integration secret.

## Scoring

All comparisons use the Mac’s current timezone. Only allow-listed lists are counted. **Overall** is the union of those lists.

| Case | Rule |
| --- | --- |
| Due with a time | On time if completed at or before that instant |
| Date only (all-day) | Matches Apple Reminders: overdue starting the **next calendar day**. Finishing at 22:00 on the due day is on time. A stored due of `00:00` is treated as date-only. |
| No due date | Ignored for on-time / late / overdue / average. Still counts toward week/month volume if completed. |
| Week / month | ISO week Monday–Sunday, and calendar month, using `completionDate` |
| Average | Mean signed delta (positive = early). Date-only uses whole days. |

## Commands

| Command | Purpose |
| --- | --- |
| `lists` | Print Reminders list names |
| `sync` | Compute and publish (skipped if the last success was less than 12 hours ago) |
| `sync --force` | Publish even if the 12-hour stamp is fresh |
| `install-agent` | Install a signed copy of the binary and a LaunchAgent |
| `uninstall-agent` | Unload and remove the LaunchAgent |
| `help` | Show help |

## Automatic refresh

`install-agent` writes a LaunchAgent that runs `sync` at login and every 15 minutes. The 12-hour rule is enforced **inside the tool**: if the last successful Notion write is newer than 12 hours, `sync` exits without publishing. Failed writes do not update the stamp, so the next tick retries.

After you rebuild, run `install-agent` again so the agent uses the new binary.

## Local paths

| Path | Role |
| --- | --- |
| `~/.config/reminders-stats/config.toml` | Token, page id, allow-list |
| `~/.local/state/reminders-stats/last_success` | 12-hour skip stamp |
| `~/Library/Logs/reminders-stats.log` | Sync / agent log |
| `~/Library/Application Support/reminders-stats/reminders-stats` | Installed binary |

## Privacy and security

- EventKit access is **read-only**. The tool does not create, complete, or delete reminders.
- The Notion token stays on your machine (config file or environment). Treat it like a password.
- The published Notion page contains reminder **titles**, list names, and due dates for open and overdue items. Share that page only with people who should see them.
- This repository is meant to stay free of secrets. Example config uses placeholders only.

## Development

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
swift test
swift build
```

Bug reports and pull requests are welcome. Please run `swift test` before opening a PR.

## License

MIT. See [LICENSE](LICENSE).
