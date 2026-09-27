#!/bin/sh
# Smoke test for skill/scripts. Runs in a throwaway HOME against a local fake
# webhook; touches nothing in your real ~/.grokbot. Needs jq, curl, python3.
#
# Usage: sh tests/smoke.sh
set -u

repo=$(cd "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d)
export HOME="$tmp/home"
g="$HOME/.grokbot"
mkdir -p "$g/inbox" && cp "$repo"/skill/scripts/* "$g/"
pass=0 fail=0
ok()  { pass=$((pass + 1)); printf 'ok   %s\n' "$1"; }
bad() { fail=$((fail + 1)); printf 'FAIL %s\n' "$1"; }
check() { if eval "$2"; then ok "$1"; else bad "$1"; fi; }

# Fake webhook: records the last request, answers 500 on /fail.
cat > "$tmp/hook.py" <<'PY'
import http.server, sys, os
out = sys.argv[1]
class H(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        body = self.rfile.read(int(self.headers["Content-Length"]))
        open(os.path.join(out, "body"), "wb").write(body)
        open(os.path.join(out, "auth"), "w").write(self.headers.get("Authorization", ""))
        code = 500 if self.path.endswith("/fail") else 200
        self.send_response(code); self.end_headers()
        self.wfile.write(b'{"ok":%s}' % (b"false" if code == 500 else b"true"))
    def log_message(self, *a): pass
s = http.server.HTTPServer(("127.0.0.1", 0), H)
open(os.path.join(out, "port"), "w").write(str(s.server_port))
s.serve_forever()
PY
python3 "$tmp/hook.py" "$tmp" & hook=$!
trap 'kill $hook 2>/dev/null; wait $hook 2>/dev/null; pkill -f "$tmp/home" 2>/dev/null; rm -rf "$tmp"' EXIT
i=0; while [ ! -s "$tmp/port" ] && [ $i -lt 50 ]; do sleep 0.1; i=$((i + 1)); done
port=$(cat "$tmp/port")

# --- ping -------------------------------------------------------------------
printf "WEBHOOK_URL='http://127.0.0.1:%s/hook'\nWEBHOOK_HEADER='Authorization: Bearer test-token'\nPROJECT='/tmp/demo'\nRULES='ask'\n" "$port" > "$g/demo.env"

"$g/ping" demo decision </dev/null >/dev/null 2>&1;    check 'ping refuses an empty message'   '[ $? -eq 2 ]'
echo hi | "$g/ping" demo later >/dev/null 2>&1;         check 'ping refuses an unknown need'    '[ $? -eq 2 ]'
echo hi | "$g/ping" ../demo update >/dev/null 2>&1;    check 'ping refuses a non-kebab name'   '[ $? -eq 2 ]'
echo hi | "$g/ping" ghost update >/dev/null 2>&1;      check 'ping refuses an unbound session' '[ $? -eq 2 ]'
echo hi | "$g/ping" demo >/dev/null 2>&1;              check 'ping refuses a missing need'     '[ $? -eq 2 ]'

"$g/ping" demo pr_ready >/dev/null <<'GROKBOT_END'
PR #12 is ready: "quotes", $HOME, `backticks`
second line
GROKBOT_END
check 'ping posts to the webhook'              '[ $? -eq 0 ]'
check 'ping sends the Authorization header'    '[ "$(cat "$tmp/auth")" = "Bearer test-token" ]'
check 'ping sends session and need'            '[ "$(jq -r "[.session,.need]|join(\" \")" "$tmp/body")" = "demo pr_ready" ]'
expected=$(printf '%s\n%s' 'PR #12 is ready: "quotes", $HOME, `backticks`' 'second line')
check 'ping keeps the message byte for byte'   '[ "$(jq -r .message "$tmp/body")" = "$expected" ]'

"$g/ping" demo update >/dev/null <<'GROKBOT_END'
unicode ünïcødé 日本 🎉 and a tab	and back\slash
GROKBOT_END
check 'ping encodes unicode, tabs, and backslashes' '[ "$(jq -r .message "$tmp/body")" = "$(printf "unicode ünïcødé 日本 🎉 and a tab\tand back\\\\slash")" ]'

printf "WEBHOOK_URL='http://127.0.0.1:%s/fail'\nWEBHOOK_HEADER='Authorization: Bearer x'\n" "$port" > "$g/down.env"
echo hi | "$g/ping" down update >/dev/null 2>&1;       check 'ping fails loudly on a server error' '[ $? -ne 0 ]'

printf "WEBHOOK_URL='https://example.invalid/hook'\nWEBHOOK_HEADER='Authorization: Bearer https://example.invalid/hook'\n" > "$g/mixed.env"
err=$(echo hi | "$g/ping" mixed update 2>&1 >/dev/null); rc=$?
check 'ping refuses a header that holds the URL' '[ $rc -eq 2 ] && printf "%s" "$err" | grep -q "holds a URL"'
printf "WEBHOOK_URL='https://example.invalid/hook'\nWEBHOOK_HEADER='crsr_token_without_header_name'\n" > "$g/bare.env"
echo hi | "$g/ping" bare update >/dev/null 2>&1;       check 'ping refuses a header with no name'  '[ $? -eq 2 ]'
printf "WEBHOOK_URL='crsr_token_in_the_url_slot'\nWEBHOOK_HEADER='Authorization: Bearer x'\n" > "$g/swapped.env"
echo hi | "$g/ping" swapped update >/dev/null 2>&1;    check 'ping refuses a token in the URL slot' '[ $? -eq 2 ]'

# --- reply ------------------------------------------------------------------
echo hi | "$g/reply" demo user >/dev/null 2>&1;        check 'reply refuses an unbound session' '[ $? -eq 2 ]'
touch "$g/inbox/demo.jsonl"
echo hi | "$g/reply" demo boss >/dev/null 2>&1;        check 'reply refuses a bad sender'       '[ $? -eq 2 ]'
echo 're PR #12 merge: approved' | "$g/reply" demo user >/dev/null
check 'reply appends one JSON line'            '[ "$(wc -l < "$g/inbox/demo.jsonl" | tr -d " ")" = 1 ]'
check 'reply line has from, by, ts, session'   'jq -e "select(.from==\"grokbot\" and .by==\"user\" and .session==\"demo\" and (.ts|test(\"Z$\")))" "$g/inbox/demo.jsonl" >/dev/null'

# --- listener: the Monitor command from the standing prompt ---------------
cmd=$(sed -n 's/^   \(f="\$HOME\/\.grokbot\/inbox\/.*done\)$/\1/p' "$repo/skill/references/standing-prompt.md" | sed 's/<session>/demo/g')
check 'the standing prompt holds one listener command' '[ -n "$cmd" ] && [ "$(printf "%s\n" "$cmd" | wc -l | tr -d " ")" = 1 ]'
listen() { sh -c "$cmd" > "$tmp/listen.out" 2>&1 & }
stop_listener() {
  pids=$(ps -Ao pid=,command= | awk -v f="$g/inbox/demo.jsonl" '{ c = $2; sub(/.*\//, "", c) } c == "tail" && index($0, f) { print $1 }')
  [ -n "$pids" ] && kill $pids 2>/dev/null; sleep 0.5
}
wait_for() { i=0; while ! grep -q "$1" "$tmp/listen.out" 2>/dev/null && [ $i -lt 50 ]; do sleep 0.1; i=$((i + 1)); done; }

rm -f "$g/inbox/demo.seen"
listen; wait_for '#1:'
check 'the listener prints the unread line'     'grep -q "^grokbot inbox #1: {" "$tmp/listen.out"'
check 'the listener records its place'          '[ "$(cat "$g/inbox/demo.seen")" = 1 ]'
echo 'pong' | "$g/reply" demo relay >/dev/null; wait_for '#2:'
check 'a running listener prints a new reply'   'grep -q "^grokbot inbox #2: .*\"by\":\"relay\"" "$tmp/listen.out"'
check 'it keeps listening after a reply'        '[ -n "$(ps -Ao command | grep -F "$g/inbox/demo.jsonl" | grep -v grep)" ]'
stop_listener
echo 'sent while nobody listened' | "$g/reply" demo user >/dev/null
listen; wait_for '#3:'
check 'a re-armed listener catches up without replay' '[ "$(grep -c "^grokbot inbox" "$tmp/listen.out")" = 1 ] && grep -q "^grokbot inbox #3: " "$tmp/listen.out"'
stop_listener
echo 99 > "$g/inbox/demo.seen"
listen; sleep 1
echo 'after a runaway cursor' | "$g/reply" demo user >/dev/null; wait_for '#4:'
check 'a cursor past the end skips nothing new'  'grep -q "^grokbot inbox #4: .*runaway" "$tmp/listen.out" && [ "$(grep -c "^grokbot inbox" "$tmp/listen.out")" = 1 ]'

printf '\n%s passed, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
