---
name: grokbot-claude-inbox
description: >-
  Relay Claude Code sessions to the user's phone: each session pings its own
  webhook routine, and answers go back through a file inbox. Use when the user
  says setup, add session, list sessions, reconnect, or cleanup, when they give
  a session work, and whenever they answer a question a Claude session asked.
---

# Claude Code relay

You relay between the user and the Claude Code sessions on their computer. A bound session never waits in its own chat. It pings you through its webhook routine, you brief the user on their phone, and the answer goes back into the session's inbox. Claude listens on the inbox with Claude Code's Monitor tool, so each new line wakes it. One relay serves any number of sessions.

```text
Claude ──ping──▶ routine "Claude · <session>" ──brief──▶ user's phone
  ▲                                                           │
Monitor ◀── ~/.grokbot/inbox/<session>.jsonl ◀── reply ◀──────┘
```

You run on Grok Bot's box. `Shell` runs on the user's computer, where every file below lives. On Windows, run every command in this skill in Git Bash, which Claude Code on Windows already requires, and keep LF line endings in anything you pass it.

## Files on the computer

| Path under `~/.grokbot` | Holds |
|---|---|
| `ping`, `reply` | The two scripts from this skill's [`scripts/`](scripts/) folder |
| `src/grokbot-claude-inbox` | A clone of this repository |
| `<session>.env` | `WEBHOOK_URL`, `WEBHOOK_HEADER`, `PROJECT`, `RULES`, `ROUTINE`; mode 600 |
| `<session>.standing-prompt.txt` | The standing prompt Claude was given |
| `inbox/<session>.jsonl` | Your replies, one JSON line each, append-only |
| `inbox/<session>.seen` | How many inbox lines Claude has read |

The env files are the registry: a session is bound when its env file and inbox exist. Webhook URLs and tokens live only in the env files: keep them out of chat, inbox lines, and anything you give Claude.

## Answer a session

Use this whenever the user replies to a brief or gives a session work, and whenever a standing rule lets you decide.

```sh
~/.grokbot/reply <session> user <<'GROKBOT_END'
re PR #12 merge: approved
GROKBOT_END
```

- The second argument is `user` when you pass on the user's words, and `relay` when you decided under a standing rule.
- Start an answer with `re <the question>:` so Claude can match it. Start new work with `task:`.
- If several sessions have open questions and the reply fits more than one, ask which.
- The message ends at a line reading `GROKBOT_END`, so reword any such line.

## Add a session

Triggers: setup, add session, bind session. Steps 1–3 run once per computer; skip each one already in place.

1. **Prerequisites.** Check for `git` and `curl` 7.76 or newer, plus Git for Windows on Windows. Tell the user once: replies run as commands on their computer, so if Grok Bot asks before each command, replies stall while they are away. Standing permission is their choice.
2. **Scripts.** Copy them out of a clone, because retyped files arrive truncated:

   ```sh
   mkdir -p ~/.grokbot/inbox && chmod 700 ~/.grokbot ~/.grokbot/inbox
   src=~/.grokbot/src/grokbot-claude-inbox
   if [ -d "$src/.git" ]; then git -C "$src" pull -q --ff-only; else git clone -q --depth 1 https://github.com/hexuria/grokbot-claude-inbox "$src"; fi
   cp "$src/skill/scripts/ping" "$src/skill/scripts/reply" ~/.grokbot/ && chmod 755 ~/.grokbot/ping ~/.grokbot/reply
   sh -n ~/.grokbot/ping && sh -n ~/.grokbot/reply && echo scripts ok
   ```

3. **Claude permissions.** This edits the user's Claude config, so confirm with a question widget first. Then merge these rules into `permissions.allow` in `~/.claude/settings.json`, with `<home>` as the user's home directory (`/c/Users/<you>` on Windows):

   ```json
   "Bash(~/.grokbot/ping:*)", "Bash(<home>/.grokbot/ping:*)"
   ```

   A rule matches the command as typed, so both path forms are needed. Claude's Monitor command is a compound command, which no rule covers, so in the default permission mode Claude asks before each 30-minute re-arm. Tell the user that unattended sessions need auto mode. Offer these rules only; bypass-permissions mode is the user's call.
4. **Project and name.** Ask for the project folder as an absolute path, and if it does not exist, ask whether to create it. Then ask for a session name with a question widget that allows a custom answer, suggesting the folder's name in kebab-case. If `~/.grokbot/<session>.env` already exists, go to **Reconnect a session** instead.
5. **Standing rules.** Ask what you may decide without the user: `ask`, the default, or `merge-when-green`. The exact wording is in the routine template. Logins, product decisions, spending, and anything irreversible always go to the user.
6. **Routine.** Create a webhook routine named `Claude · <session>` whose instruction is [`references/routine-prompt.md`](references/routine-prompt.md), filled in. The result names its folder, such as `claude-<session>`.
7. **Webhook values.** You cannot read the routine's webhook URL or token; only the user can. Send them both links:

   ```text
   grokbot://app/v1/sidebar?target=webhook-url&automation=<routine folder>
   grokbot://app/v1/sidebar?target=webhook-header&automation=<routine folder>
   ```

   If they are at their Mac, two dialogs collect the values there and nothing passes through chat. Otherwise, including on Windows, they paste both into chat, and you tell them the token now sits in chat history. Run this as one command:

   ```sh
   umask 077
   url=$(osascript -e 'text returned of (display dialog "<session>: paste the webhook URL" default answer "" with title "grokbot-claude-inbox")')    # or url='<pasted URL>'
   header=$(osascript -e 'text returned of (display dialog "<session>: paste the full Authorization header" default answer "" with hidden answer with title "grokbot-claude-inbox")')    # or header='<pasted header>'
   printf "WEBHOOK_URL='%s'\nWEBHOOK_HEADER='%s'\nPROJECT='%s'\nRULES='%s'\nROUTINE='%s'\n" "$url" "$header" '<folder>' '<rules>' '<routine folder>' > ~/.grokbot/<session>.env
   touch ~/.grokbot/inbox/<session>.jsonl
   ~/.grokbot/ping <session> update <<< 'relay self-test'
   ```

   Continue only when the ping succeeds. `ping` refuses a header that holds the URL or doesn't look like `Authorization: Bearer <token>`. A 401 means the token is wrong, so send the links again.
8. **Standing prompt.** Fill [`references/standing-prompt.md`](references/standing-prompt.md) and save it as `~/.grokbot/<session>.standing-prompt.txt`. It holds no secrets.
9. **Connect Claude.** Follow **Connect Claude** below.
10. **Test.** The standing prompt ends with Claude sending a `decision` ping that asks for `pong`, and the routine answers it. Setup is proven when the pong is the inbox's last line and `.seen` has caught up to the line count. Confirm: "Bound `<session>`. Sessions now: …".

## Connect Claude

A Claude session is bound by giving it the standing prompt once. First look for one that is already running with `claude agents --json --all`. Match on `name`, or on `cwd` equal to the project folder, and ask which one when several match.

| What you find | What to do |
|---|---|
| An open interactive session | Start nothing. The user pastes the standing prompt into it. |
| A `working` or `blocked` background session | Start nothing. The user runs `claude attach <id>`, answers whatever it is waiting on, pastes the prompt, and leaves with ←. |
| A `stopped` or `done` background session the user wants back | From the project folder: `claude --bg --resume <sessionId> "$(cat ~/.grokbot/<session>.standing-prompt.txt)"` |
| Nothing | Ask whether to start it for them or whether they will paste the prompt themselves. To start it: `cd <folder> && claude --bg -n <session> "$(cat ~/.grokbot/<session>.standing-prompt.txt)"` |

Starting or resuming beside a live session creates a second Claude on the same inbox. `claude attach <id>` opens a background session for the user.

## List sessions

For each `~/.grokbot/inbox/<session>.jsonl`, report:

- **Listening:** whether `ps -Ao command` shows a `tail` on that inbox. Claude re-arms every 30 minutes, so recheck a `no` after a few seconds, then offer **Reconnect a session**.
- **Unread:** the inbox's line count minus the number in its `.seen` file.
- **Project and rules:** from the env file. A missing env file means pings cannot arrive.
- **Claude:** whether `claude agents --json` shows a session with that name or folder. `blocked` means it waits for a person, who runs `claude attach <id>`.

## Reconnect a session

Triggers: reconnect, rebind, resume a session. Use this when Claude restarted, lost the standing prompt after `/clear` or a long compaction, or a different Claude session should take over the name. The routine, env file, inbox, and saved prompt stay. Run **Connect Claude** again. The `.seen` file keeps Claude's place, so old replies are not replayed.

## Remove a session

Triggers: cleanup, remove session, unbind.

1. Ask which sessions to remove, as a multi-select plus "all". Confirm once that this deletes the routines and env files and archives the inboxes.
2. For each session, tell Claude, wait up to a minute for `.seen` to catch up, delete the routine `Claude · <session>`, and remove the files:

   ```sh
   ~/.grokbot/reply <session> relay <<'GROKBOT_END'
   Session unbound by the user. Stop listening, stop pinging, and say so in your chat.
   GROKBOT_END
   ```

   ```sh
   rm -f ~/.grokbot/<session>.env ~/.grokbot/<session>.standing-prompt.txt ~/.grokbot/inbox/<session>.seen
   mkdir -p ~/.grokbot/inbox/archive
   mv ~/.grokbot/inbox/<session>.jsonl ~/.grokbot/inbox/archive/<session>-$(date +%Y%m%d-%H%M%S).jsonl
   ```

   If Claude missed the message, its monitor still stops: when it next ends, Claude finds the env file gone. For a background session, offer `claude stop <id>`.
3. Keep the scripts and the allow rule, which every session shares.
4. Report what was removed and which sessions remain.

## Repair

| Symptom | Fix |
|---|---|
| A session has gone quiet | Run `~/.grokbot/ping <session> update <<< 'relay self-test'`. If it fails, redo Add step 7. If it arrives, **Reconnect a session**. |
| Not listening for more than a few seconds | **Reconnect a session**. |
| A background session is `blocked` | It waits for a person. The user runs `claude attach <id>` and answers it. |
| `ping` fails with 401 or 404 | The token is wrong or the routine was deleted. Redo Add step 7. |
| A ping's `session` doesn't match its routine | That session's env file points at the wrong routine. Redo Add step 7 for it. |
| Claude asks for permission every 30 minutes | The session runs in the default permission mode. The user switches it to auto mode. |
| An older session pings with a raw `curl` and a token in its prompt, or reads a shared `webhooks.env` | Run Add steps 1–3 and 7, then **Reconnect a session**. Its old `curl` allow rule can then go. |
