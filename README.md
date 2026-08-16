# reminders-stats

macOS CLI that reads **Apple Reminders** on this Mac (same iCloud account as your iPhone), computes punctuality stats, and overwrites **one Notion page**. Reminders stay in the Apple app. Notion is a scoreboard, not a second task list.

There is no public iCloud Reminders API. This tool uses EventKit locally, then the Notion API.

## What you get in Notion

- Colored KPI cards: on time %, late %, open overdue, done this week
- Average early/late and done this month
- Per-list stats table
- Read-only tables of **overdue** and still-**open** reminders (title, list, due, status as text — no checkboxes)
- The overdue card links to the Overdue section

Mark items done in Apple Reminders. Notion is a snapshot; the next sync overwrites the page. You can lock the page in Notion (••• → Lock) if you want to block casual edits.

## How scoring works

Comparisons use this Mac’s timezone. Only lists in your config allow-list are counted.

| Case | Rule |
|---|---|
| Due with a time | On time if completed at or before that instant |
| Date only (all-day) | Apple’s rule: overdue starting the **next calendar day**. Finishing at 22:00 on the due day is still on time. Stored `00:00` dues are treated as date-only. |
| No due date | Excluded from on-time / late / overdue / average. Still counts in week/month volume if completed. |
| Week / month | ISO week Monday–Sunday, and calendar month, by `completionDate` |
| Average | Mean of signed deltas (positive = early). Date-only uses whole days. |

## Requirements

- macOS 14+
- Xcode (Command Line Tools alone cannot run `swift test` on this machine)
- This Mac signed into the same iCloud account as the iPhone, with Reminders visible
- A Notion internal integration and a page shared with it

## Setup

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
swift test
swift build -c release
```

1. Create a [Notion internal integration](https://www.notion.so/my-integrations) and copy the token.
2. Create a Notion page, share it with that integration, copy the page id (from the URL).
3. Install the config (not in this repo — it holds the token):

```bash
mkdir -p ~/.config/reminders-stats
cp config.example.toml ~/.config/reminders-stats/config.toml
```

4. Grant Reminders access when macOS asks, then copy exact list names into `lists`:

```bash
.build/release/reminders-stats lists
```

5. Publish:

```bash
.build/release/reminders-stats sync --force
```

6. Optional — refresh automatically on this Mac:

```bash
.build/release/reminders-stats install-agent
```

`NOTION_TOKEN` in the environment overrides `notion_token` in the file.

## Config

`~/.config/reminders-stats/config.toml`:

```toml
notion_token = "secret_…"
notion_page_id = "…"
lists = ["Work", "Personal"]
```

List names must match Reminders exactly (case-sensitive). Never commit a real `config.toml`.

## Commands

| Command | Purpose |
|---|---|
| `lists` | Print Reminders list names |
| `sync` | Compute and publish (skipped if last success &lt; 12h) |
| `sync --force` | Ignore the 12h stamp |
| `install-agent` | Copy the binary, install a LaunchAgent |
| `uninstall-agent` | Unload and remove the LaunchAgent |
| `help` | Show help |

## Automatic refresh

`install-agent` registers `~/Library/LaunchAgents/dev.aumarin.reminders-stats.plist`. launchd runs `sync` at login and every 15 minutes. The tool itself no-ops if the last **successful** Notion write was less than 12 hours ago. Failed writes do not update the stamp, so the next tick retries.

If you rebuild the CLI, run `install-agent` again so the agent uses the new binary.

## Local paths

| Path | Role |
|---|---|
| `~/.config/reminders-stats/config.toml` | Token, page id, allow-list |
| `~/.local/state/reminders-stats/last_success` | 12h skip stamp |
| `~/Library/Logs/reminders-stats.log` | Agent / sync log |
| `~/Library/Application Support/reminders-stats/reminders-stats` | Installed binary |

## Privacy

- EventKit is **read-only**. The tool never creates, completes, or deletes reminders.
- The Notion token lives only in your config file or environment.
- The GitHub repo should stay private if it might ever contain local notes; the token must never be committed.

## Develop

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
swift test
swift build
```
