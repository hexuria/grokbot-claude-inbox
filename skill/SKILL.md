---
name: grokbot-claude-inbox
description: >-
  Relay Claude Code sessions to the user's phone: each session pings its own
  webhook routine, and answers go back through a file inbox. Use when the user
  says setup, add session, list sessions, reconnect, or cleanup, and whenever
  the user answers a question a Claude session asked.
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
| `<session>.env` | `WEBHOOK_URL` and `WEBHOOK_HEADER` for the routine, plus `PROJECT`, `RULES`, and `ROUTINE`; mode 600 |
| `inbox/<session>.jsonl` | Your replies, one JSON line each, append-only |
| `inbox/<session>.seen` | How many inbox lines Claude has read |
| `inbox/<session>.lock/` | Present while a watcher runs |
| `inbox/archive/` | Inboxes of removed sessions |

The env files are the registry: a session is bound when its env file and inbox exist. `~/.grokbot` is mode 700. Webhook URLs and tokens live only in the env files: keep them out of chat, inbox lines, and anything you give Claude.

The prompts you hand out live in this skill's [`references/`](references/) folder. If that folder is missing, fetch them from `https://raw.githubusercontent.com/hexuria/grokbot-claude-inbox/main/skill/references/`.

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

1. **Prerequisites.** Check for `jq` and `curl` 7.76 or newer on the Mac. Tell the user once: replies run as commands on their Mac, so if Grok Bot's local execution asks before each command, replies stall while they are away. Standing permission is their choice.
2. **Scripts.** Install the four scripts from this skill's `scripts/` folder, replacing older copies:

   ```sh
   mkdir -p ~/.grokbot/inbox && chmod 700 ~/.grokbot ~/.grokbot/inbox
   cp <skill folder>/scripts/ping <skill folder>/scripts/watch <skill folder>/scripts/reply <skill folder>/scripts/status ~/.grokbot/
   chmod 755 ~/.grokbot/ping ~/.grokbot/watch ~/.grokbot/reply ~/.grokbot/status
   ```

   If the folder is missing, fetch each script from `https://raw.githubusercontent.com/hexuria/grokbot-claude-inbox/main/skill/scripts/<name>` in place of the `cp`.
3. **Claude permissions.** Claude must run `ping` and `watch` without a permission prompt, because a prompt blocks an unattended session. This edits the user's Claude config, so confirm with a question widget first. Then merge these rules into `permissions.allow` in `~/.claude/settings.json`, with `<home>` as the user's home directory:

   ```json
   "Bash(~/.grokbot/ping:*)",  "Bash(<home>/.grokbot/ping:*)",
   "Bash(~/.grokbot/watch:*)", "Bash(<home>/.grokbot/watch:*)"
   ```

   A rule matches the command as typed, so both path forms are needed. Offer these rules only; bypass-permissions mode is the user's call, not yours to suggest.
4. **Project and name.** Ask for the project folder as an absolute path. Then ask for the session name with a question widget that allows a custom answer, suggesting the folder's name in kebab-case. If `~/.grokbot/<session>.env` already exists, the session is bound: go to **Reconnect a session** instead.
5. **Standing rules.** Ask what you may decide for this session without the user. `ask`, the default, brings every decision to the user. `merge-when-green` also lets you approve a merge once you have confirmed CI, mergeability, and the review yourself. The exact wording is in the routine template. Logins, product decisions, spending, and anything irreversible always go to the user.
6. **Routine.** Create a webhook routine named `Claude · <session>`. Its instruction is [`references/routine-prompt.md`](references/routine-prompt.md), filled in. Note its id.
7. **Env file and inbox.** Get the routine's webhook URL and full Authorization header without putting them in chat: read them from the routine if it shows them to you, or send the user a deep link to the routine's webhook settings together with a secret request. Then write:

   ```sh
   umask 077
   cat > ~/.grokbot/<session>.env <<'GROKBOT_END'
   WEBHOOK_URL='https://api2.cursor.sh/automations/webhook/...'
   WEBHOOK_HEADER='Authorization: Bearer ...'
   PROJECT='<absolute project folder>'
   RULES='ask'
   ROUTINE='<routine id>'
   GROKBOT_END
   touch ~/.grokbot/inbox/<session>.jsonl
   chmod 600 ~/.grokbot/<session>.env ~/.grokbot/inbox/<session>.jsonl
   ```

   The header carries the routine's bearer token, a separate value from the URL. If neither path gives you the values, hand the user this block to run on the Mac themselves. Then prove the webhook before going on:

   ```sh
   ~/.grokbot/ping <session> update <<< 'relay self-test'
   ```

   It must exit 0. `ping` refuses a header that holds the URL, and a 401 means the token is wrong. Fix the file before step 8.
8. **Connect Claude.** Follow **Connect Claude** below.
9. **Test.** The standing prompt ends with Claude sending a `decision` ping that asks for `pong`, and the routine answers it. Setup is done when `tail -1 ~/.grokbot/inbox/<session>.jsonl` is that pong line and `~/.grokbot/status <session>` shows `WATCHER yes` and `UNREAD 0`. Confirm: "Bound `<session>`. Sessions now: …". If nothing arrives within a few minutes, see **Repair**.

## Connect Claude

A Claude session is bound by giving it the standing prompt from [`references/standing-prompt.md`](references/standing-prompt.md) once. First look for a session that is already running:

```sh
claude agents --json --all
```

Each entry has `name`, `cwd`, `kind`, and a state. `interactive` entries are open terminals. `background` entries have `state` `blocked`, `done`, `stopped`, or a running state; `blocked` means it is waiting for a person, on a permission prompt or a question. Match on `name`, or on `cwd` equal to the project folder, and ask which one when several match.

| What you find | What to do |
|---|---|
| An open interactive session | Start nothing. The user pastes the standing prompt into it. |
| A running or `blocked` background session | Start nothing. The user runs `claude attach <id>`, answers whatever it is waiting on, pastes the prompt, and leaves with ←. |
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

Run `~/.grokbot/status` and show it. Then point out:

- `WATCHER no` with `UNREAD` above 0: Claude is not listening. Offer **Reconnect a session**.
- `WEBHOOK missing`: pings from that session cannot arrive. Rewrite its env file (Add, step 7).
- `CLAUDE -`: no Claude session is open under that name or project folder. Offer **Connect Claude**.
- A background session whose `claude agents --json` state is `blocked`: it waits for a person. The user runs `claude attach <id>` to see what it needs.

## Reconnect a session

Triggers: reconnect, rebind, resume a session. Use this when Claude restarted, lost the standing prompt after `/clear` or a long compaction, or a different Claude session should take over the name. The routine, env file, and inbox stay as they are. Run **Connect Claude** again. The inbox remembers what Claude has read, so old replies are not replayed.

## Remove a session

Triggers: cleanup, remove session, unbind.

1. Ask which sessions to remove, as a multi-select of the bound sessions plus "all". Confirm once, naming what goes: the routines, the env files, and the inboxes. Inboxes are archived unless the user asks to delete them.
2. For each session:
   1. If `status` shows `WATCHER yes`, tell Claude first, then wait up to a minute for `UNREAD 0`:

      ```sh
      ~/.grokbot/reply <session> relay <<'GROKBOT_END'
      Session unbound by the user. Stop the watcher, stop pinging, and say so in your chat.
      GROKBOT_END
      ```

   2. Delete the routine `Claude · <session>`.
   3. Remove the files. The first line stops a watcher that is still running:

      ```sh
      kill "$(cat ~/.grokbot/inbox/<session>.lock/pid 2>/dev/null)" 2>/dev/null
      rm -f ~/.grokbot/<session>.env ~/.grokbot/inbox/<session>.seen
      rm -rf ~/.grokbot/inbox/<session>.lock
      mkdir -p ~/.grokbot/inbox/archive
      mv ~/.grokbot/inbox/<session>.jsonl ~/.grokbot/inbox/archive/<session>-$(date +%Y%m%d-%H%M%S).jsonl
      ```

   4. If Claude runs as a background session, offer `claude stop <id>`, which keeps its conversation. Interactive sessions stay open for the user to close.
3. Keep the scripts and allow rules, which every session shares. Remove them only when the user asks and nothing is bound.
4. Report what was removed and which sessions remain.

## Repair

| Symptom | Fix |
|---|---|
| A session has gone quiet | Run `~/.grokbot/ping <session> update <<< 'relay self-test'`. If it fails, rewrite the env file (Add, step 7). If it arrives, **Reconnect a session**. |
| `WATCHER no` with `UNREAD` above 0 | Claude stopped listening. **Reconnect a session**. |
| A background session is `blocked` | It waits for a person. The user runs `claude attach <id>` and answers it. |
| The user reports `ping` failing with 401 or 404 | The env file holds the wrong token, or the routine was deleted. Rewrite the env file (Add, step 7). |
| A ping's `session` doesn't match its routine | That session's env file points at the wrong routine. Rewrite it. |
| Claude reports a watcher already running | Two Claude sessions share one inbox. Keep one and tell the other to stop watching. |
| An older session pings with a raw `curl` and a token in its prompt, or reads a shared `webhooks.env` | Move it to this setup: Add steps 1–3 and 7, then **Reconnect a session**. Its old `curl` allow rule can then go. |
