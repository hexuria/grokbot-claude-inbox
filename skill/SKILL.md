---
name: grokbot-claude-inbox
description: >-
  Relay Claude Code sessions to the user's phone: each session pings its own
  webhook routine, and answers go back through a file inbox. Use when the user
  says setup, add session, list sessions, reconnect, or cleanup, when they give
  a session work, and whenever they answer a question a Claude session asked.
---

# Claude Code relay

You relay between the user and the Claude Code sessions on their computer. A bound session never waits in its own chat. It pings you through its webhook routine, you brief the user on their phone, and the answer goes back into the session's inbox. Claude listens on the inbox with Claude Code's built-in Monitor tool, so each new line wakes it. One relay serves any number of sessions.

```text
Claude ──ping──▶ routine "Claude · <session>" ──brief──▶ user's phone
  ▲                                                           │
Monitor ◀── ~/.grokbot/inbox/<session>.jsonl ◀── reply ◀──────┘
```

You run on Grok Bot's box. `Shell` runs on the user's computer, where every file below lives. You read this skill's `references/` here; its `scripts/` get installed there.

**Windows.** Claude runs `ping` and its Monitor command through Git Bash, so the standing prompt is the same on both systems. Your own commands change shape: every `~/.grokbot/<name>` in this skill becomes `powershell -NoProfile -File $HOME\.grokbot\<name>.ps1` with the same arguments, and a message goes in as `-Message "<text>"` instead of a heredoc.

## Files on the computer

| Path under `~/.grokbot` | Holds |
|---|---|
| `ping`, `reply`, `status`, `bind`, `unbind` | The scripts from this skill's [`scripts/`](scripts/) folder, plus their `.ps1` twins from [`scripts/windows/`](scripts/windows/) on Windows |
| `src/grokbot-claude-inbox` | A clone of this repository, where the scripts are copied from |
| `<session>.env` | `WEBHOOK_URL`, `WEBHOOK_HEADER`, `PROJECT`, `RULES`, `ROUTINE`; mode 600 |
| `<session>.standing-prompt.txt` | The filled standing prompt Claude was given |
| `inbox/<session>.jsonl` | Your replies, one JSON line each, append-only |
| `inbox/<session>.seen` | How many inbox lines Claude has read; its Monitor command keeps it |
| `inbox/archive/` | Inboxes of removed sessions |

The env files are the registry: a session is bound when its env file and inbox exist. Webhook URLs and tokens live only in the env files: keep them out of chat, inbox lines, and anything you give Claude.

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

## Give a session work

Work reaches Claude the same way as an answer. Start the message with `task:`:

```sh
~/.grokbot/reply <session> user <<'GROKBOT_END'
task: <what to do, what done looks like, any limits>
GROKBOT_END
```

Claude does it and pings when it is done or blocked.

## Add a session

Triggers: setup, add session, bind session. Steps 1–3 run once per computer; skip each one already in place.

1. **Prerequisites.** On a Mac: `git`, `curl` 7.76 or newer, and `awk`, all present by default. On Windows: PowerShell 5.1 or newer, Git for Windows, and `curl`. Tell the user once: replies run as commands on their computer, so if Grok Bot's local execution asks before each command, replies stall while they are away. Standing permission is their choice.
2. **Scripts.** Clone this repository on the computer and copy the scripts out of the clone. Files arrive by `git` and `cp`; retyping their contents truncates them.

   ```sh
   mkdir -p ~/.grokbot/inbox && chmod 700 ~/.grokbot ~/.grokbot/inbox
   src=~/.grokbot/src/grokbot-claude-inbox
   if [ -d "$src/.git" ]; then git -C "$src" pull -q --ff-only; else git clone -q --depth 1 https://github.com/hexuria/grokbot-claude-inbox "$src"; fi
   cp "$src"/skill/scripts/ping "$src"/skill/scripts/reply "$src"/skill/scripts/status "$src"/skill/scripts/bind "$src"/skill/scripts/unbind ~/.grokbot/
   chmod 755 ~/.grokbot/ping ~/.grokbot/reply ~/.grokbot/status ~/.grokbot/bind ~/.grokbot/unbind
   for s in ping reply status bind unbind; do sh -n ~/.grokbot/$s || echo "BROKEN $s"; done
   ```

   Windows:

   ```powershell
   $g = "$HOME\.grokbot"; New-Item -ItemType Directory -Force "$g\inbox" | Out-Null
   $src = "$g\src\grokbot-claude-inbox"
   if (Test-Path "$src\.git") { git -C $src pull -q --ff-only } else { git clone -q --depth 1 https://github.com/hexuria/grokbot-claude-inbox $src }
   Copy-Item "$src\skill\scripts\ping" $g
   Copy-Item "$src\skill\scripts\windows\*.ps1" $g
   ```

3. **Claude permissions.** Claude must ping without a permission prompt, because a prompt blocks an unattended session. This edits the user's Claude config, so confirm with a question widget first. Then merge these rules into `permissions.allow` in `~/.claude/settings.json`, with `<home>` as the user's home directory (`/c/Users/<you>` under Git Bash on Windows):

   ```json
   "Bash(~/.grokbot/ping:*)", "Bash(<home>/.grokbot/ping:*)"
   ```

   A rule matches the command as typed, so both path forms are needed. The Monitor command that listens is a compound command, and no allow rule covers one. In the default permission mode Claude asks before each 30-minute re-arm, so tell the user that unattended sessions need auto mode. Offer these rules only; bypass-permissions mode is the user's call, not yours to suggest.
4. **Project and name.** Ask for the project folder as an absolute path. If it does not exist, ask with a question widget whether to create it or use another path. Then ask for the session name with a question widget that allows a custom answer, suggesting the folder's name in kebab-case. If `~/.grokbot/<session>.env` already exists, the session is bound: go to **Reconnect a session** instead.
5. **Standing rules.** Ask what you may decide for this session without the user. `ask`, the default, brings every decision to the user. `merge-when-green` also lets you approve a merge once you have confirmed CI, mergeability, and the review yourself. The exact wording is in the routine template. Logins, product decisions, spending, and anything irreversible always go to the user.
6. **Routine.** Create a webhook routine named `Claude · <session>`. Its instruction is [`references/routine-prompt.md`](references/routine-prompt.md), filled in. The result names the routine's folder, such as `claude-<session>`; that is its id.
7. **Bind.** You cannot read the routine's webhook URL or token; only the user can, from the routine's page. Send them both links:

   ```text
   grokbot://app/v1/sidebar?target=webhook-url&automation=<routine folder>
   grokbot://app/v1/sidebar?target=webhook-header&automation=<routine folder>
   ```

   Then get the two values onto the computer. When the user is at the computer, two dialogs open there and nothing passes through chat:

   ```sh
   PROJECT='<folder>' RULES='<rules>' ROUTINE='<routine folder>' ~/.grokbot/bind <session> --dialog
   ```

   When they are away from it, they paste both values in chat and you pass them on:

   ```sh
   ~/.grokbot/bind <session> <<'GROKBOT_END'
   WEBHOOK_URL=<pasted URL>
   WEBHOOK_HEADER=<pasted header>
   PROJECT=<folder>
   RULES=<rules>
   ROUTINE=<routine folder>
   GROKBOT_END
   ```

   Tell them the token now sits in chat history. Either way `bind` checks the values, writes the env file and the inbox, and sends a self-test ping. Continue only when it prints `bound`. A 401 means the header is wrong: send the links again and rerun `bind`. On Windows, set `$env:PROJECT`, `$env:RULES`, and `$env:ROUTINE` first and run `bind.ps1 <session> -Dialog`, or pipe the same lines in as a here-string.
8. **Standing prompt.** Fill [`references/standing-prompt.md`](references/standing-prompt.md) and save it, so it can be pasted or read later. It holds no secrets.

   ```sh
   cat > ~/.grokbot/<session>.standing-prompt.txt <<'GROKBOT_END'
   <filled standing prompt>
   GROKBOT_END
   ```

9. **Connect Claude.** Follow **Connect Claude** below.
10. **Test.** The standing prompt ends with Claude sending a `decision` ping that asks for `pong`, and the routine answers it. Setup is proven when `tail -1 ~/.grokbot/inbox/<session>.jsonl` is the pong line and `~/.grokbot/status <session>` shows `LISTENING yes` and `UNREAD 0`. Confirm: "Bound `<session>`. Sessions now: …". If nothing arrives within a few minutes, see **Repair**.

## Connect Claude

A Claude session is bound by giving it the standing prompt once. First look for a session that is already running:

```sh
claude agents --json --all
```

Each entry has `name`, `cwd`, `kind`, and a state. `interactive` entries are open terminals. `background` entries are `working`, `blocked`, `done`, or `stopped`; `blocked` means it is waiting for a person, on a permission prompt or a question. Match on `name`, or on `cwd` equal to the project folder, and ask which one when several match.

| What you find | What to do |
|---|---|
| An open interactive session | Start nothing. The user pastes the standing prompt into it. |
| A `working` or `blocked` background session | Start nothing. The user runs `claude attach <id>`, answers whatever it is waiting on, pastes the prompt, and leaves with ←. |
| A `stopped` or `done` background session the user wants back | Resume it with its history from the project folder: `claude --bg --resume <sessionId> "$(cat ~/.grokbot/<session>.standing-prompt.txt)"`. |
| Nothing | Ask with a question widget: start background Claude for them, or they paste the prompt themselves. |

Starting or resuming beside a live session creates a second Claude on the same inbox, and the two fight over it. To start a new one:

```sh
cd <folder> && claude --bg -n <session> "$(cat ~/.grokbot/<session>.standing-prompt.txt)"
```

On Windows: `Set-Location <folder>; claude --bg -n <session> (Get-Content -Raw "$HOME\.grokbot\<session>.standing-prompt.txt")`. The output names the session id, which the user opens with `claude attach <id>`.

## List sessions

Run `~/.grokbot/status` and show it. Then point out:

- `LISTENING no`: Claude's monitor is not running. Every 30 minutes it re-arms, so recheck after a few seconds; if it stays `no`, offer **Reconnect a session**.
- `WEBHOOK missing`: pings from that session cannot arrive. Rerun **Bind**.
- `CLAUDE -`: no Claude session is open under that name or project folder. Offer **Connect Claude**.
- A background session whose `claude agents --json` state is `blocked`: it waits for a person. The user runs `claude attach <id>` to see what it needs.

## Reconnect a session

Triggers: reconnect, rebind, resume a session. Use this when Claude restarted, lost the standing prompt after `/clear` or a long compaction, or a different Claude session should take over the name. The routine, env file, inbox, and saved standing prompt stay as they are. Run **Connect Claude** again. The inbox remembers what Claude has read, so old replies are not replayed.

## Remove a session

Triggers: cleanup, remove session, unbind.

1. Ask which sessions to remove, as a multi-select of the bound sessions plus "all". Confirm once, naming what goes: the routines, the env files, and the inboxes. Inboxes are archived unless the user asks to delete them.
2. For each session:
   1. If `status` shows `LISTENING yes`, tell Claude first, then wait up to a minute for `UNREAD 0`:

      ```sh
      ~/.grokbot/reply <session> relay <<'GROKBOT_END'
      Session unbound by the user. Stop listening, stop pinging, and say so in your chat.
      GROKBOT_END
      ```

   2. Delete the routine `Claude · <session>`.
   3. Run `~/.grokbot/unbind <session>`. It ends Claude's monitor if it is still running, removes the env file, the read cursor, and the saved prompt, and archives the inbox; `--delete` (`-Delete` on Windows) removes the inbox instead.
   4. If Claude runs as a background session, offer `claude stop <id>`, which keeps its conversation. Interactive sessions stay open for the user to close.
3. Keep the scripts and allow rules, which every session shares. Remove them only when the user asks and nothing is bound.
4. Report what was removed and which sessions remain.

## Repair

| Symptom | Fix |
|---|---|
| A session has gone quiet | Run `~/.grokbot/ping <session> update <<< 'relay self-test'`. If it fails, rerun **Bind**. If it arrives, **Reconnect a session**. |
| `LISTENING no` for more than a few seconds | Claude stopped listening. **Reconnect a session**. |
| Claude asks for permission every 30 minutes | The session runs in the default permission mode, and the Monitor command is a compound command no allow rule covers. The user switches that session to auto mode. |
| A background session is `blocked` | It waits for a person. The user runs `claude attach <id>` and answers it. |
| `ping` fails with 401 or 404 | The env file holds the wrong token, or the routine was deleted. Rerun **Bind**. |
| `bind` reports the header holds a URL, or the same value twice | The user pasted the URL into both dialogs. Send the two links again and rerun `bind`. |
| A ping's `session` doesn't match its routine | That session's env file points at the wrong routine. Rerun **Bind**. |
| Two Claude sessions listen on one inbox | Each gets every reply. Keep one and tell the other to stop listening. |
| An older session pings with a raw `curl` and a token in its prompt, or reads a shared `webhooks.env` | Move it to this setup: Add steps 1–3 and 7, then **Reconnect a session**. Its old `curl` allow rule can then go. |
