# grokbot-claude-inbox

Run Claude Code while you're away from your desk. Every Claude Code session on your computer reports to one Grok Bot agent. When a session needs you, you get a short brief on your phone, and your answer reaches the session within seconds. Claude never sits blocked on a question in a terminal nobody is watching.

- **One Grok Bot, many sessions.** Each session gets its own webhook routine and inbox, so conversations never cross.
- **Claude keeps working.** It asks through a ping, then carries on with anything that doesn't need the answer.
- **You decide how much Grok Bot decides.** Per session, it either brings you every decision, or also approves merges once CI is green and the review passes.

## How it works

```text
Claude Code ──ping──▶ Grok Bot routine "Claude · parser" ──brief──▶ your phone
     ▲                                                                  │
  Monitor ◀─── ~/.grokbot/inbox/parser.jsonl ◀──── reply ◀──────────────┘
```

1. Claude runs `~/.grokbot/ping parser decision` with its question. The script posts it to the session's own webhook routine.
2. The routine sends you a brief of at most five lines. You answer in the Grok Bot chat.
3. Grok Bot runs `~/.grokbot/reply parser user`, which appends one JSON line to the session's inbox.
4. Claude listens on its inbox with Claude Code's built-in Monitor tool. Each new line arrives as an event and wakes Claude with your answer.

The whole thing is two small scripts and two prompts. The Monitor command in the standing prompt keeps a read cursor in `parser.seen`, so re-arming it every 30 minutes never skips or replays a reply. Nothing types into your terminal.

## Requirements

- Claude Code, `git`, and `curl` 7.76 or newer. On Windows, Git for Windows, which Claude Code already needs; everything runs in Git Bash.
- A Grok Bot agent with webhook routines and local execution on that computer.
- Auto mode for sessions that run unattended. The Monitor command is a compound command, which no allow rule covers, so in the default permission mode Claude asks before each 30-minute re-arm.

Every ping starts one routine run, which counts against your Grok Bot usage.

## Install

In Grok Bot, say:

```text
Install this skill: https://github.com/hexuria/grokbot-claude-inbox
```

Then say `add session`. Grok Bot clones this repository onto your computer and copies the two scripts into `~/.grokbot`. It then asks before adding an allow rule for `ping` to Claude Code, creates the routine, and connects the session.

Grok Bot cannot read a routine's webhook URL or token, so it sends you two links to them. At your Mac, you paste each value into a dialog, and nothing passes through chat. Away from it, you paste both into the Grok Bot chat, which leaves the token in your chat history.

Grok Bot's local execution needs one decision from you. If it asks before each command, replies stall while you are away. With standing permission, it runs commands on your computer unattended.

## Commands

| Say | What happens |
|---|---|
| `add session` or `setup` | Binds a Claude session: routine, env file, inbox, and the standing prompt. |
| `list sessions` | Shows each session, whether Claude is listening, and unread replies. |
| `reconnect parser` | Gives Claude the standing prompt again after a restart or `/clear`. |
| `remove parser` or `cleanup` | Tells Claude to stop, deletes the routine, and archives the inbox. |

To answer a session, reply to its brief. To give it work, say something like `tell parser to add retries to the fetch client and open a PR`.

## Examples

### Bind a session that's already open

Grok Bot finds the running session with `claude agents --json` and never starts a second copy.

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
Grok Bot: Webhook self-test succeeded. Claude is already open in ~/code/parser,
          so paste this into that session: <standing prompt>
Grok Bot: parser is connected. Sessions now: parser, docs-site.
```

When nothing is running in the folder, Grok Bot offers to start Claude in the background instead, and to create the folder if it doesn't exist.

### Answer a decision from your phone

Claude hits a choice and pings instead of waiting:

```sh
~/.grokbot/ping parser decision <<'GROKBOT_END'
PR #12 (streaming tokenizer) is green: 214 tests pass.
Merge now, or wait for the fuzz run (about 40 min)?
Recommend: merge now. Default if no answer: wait for the fuzz run.
Reply "merge #12" or "wait for fuzz".
GROKBOT_END
```

Your phone shows:

```text
parser · decision
PR #12 (streaming tokenizer) is green. Merge now or wait ~40 min for fuzzing?
Recommend: merge now. Default: wait.
Reply "merge #12" or "wait for fuzz".
github.com/acme/parser/pull/12
```

You reply `merge #12`. Grok Bot appends this line, Claude's monitor delivers it, and Claude merges:

```json
{"session":"parser","from":"grokbot","by":"user","ts":"2026-09-27T09:41:00Z","message":"re PR #12 merge now or wait: merge #12"}
```

## Reference

| Path under `~/.grokbot` | Holds |
|---|---|
| `ping`, `reply` | The scripts in [`skill/scripts`](skill/scripts) |
| `<session>.env` | The routine's `WEBHOOK_URL` and `WEBHOOK_HEADER`, plus `PROJECT`, `RULES`, and `ROUTINE`; mode 600 |
| `<session>.standing-prompt.txt` | The standing prompt Claude was given |
| `inbox/<session>.jsonl` | Grok Bot's replies, one JSON line each, append-only |
| `inbox/<session>.seen` | How many lines Claude has read |

In an inbox line, `by` is `user` when Grok Bot passes on your words, and `relay` when it decided under the session's standing rules. A message that starts with `task:` is new work.

The prompts live in [`skill/references`](skill/references). The standing prompt is what Claude receives, including when to ping. The routine prompt is each routine's instruction, including the brief format and the standing rules.

## Security

- Webhook tokens live only in `~/.grokbot/<session>.env`. They reach chat only if you paste them there while away from your computer.
- `~/.grokbot` is mode 700. Any process running as you can write an inbox, so those folder permissions are the real boundary.
- Claude gets an allow rule for `ping` only. It accepts six `need` values and posts only to the URL in the session's env file.

## Troubleshooting

| Symptom | Fix |
|---|---|
| A session stopped answering | Ask Grok Bot to `list sessions`, then to reconnect any session that isn't listening. |
| A background session sits `blocked` | It waits for you on a prompt or a question. Run `claude attach <id>` and answer it. |
| `ping` failed with 401 or 404 | The token is wrong or the routine was deleted. Ask Grok Bot to redo the session's webhook values. |
| Claude asks for permission every 30 minutes | The session runs in the default permission mode. Switch it to auto mode. |

Sessions set up before this version posted with a raw `curl` and carried the token in their prompt. Ask Grok Bot to reconnect each one. Then remove the old `curl` rule from `~/.claude/settings.json`, and rotate any token that was ever pasted into a chat or an inbox.

## Testing

```sh
sh tests/smoke.sh
```

The test runs both scripts and the standing prompt's Monitor command in a throwaway home folder against a local fake webhook. It never touches your real `~/.grokbot`. It runs on macOS; nothing has been tested on Windows yet.

## License

MIT
