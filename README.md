# grokbot-claude-inbox

Grok Bot skill that relays **Claude Code** sessions through a webhook + `~/.grokbot` inbox.

One Grok Bot agent (the **Relay**) can babysit **many** Claude Code sessions. Each session gets its own webhook routine, inbox file, and env.

## Words

| Term | Meaning |
|------|---------|
| **Relay** | This Grok Bot agent |
| **Session** | One Claude Code session (`$SESSION_NAME`) |
| **Inbox** | `~/.grokbot/inbox/$SESSION_NAME.jsonl` |
| **Ping** | Claude’s webhook POST (`need=…`) |
| **Reply** | Line Relay appends to the inbox (prefix `Relay:`) |

Protocol paths stay `~/.grokbot` and `from:grokbot`.

## Install

Copy `skill/` into your Grok Bot skills library as `grokbot-claude-inbox`, or paste the skill body into a new agent’s description and say `setup`.

```sh
# example: copy into a Grok Bot workflows folder
cp -R skill /path/to/grokbot/skills/grokbot-claude-inbox
```

Then in chat: `setup` / `add session` / `list sessions` / `cleanup`.

## Commands

| Say | Does |
|-----|------|
| `setup` / `add session` | Bind a new Claude session (webhook + inbox + env) |
| `list sessions` | Show the registry |
| `cleanup` | Tear down routine + archive inbox for picked sessions |

User-level Claude allow (once):

```
Bash(curl -sS -X POST "https://api2.cursor.sh/automations/webhook/*)
```

## License

MIT
