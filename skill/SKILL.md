---
name: grokbot-claude-inbox
description: >-
  Relay Claude Code sessions to the user's phone: each session pings its own
  webhook routine, and answers go back through a file inbox. Use when the user
  wants to set up, add, list, reconnect, or remove a Claude Code session, and
  whenever the user answers a Claude session.
---

# Claude Code relay

You relay between the user and the Claude Code sessions on their Mac. A bound session never waits in its own chat. It pings you through its webhook routine, you brief the user on their phone, and the answer goes back into the session's inbox, where a watcher wakes Claude. One relay serves any number of sessions.

```text
Claude ──ping──▶ routine "Claude · <session>" ──brief──▶ user's phone
  ▲                                                           │
watch ◀── ~/.grokbot/inbox/<session>.jsonl ◀── reply ◀────────┘
```

## Files on the Mac

A session name is kebab-case and keys everything below.

| Path under `~/.grokbot` | Holds |
|---|---|
| `ping`, `watch`, `reply`, `status` | Helper scripts from this skill's [`scripts/`](scripts/) folder |
| `<session>.env` | The routine's `WEBHOOK_URL` and `WEBHOOK_HEADER`, mode 600 |
| `inbox/<session>.jsonl` | Your replies, one JSON line each, append-only |
| `inbox/<session>.seen` | How many inbox lines Claude has read |
| `inbox/<session>.lock/` | Present while a watcher runs |

`~/.grokbot` is mode 700. Webhook URLs and tokens live only in the env files: keep them out of chat, inbox lines, and anything you give Claude.

The **registry** is a memory entry with one line per bound session: `<session> · <project folder> · routine <id> · rules: ask | merge-when-green`. The disk is the source of truth. When memory and `~/.grokbot/inbox/` disagree, trust the disk and fix memory.

## Answer a session

Use this whenever the user replies to a brief, and whenever a standing rule lets you decide.

1. Pick the session. The brief the user answered names it. If several sessions have open questions and the reply fits more than one, ask which.
2. Append the answer:

   ```sh
   ~/.grokbot/reply <session> user <<'GROKBOT_END'
   re PR #12 merge: approved
   GROKBOT_END
   ```

   The second argument is `user` when you pass on the user's words, and `relay` when you decided under a standing rule. Start with `re <the question>:` so Claude can match the answer. The message ends at a line reading `GROKBOT_END`, so reword any such line.
3. Done when `reply` prints the line it wrote. `~/.grokbot/status <session>` shows `UNREAD 0` once Claude has read it.

## Add a session

Triggers: setup, add session, bind session. Steps 1–3 run once per Mac; skip each one already in place.

1. **Prerequisites.** Check for `jq` and `curl` 7.76 or newer. Check that Grok Bot's local execution on the Mac has standing permission. Without it, every reply waits for the user to approve a command, which stalls while they are away. If it is off, tell the user and let them choose.
2. **Scripts.** Copy `ping`, `watch`, `reply`, and `status` from this skill's `scripts/` folder to `~/.grokbot/`, replacing older copies. If the folder is missing, fetch them from `https://raw.githubusercontent.com/hexuria/grokbot-claude-inbox/main/skill/scripts/`. Then:

   ```sh
   mkdir -p ~/.grokbot/inbox && chmod 700 ~/.grokbot ~/.grokbot/inbox
   chmod 755 ~/.grokbot/ping ~/.grokbot/watch ~/.grokbot/reply ~/.grokbot/status
   ```

3. **Claude permissions.** Claude must run `ping` and `watch` without a permission prompt, because a prompt blocks an unattended session. This edits the user's Claude config, so confirm with a question widget first. Then merge these rules into `permissions.allow` in `~/.claude/settings.json`, with `<home>` as the user's home directory:

   ```json
   "Bash(~/.grokbot/ping:*)",  "Bash(<home>/.grokbot/ping:*)",
   "Bash(~/.grokbot/watch:*)", "Bash(<home>/.grokbot/watch:*)"
   ```

   A rule matches the command as typed, so both path forms are needed. Offer these rules only; bypass-permissions mode is the user's call, not yours to suggest.
4. **Project and name.** Ask for the project folder and a session name, suggesting the folder's name in kebab-case. If `~/.grokbot/inbox/<session>.jsonl` already exists, the session is bound: go to **Reconnect a session** instead.
5. **Standing rules.** Ask what you may decide for this session without the user:
   - `ask`, the default: bring every decision to the user.
   - `merge-when-green`: approve a merge when CI is green, the PR is mergeable, and the latest review approves it with no open findings.

   Logins, product decisions, spending, and anything irreversible always go to the user.
6. **Routine.** Create a webhook routine named `Claude · <session>`. Its instruction is [`references/routine-prompt.md`](references/routine-prompt.md), filled in.
7. **Env file and inbox.** Write the routine's webhook URL and full Authorization header straight to disk:

   ```sh
   umask 077
   cat > ~/.grokbot/<session>.env <<'GROKBOT_END'
   WEBHOOK_URL='https://api2.cursor.sh/automations/webhook/...'
   WEBHOOK_HEADER='Authorization: Bearer ...'
   GROKBOT_END
   touch ~/.grokbot/inbox/<session>.jsonl
   ```

   If the routine doesn't show you its token, send the user a deep link to the routine's webhook settings and ask them to write this file on the Mac.
8. **Registry.** Add the session's line now, so an interrupted setup can be resumed.
9. **Connect Claude.** Follow **Connect Claude** below.
10. **Test.** The standing prompt ends with Claude sending a `decision` ping that asks for `pong`, and the routine answers it. Setup is done when `~/.grokbot/status <session>` shows `WATCHER yes` and `UNREAD 0`. Confirm: "Bound `<session>`. Sessions now: …". If no ping arrives within a few minutes, see **Repair**.

## Connect Claude

A Claude session is bound by giving it the standing prompt from [`references/standing-prompt.md`](references/standing-prompt.md) once. First look for a session that is already running:

```sh
claude agents --json --all
```

Each entry has `name`, `cwd`, `kind`, and a state. `interactive` entries are open terminals. `background` entries have `state` `blocked`, `done`, `stopped`, or a running state. Match on `name`, or on `cwd` equal to the project folder, and ask which one when several match.

| What you find | What to do |
|---|---|
| An open interactive session | Start nothing. The user pastes the standing prompt into it. |
| A running or `blocked` background session | Start nothing. The user runs `claude attach <id>`, pastes the prompt, and leaves with ←. |
| A `stopped` or `done` background session the user wants back | Resume it with its history: `claude --bg --resume <sessionId> "<prompt>"` from the project folder. |
| Nothing | Ask whether to start it for them or whether they will open it and paste. |

Starting or resuming beside a live session creates a second Claude on the same inbox, and the two fight over it. To start a new one, pass the prompt through a quoted heredoc so the shell expands nothing:

```sh
cd <folder> && claude --bg -n <session> "$(cat <<'GROKBOT_END'
<standing prompt, filled in>
GROKBOT_END
)"
```

## List sessions

Run `~/.grokbot/status` and show it with each session's project and rules from the registry. Then point out:

- `WATCHER no` with `UNREAD` above 0: Claude is not listening. Offer **Reconnect a session**.
- `WEBHOOK missing`: pings from that session cannot arrive. Rewrite its env file (Add, step 7).
- A background session whose `claude agents --json` state is `blocked`: it waits on a prompt in its terminal. The user runs `claude attach <id>` to answer it.
- An inbox with no registry line, or a registry line with no inbox: fix memory to match the disk.

## Reconnect a session

Use this when Claude restarted, lost the standing prompt after `/clear` or a long compaction, or a different Claude session should take over the name. The routine, env file, and inbox stay as they are. Run **Connect Claude** again. The inbox remembers what Claude has read, so old replies are not replayed.

## Remove a session

Triggers: cleanup, remove session, unbind.

1. Ask which sessions to remove, as a multi-select of the registry plus "all". Confirm once, naming what goes: the routines, the env files, and the inboxes. Inboxes are archived unless the user asks to delete them.
2. For each session:
   1. If `status` shows `WATCHER yes`, tell Claude first, then wait up to a minute for `UNREAD 0`:

      ```sh
      ~/.grokbot/reply <session> relay <<'GROKBOT_END'
      Session unbound by the user. Stop the watcher, stop pinging, and say so in your chat.
      GROKBOT_END
      ```

   2. Delete the routine `Claude · <session>`.
   3. Remove the files:

      ```sh
      rm -f ~/.grokbot/<session>.env ~/.grokbot/inbox/<session>.seen
      mkdir -p ~/.grokbot/inbox/archive
      mv ~/.grokbot/inbox/<session>.jsonl ~/.grokbot/inbox/archive/<session>-$(date +%Y%m%d-%H%M%S).jsonl
      ```

   4. If Claude runs as a background session, offer `claude stop <id>`, which keeps its conversation. Interactive sessions stay open for the user to close.
   5. Remove the session's registry line.
3. Keep the scripts and allow rules, which every session shares. Remove them only when the user asks and nothing is bound.
4. Report what was removed and which sessions remain.

## Repair

| Symptom | Fix |
|---|---|
| A session has gone quiet | Run `~/.grokbot/ping <session> update <<< 'relay self-test'`. If it fails, rewrite the env file (Add, step 7). If it arrives, **Reconnect a session**. |
| `WATCHER no` with `UNREAD` above 0 | Claude stopped listening. **Reconnect a session**. |
| A background session is `blocked` | It waits on a prompt in its terminal. The user runs `claude attach <id>` and answers it. |
| The user reports `ping` failing with 401 or 404 | The routine was deleted or its token changed. Rewrite the env file (Add, step 7). |
| A ping's `session` doesn't match its routine | That session's env file points at the wrong routine. Rewrite it. |
| Claude reports a watcher already running | Two Claude sessions share one inbox. Keep one and tell the other to stop watching. |
| An older session pings with a raw `curl` and a token in its prompt, or reads a shared `webhooks.env` | Move it to this setup: Add steps 1–3 and 7, then **Reconnect a session**. Its old `curl` allow rule can then go. |
