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

# --- bind -------------------------------------------------------------------
"$g/bind" bound >/dev/null 2>&1 <<GROKBOT_END
WEBHOOK_URL='http://127.0.0.1:$port/hook'
WEBHOOK_HEADER="Authorization: Bearer test-token"
PROJECT=/tmp/it's here
RULES=merge-when-green
ROUTINE=claude-bound
GROKBOT_END
check 'bind writes the env file and pings'      '[ $? -eq 0 ] && [ -f "$g/bound.env" ] && [ -f "$g/inbox/bound.jsonl" ]'
check 'bind strips quotes and keeps apostrophes' '[ "$(. "$g/bound.env"; printf "%s|%s|%s|%s" "$WEBHOOK_URL" "$WEBHOOK_HEADER" "$PROJECT" "$ROUTINE")" = "http://127.0.0.1:'"$port"'/hook|Authorization: Bearer test-token|/tmp/it'"'"'s here|claude-bound" ]'
check 'bind makes the files private'            '[ "$(stat -f %Lp "$g/bound.env")" = 600 ] && [ "$(stat -f %Lp "$g/inbox/bound.jsonl")" = 600 ]'
check 'bind sends the self-test ping'           '[ "$(jq -r .message "$tmp/body")" = "relay self-test" ] && [ "$(jq -r .session "$tmp/body")" = bound ]'

printf 'WEBHOOK_URL=http://127.0.0.1:%s/hook\nWEBHOOK_HEADER=crsr_bare_token\n' "$port" | "$g/bind" bare2 >/dev/null 2>&1
check 'bind completes a bare token into a header' '[ "$(. "$g/bare2.env"; printf "%s" "$WEBHOOK_HEADER")" = "Authorization: Bearer crsr_bare_token" ]'
printf 'WEBHOOK_URL=http://127.0.0.1:%s/hook\nWEBHOOK_HEADER=Bearer crsr_x\n' "$port" | "$g/bind" bearer >/dev/null 2>&1
check 'bind completes a Bearer value into a header' '[ "$(. "$g/bearer.env"; printf "%s" "$WEBHOOK_HEADER")" = "Authorization: Bearer crsr_x" ]'

printf 'WEBHOOK_URL=https://x.invalid/h\nWEBHOOK_HEADER=https://x.invalid/h\n' | "$g/bind" same >/dev/null 2>&1
check 'bind refuses the same value twice'       '[ $? -eq 2 ] && [ ! -f "$g/same.env" ]'
printf 'WEBHOOK_URL=https://x.invalid/h\nWEBHOOK_HEADER=Authorization: Bearer x\nRULES=yolo\n' | "$g/bind" rules >/dev/null 2>&1
check 'bind refuses unknown rules'              '[ $? -eq 2 ]'
printf 'WEBHOOK_URL=https://x.invalid/h\nWEBHOOK_HEADER=Authorization: Bearer x\nPROJECT=relative/path\n' | "$g/bind" rel >/dev/null 2>&1
check 'bind refuses a relative project path'    '[ $? -eq 2 ]'
printf 'garbage line\n' | "$g/bind" junk >/dev/null 2>&1
check 'bind refuses a line that is not KEY=VALUE' '[ $? -eq 2 ]'
printf 'WEBHOOK_URL=http://127.0.0.1:%s/fail\nWEBHOOK_HEADER=Authorization: Bearer x\n' "$port" | "$g/bind" broken >/dev/null 2>&1
check 'bind exits 1 when the self-test ping fails' '[ $? -eq 1 ] && [ -f "$g/broken.env" ]'

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

# --- status -----------------------------------------------------------------
row=$("$g/status" demo | awk 'NR==2 {print $1, $2, $3, $4, $6, $7}')
check 'status sees the running listener'         '[ "$row" = "demo yes 0 ok ask /tmp/demo" ]'
stop_listener
echo 'one more' | "$g/reply" demo user >/dev/null
row=$("$g/status" demo | awk 'NR==2 {print $1, $2, $3, $4, $6, $7}')
check 'status shows listening, unread, webhook, rules, project' '[ "$row" = "demo no 1 ok ask /tmp/demo" ]'
check 'status filters to one session'          '[ "$("$g/status" demo | wc -l | tr -d " ")" = 2 ]'
check 'status lists every inbox without a filter' '[ "$("$g/status" | wc -l | tr -d " ")" = $(( $(ls "$g/inbox"/*.jsonl | wc -l) + 1 )) ]'

# --- unbind -----------------------------------------------------------------
"$g/unbind" nobody >/dev/null 2>&1;                    check 'unbind refuses an unbound session' '[ $? -eq 2 ]'
echo prompt > "$g/demo.standing-prompt.txt"
listen; wait_for '#5:'
out=$("$g/unbind" demo); rc=$?
sleep 0.5
check 'unbind archives the inbox and removes the files' '[ $rc -eq 0 ] && [ "$(ls "$g/inbox/archive"/demo-*.jsonl | wc -l | tr -d " ")" = 1 ] && [ ! -f "$g/inbox/demo.jsonl" ] && [ ! -f "$g/demo.env" ] && [ ! -f "$g/demo.standing-prompt.txt" ] && [ ! -f "$g/inbox/demo.seen" ]'
check 'unbind ends a running listener'         'printf "%s" "$out" | grep -q "stopped Claude" && [ -z "$(ps -Ao command | grep -F "$g/inbox/demo.jsonl" | grep -v grep)" ]'
"$g/unbind" bound --delete >/dev/null 2>&1;            check 'unbind --delete removes the inbox'  '[ $? -eq 0 ] && [ ! -f "$g/inbox/bound.jsonl" ] && [ -z "$(ls "$g/inbox/archive"/bound-*.jsonl 2>/dev/null)" ]'

printf '\n%s passed, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
