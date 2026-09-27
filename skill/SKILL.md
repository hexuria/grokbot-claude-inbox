---
name: grokbot-claude-inbox
description: >-
  use when the user says setup, add session, list sessions, cleanup, or
  grokbot-claude-inbox — bind one or many Claude Code sessions to this Grok Bot
  relay (webhook + inbox each), or tear them down
---
# grokbot-claude-inbox — Claude Code ↔ Grok Bot inbox relay (1:many)

Use when the user says `setup`, `bind session`, `add session`, `list sessions`, `cleanup`, `setup-claude-inbox`, or `grokbot-claude-inbox`.

One Grok Bot agent (the **Relay**) can babysit **many** Claude Code sessions. Each session has its own webhook routine + inbox + env. Drive the flow yourself.

**Words:**
- **Relay** = this Grok Bot agent
- **Session** = one Claude Code session (`$SESSION_NAME`)
- **Inbox** = `~/.grokbot/inbox/$SESSION_NAME.jsonl`
- **Ping** = Claude’s webhook POST
- **Reply** = inbox line Relay appends (prefix `Relay:`)

**Registry:** keep a list of bound sessions in agent memory, e.g.  
`Bound Claude sessions: name=… routine=… inbox=~/.grokbot/inbox/….jsonl env=~/.grokbot/….env`

---

## Commands

| User says | Do |
|-----------|----|
| `setup` / first run / no sessions yet | → **Add session** (below) |
| `add session` / `bind session` | → **Add session** |
| `list sessions` | → Show registry (name, routine folder, inbox path) |
| `cleanup` / `remove session` | → **Cleanup** (pick which, or all) |

Never hard-code a session name in this skill.

---

## Add session

1. **Name** — widget (`allowCustom: true`): `Claude session name?` (kebab-case). Reject if already in registry.

2. **Inbox** (user’s Mac):
   ```sh
   mkdir -p ~/.grokbot/inbox && chmod 700 ~/.grokbot ~/.grokbot/inbox
   touch ~/.grokbot/inbox/$SESSION_NAME.jsonl
   ```

3. **Webhook routine** on this agent:
   - name: `Claude · $SESSION_NAME`
   - trigger: webhook
   - prompt: Relay for Claude Code session `$SESSION_NAME` only. Short mobile brief every ping. Reply only by appending to `~/.grokbot/inbox/$SESSION_NAME.jsonl` with `from:"grokbot"`. Prefix `Relay:` when answering for the user. Away-mode defaults on `need=merge` only after Cursor Approve + CI green. Escalate login / product / irreversible. Never AskUser in Claude chat. Never drive terminal UI / System Events.
   - Save `$ROUTINE_FOLDER`.

4. **Credentials** — deep links + secret-request (never chat paste):
   - Webhook URL / Authorization for `$ROUTINE_FOLDER`
   - Write `~/.grokbot/$SESSION_NAME.env` (chmod 600)

5. **Allow-rule once (user-level)** — if not already done for any session:
   ```
   Bash(curl -sS -X POST "https://api2.cursor.sh/automations/webhook/*)
   ```
   Merge into `~/.claude/settings.json` or tell user `/permissions`. Widget confirm. Never suggest yolo/bypass. Skip re-confirm if memory says allow-rule already installed.

6. **Claude paste** — one message with `$SESSION_NAME` filled; URL/auth as pill placeholders unless they ask filled. Include Monitor one-liner. Optional: offer `claude --bg -n $SESSION_NAME` launch if they named a project cwd.

7. **Registry** — append session to memory. Confirm: “Bound `$SESSION_NAME`. Sessions now: …”

Repeat Add for each extra Claude session — same Relay agent.

---

## Cleanup session

1. Widget: which session(s)? (multiSelect from registry + “all”)

2. For each picked `$SESSION_NAME`:
   - Delete webhook routine `Claude · $SESSION_NAME` (folder from registry)
   - On Mac (ask confirm first — destructive):
     - remove `~/.grokbot/$SESSION_NAME.env`
     - archive or delete inbox: prefer `mv ~/.grokbot/inbox/$SESSION_NAME.jsonl ~/.grokbot/inbox/$SESSION_NAME.jsonl.done` (and `.seen` / `.lock` if present); only `rm` if user says delete
   - Drop from registry memory
   - If a background Claude id was saved, offer `claude stop <id>` / `claude rm <id>`

3. If registry empty and user wants: leave the user-level curl allow-rule in place (shared); only remove it if they explicitly ask.

4. Confirm what’s gone and what’s left.

---

## After setup (every webhook wake)

Match ping `session` to a bound session. Brief user. Append-only inbox reply. Merge only on `need=merge` after Approve + CI green. Escalate login / product / irreversible.

## Repair
- Unknown session on ping → tell user; offer Add or ignore
- Missing session mid-work → Add
- Bad webhook → re-do credentials for that session
- Curl blocked → allow-rule step
