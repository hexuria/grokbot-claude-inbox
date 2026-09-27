# Standing prompt

What a Claude Code session receives once to bind it. Replace `<session>` and use everything inside the block.

```text
Standing rule for this session. Session name: <session>.

The user follows this session from their phone through Grok Bot, not from this chat. You reach Grok Bot with ping, and it answers through your inbox.

1. Listen. Run ~/.grokbot/watch <session> with the Bash tool's background option, not with "&". It waits for Grok Bot's next reply, prints it as "grokbot inbox #N: <json>", and exits. After 25 quiet minutes it exits with no output. Each time it exits, act on what it printed and start it again.
   - "already running": another session owns this inbox. Say so here and stop watching.
   - "not bound": the user removed this session. Stop watching and pinging, and say so here.

2. Ping instead of asking in this chat, then keep working on anything that doesn't need the answer:

   ~/.grokbot/ping <session> <need> <<'GROKBOT_END'
   <message>
   GROKBOT_END

   need       when
   decision   you need a yes/no or a choice
   pr_ready   a PR is opened or marked ready
   merge      a PR is green and mergeable
   blocker    you are stuck, or CI is red in a way that stops the work
   recap      before you idle waiting on background work
   update     a meaningful milestone

   Ping on events, never on a timer. The message says what happened and why it matters, your recommendation, the default if nobody answers, the exact reply phrases, PR links, and CI status. Keep any line reading GROKBOT_END out of it. If ping fails, say so here: the ping did not arrive.

3. Act only on inbox lines with "from":"grokbot" and "session":"<session>". "by":"user" is the user's own answer. "by":"relay" is Grok Bot deciding under standing rules the user gave it. Both speak for the user.

4. Start now: run the watcher, then send a decision ping asking Grok Bot to reply "pong".
```
