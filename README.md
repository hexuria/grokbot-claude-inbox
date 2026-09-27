# grokbot-claude-inbox

Run Claude Code while you're away from your desk. Every Claude Code session on your computer reports to one Grok Bot agent. When a session needs you, you get a short brief on your phone, and your answer reaches the session within seconds. Claude never sits blocked on a question in a terminal nobody is watching.

- **One Grok Bot, many sessions.** Each session gets its own webhook routine and inbox, so conversations never cross.
- **Claude keeps working.** It asks through a ping, then carries on with anything that doesn't need the answer.
- **You decide how much Grok Bot decides.** Per session, it either brings you every decision, or also approves merges once CI is green and the review passes.
- **Mac and Windows.** Shell scripts for the Mac and Git Bash, PowerShell twins for Windows.

## How it works

```text
Claude Code ──ping──▶ Grok Bot routine "Claude · parser" ──brief──▶ your phone
     ▲                                                                  │
   watch ◀──── ~/.grokbot/inbox/parser.jsonl ◀──── reply ◀──────────────┘
```

1. Claude runs `~/.grokbot/ping parser decision` with its question. The script posts it to the session's own webhook routine.
2. The routine sends you a brief of at most five lines. You answer in the Grok Bot chat.
3. Grok Bot runs `~/.grokbot/reply parser user`, which appends one JSON line to the session's inbox.
4. Claude keeps `~/.grokbot/watch parser` running in the background. The watcher exits as soon as the line lands, and that exit wakes Claude with your answer.

Nothing types into your terminal. Grok Bot reaches Claude only through the inbox.

## Requirements

- **Mac:** Claude Code, `git`, and `curl` 7.76 or newer. Tested with Claude Code 2.1.283.
- **Windows:** Claude Code with Git for Windows, PowerShell 5.1 or newer, `git`, and `curl`. Claude runs the shell scripts through Git Bash; Grok Bot runs the PowerShell ones.
- A Grok Bot agent with webhook routines and local execution on that computer.

Every ping starts one routine run, which counts against your Grok Bot usage.

## Install

In Grok Bot, say:

```text
Install this skill: https://github.com/hexuria/grokbot-claude-inbox
```

Grok Bot fetches the repository into its skills folder. Then say `add session`. The agent clones this repository onto your computer, copies the scripts into `~/.grokbot`, adds allow rules for `ping` and `watch` to Claude Code after asking you, creates the routine, and connects the session.

Without that install command, copy `skill/` into your Grok Bot skills library as `grokbot-claude-inbox`, keeping `scripts/` and `references/` next to `SKILL.md`.

Grok Bot's local execution needs one decision from you. If it asks before each command, replies stall while you are away. If it has standing permission, it can run commands on your computer unattended. Choose knowingly.

### The webhook credentials

Grok Bot cannot read a routine's webhook URL or token. Only you can, from the routine's page, so it sends you two links there. If you are at your computer, `bind` opens two dialogs on it and you paste each value in; nothing passes through chat. If you are away, you paste both values into the Grok Bot chat and it writes them for you, which leaves the token in your chat history.

## Commands

| Say | What happens |
|---|---|
| `add session` or `setup` | Binds a Claude session: routine, env file, inbox, and the standing prompt. |
| `list sessions` | Shows each session, whether Claude is listening, and unread replies. |
| `reconnect parser` | Gives Claude the standing prompt again after a restart or `/clear`. |
| `remove parser` or `cleanup` | Tells Claude to stop, deletes the routine, and archives the inbox. |

To answer a session, reply to its brief in the Grok Bot chat. To give a session work, say something like `tell parser to add retries to the fetch client`.

## Examples

### Bind a session that's already open

You already have Claude working in `~/code/parser`. Grok Bot finds it with `claude agents --json` and does not start a second copy.

```text
You:      add session
Grok Bot: Which project folder, and what should I call the session?
You:      ~/code/parser, call it parser
Grok Bot: What may I decide for parser without you?
          [Ask me every time]  [Also approve merges when CI is green and the review approves]
You:      Ask me every time
Grok Bot: Routine "Claude · parser" is saved. Open these two links and copy the values:
          [webhook URL]  [Authorization header]
          Two dialogs are open on your Mac; paste each value there.
          ...
Grok Bot: Webhook self-test succeeded. Claude is already open in ~/code/parser,
          so I won't start another one. Paste this into that session: <standing prompt>
          ...
Grok Bot: parser is connected. Sessions now: parser, docs-site.
```

If the open session is a background one, Grok Bot tells you to run `claude attach <id>`, paste the prompt, and leave with ←.

### Start a new session in the background

When nothing is running in the folder, Grok Bot offers to start Claude for you. If the folder doesn't exist yet, it asks before creating it.

```text
You:      add session, new one on ~/code/billing
Grok Bot: ...
          How should we connect Claude for billing?
          [Start background Claude for me]  [I'll paste it myself]
You:      Start background Claude for me
Grok Bot: ~/code/billing doesn't exist.
          [Create the folder and start Claude]  [Use a different path]
You:      Create the folder and start Claude
Grok Bot: Bound billing. Setup pong landed; watcher is up. Claude id 7247efce.
```

The standing prompt makes Claude start its watcher and send a test ping. Grok Bot answers `pong`, and the session is live. `claude attach 7247efce` opens it in a terminal.

### Answer a decision from your phone

Claude hits a choice and pings instead of waiting:

```sh
~/.grokbot/ping parser decision <<'GROKBOT_END'
PR #12 (streaming tokenizer) is green: 214 tests pass, CI https://github.com/acme/parser/actions/runs/123.
Merge now, or wait for the fuzz run (about 40 min)?
Recommend: merge now; the fuzz run gates the release, not this PR.
Default if no answer: wait for the fuzz run.
Reply "merge #12" or "wait for fuzz".
GROKBOT_END
```

Your phone shows the brief:

```text
parser · decision
PR #12 (streaming tokenizer) is green. Merge now or wait ~40 min for fuzzing?
Recommend: merge now. Default: wait.
Reply "merge #12" or "wait for fuzz".
github.com/acme/parser/pull/12
```

You reply `merge #12`. Grok Bot appends:

```json
{"session":"parser","from":"grokbot","by":"user","ts":"2026-09-27T09:41:00Z","message":"re PR #12 merge now or wait: merge #12"}
```

Claude's watcher prints the line and exits, Claude merges, and it starts the watcher again.

### Give a session work

```text
You:      tell parser to add retries to the fetch client, three attempts with backoff, and open a PR
Grok Bot: Sent to parser.
```

Grok Bot appends a `task:` line to the inbox. Claude picks it up like any reply, does the work, and pings `pr_ready` when the PR is up.

### Check on your sessions

```text
You: list sessions
```

```text
SESSION              WATCHER  UNREAD  WEBHOOK  CLAUDE  RULES             PROJECT
billing              yes      0       ok       open    ask               /Users/you/code/billing
parser               no       2       ok       open    merge-when-green  /Users/you/code/parser
docs-site            yes      0       ok       open    ask               /Users/you/code/docs-site
```

`parser` has two replies Claude hasn't read and no watcher, so Claude stopped listening. Grok Bot offers to reconnect it. You can run `~/.grokbot/status` yourself too. Right after a reply, `WATCHER` reads `no` for a moment while Claude restarts the watcher; that is normal.

### Remove a session

```text
You:      remove parser
Grok Bot: This deletes the routine "Claude · parser" and ~/.grokbot/parser.env,
          and archives the inbox. Go ahead?
You:      yes
Grok Bot: Told parser to stop, then removed it. Sessions now: billing, docs-site.
```

## Reference

### Files

| Path under `~/.grokbot` | Holds |
|---|---|
| `ping`, `watch`, `reply`, `status`, `bind`, `unbind` | The scripts in [`skill/scripts`](skill/scripts); `.ps1` twins from [`skill/scripts/windows`](skill/scripts/windows) on Windows |
| `src/grokbot-claude-inbox` | A clone of this repository, where the scripts are copied from |
| `<session>.env` | `WEBHOOK_URL` and `WEBHOOK_HEADER` for that session's routine, plus `PROJECT`, `RULES`, and `ROUTINE`; mode 600 |
| `<session>.standing-prompt.txt` | The filled standing prompt Claude was given |
| `inbox/<session>.jsonl` | Grok Bot's replies, one JSON line each, append-only |
| `inbox/<session>.seen` | How many lines Claude has read |
| `inbox/<session>.lock/` | Present while a watcher runs |
| `inbox/archive/` | Inboxes of removed sessions |

### Scripts

| Script | Who runs it | What it does |
|---|---|---|
| `ping <session> <need>` | Claude | Posts the message on stdin to the session's routine. Refuses a bad `need`, an empty message, or an env file whose header holds a URL. |
| `watch <session>` | Claude | Waits for the next unread inbox lines, prints them, and exits. Keeps its place in `.seen`; one watcher per inbox. |
| `reply <session> user\|relay` | Grok Bot | Appends one JSON line to the inbox. |
| `status [session]` | Grok Bot, or you | One row per session: watcher, unread replies, env file, open Claude session, rules, project. |
| `bind <session> [--dialog]` | Grok Bot | Writes the env file from two dialogs or from `KEY=VALUE` lines on stdin, creates the inbox, and sends a self-test ping. |
| `unbind <session> [--delete]` | Grok Bot | Stops the watcher, removes the session's files, and archives its inbox. |

The PowerShell versions take the same arguments; a message goes in as `-Message "<text>"` or on stdin.

### Inbox line

```json
{"session":"parser","from":"grokbot","by":"relay","ts":"2026-09-27T09:41:00Z","message":"re setup test: pong"}
```

`by` is `user` when Grok Bot passes on your words, and `relay` when it decided under the session's standing rules. A message that starts with `task:` is new work.

### Prompts

- [`skill/references/standing-prompt.md`](skill/references/standing-prompt.md) is what Claude receives. It lists when Claude pings and what each ping must contain.
- [`skill/references/routine-prompt.md`](skill/references/routine-prompt.md) is the instruction for each webhook routine, including the brief format and the standing rules.

## Security

- Webhook tokens live only in `~/.grokbot/<session>.env`. `bind` writes them from dialogs on your computer, so they never enter chat unless you are away and paste them there.
- `~/.grokbot` is mode 700. The `from` and `session` fields filter stray lines, but any process running as you can write an inbox, so the folder permissions are the real boundary.
- Claude gets allow rules for `ping` and `watch` only. `ping` accepts six `need` values and posts only to the URL in the session's env file.
- Keep secrets out of ping messages and replies. Both end up in chat history.

## Troubleshooting

Start with `~/.grokbot/status`, or ask Grok Bot to `list sessions`.

| Symptom | Fix |
|---|---|
| `WATCHER no` and unread replies for more than a few seconds | Claude stopped listening. Ask Grok Bot to reconnect the session. |
| `WATCHER no` right after a reply | Normal. The watcher exits on each reply and Claude restarts it within seconds. |
| A background session sits `blocked` | It waits for a person, on a permission prompt or a question. Run `claude attach <id>` and answer it. |
| `ping` failed with 401 or 404 | The env file holds the wrong token, or the routine was deleted. Ask Grok Bot to bind the session again. |
| `bind` says the header holds a URL, or the same value twice | The URL went into both dialogs. Paste the Authorization header into the second one. |
| Claude says a watcher is already running | Two Claude sessions share one inbox. Keep one. |
| Claude keeps asking for permission to ping | The allow rules are missing. Ask Grok Bot to run setup again. |

### Upgrading an older setup

Older sessions posted with a raw `curl` and carried the token in their prompt, or read a shared `webhooks.env`. Ask Grok Bot to `reconnect` each one. It installs the scripts, binds the session, and gives Claude the new standing prompt. Then remove the old `curl` rule from `~/.claude/settings.json`. Rotate any token that was ever pasted into a chat or an inbox.

## Testing

```sh
sh tests/smoke.sh            # the shell scripts
pwsh -File tests/smoke.ps1   # the PowerShell scripts; powershell -File tests\smoke.ps1 on Windows
```

Both suites run the scripts in a throwaway home folder against a local fake webhook. They never touch your real `~/.grokbot`. The Windows dialogs in `bind.ps1` need a Windows desktop and are not covered by the suite.

## License

MIT
