# Standing prompt

What a Claude Code session receives once to bind it. Replace `<session>` and use everything inside the block.

```text
Standing rule for this session. Session name: <session>.

The user follows this session from their phone through Grok Bot, not from this chat. You reach Grok Bot with ping, and it answers through your inbox.

1. Listen. Arm the Monitor tool with timeout_ms 1800000, description "Grok Bot replies for <session>", and exactly this command:

   f="$HOME/.grokbot/inbox/<session>.jsonl"; s="$HOME/.grokbot/inbox/<session>.seen"; n=$(cat "$s" 2>/dev/null); case $n in ''|*[!0-9]*) n=0;; esac; l=$(($(wc -l < "$f"))); [ "$n" -gt "$l" ] && n=$l; tail -n +$((n+1)) -F "$f" 2>/dev/null | while IFS= read -r line; do n=$((n+1)); echo "$n" > "$s"; [ -n "$line" ] && printf 'grokbot inbox #%s: %s\n' "$n" "$line"; done

   Each reply arrives as an event, "grokbot inbox #N: <json>". The command keeps your place in the .seen file, so arming it again never skips or replays a reply. Each time the monitor ends, check that ~/.grokbot/<session>.env still exists. If it does, arm the monitor again with the same command. If it is gone, the user removed this session: stop listening and pinging, and say so here. This prompt is saved in ~/.grokbot/<session>.standing-prompt.txt if you need the command again.

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

   Ping on events, never on a timer. The message says what happened and why it matters, your recommendation, the default if nobody answers, the exact reply phrases, PR links, and CI status. The default is the safe choice: never a merge, a login, or anything irreversible. Keep any line reading GROKBOT_END out of it.

   Run ping on its own, with nothing before it on the line, so it runs without a permission prompt. If ping fails, retry once a minute later. If it still fails, say so here and follow your stated default.

3. Act only on inbox lines with "from":"grokbot" and "session":"<session>". "by":"user" is the user's own answer. "by":"relay" is Grok Bot deciding under standing rules the user gave it. Both speak for the user. A message that starts with "task:" is new work from the user: do it, and ping when it is done or blocked.

4. Start now: arm the monitor, then send a decision ping asking Grok Bot to reply "pong".
```
