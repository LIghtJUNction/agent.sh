#!/usr/bin/env bash
set -euo pipefail

ROOT=$(mktemp -d)
BIN=$(cd "$(dirname "$0")" && pwd)/agent.sh
FAKE_CTX="$ROOT/ctx"
LOG="$ROOT/ctx.log"

cleanup(){ rm -rf "$ROOT"; }
trap cleanup EXIT

assert_contains(){ case "$1" in *"$2"*) ;; *) printf 'missing %s in %s\n' "$2" "$1" >&2; exit 1 ;; esac; }
assert_not_contains(){ case "$1" in *"$2"*) printf 'unexpected %s in %s\n' "$2" "$1" >&2; exit 1 ;; *) ;; esac; }
last_call(){ tail -n 1 "$LOG"; }

cat >"$FAKE_CTX" <<'EOF_CTX'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"$CTX_FAKE_LOG"
case "$*" in
  "agent send coder hello socket") printf 'sent\n' ;;
  "agent send coder --session focus use focus") printf 'sent focus\n' ;;
  "agent send coder --raw raw") printf '{"type":"delta","text":"raw-ok"}\n' ;;
  "agent repl coder") printf 'repl\n' ;;
  "agent repl coder --session focus") printf 'repl focus\n' ;;
  "agent repl coder --raw") printf 'repl raw\n' ;;
  "agent resume coder") printf 'resumed\n' ;;
  "agent history coder") printf '{"role":"user","content":"hello"}\n' ;;
  "agent output coder") printf '# latest\nok\n' ;;
  "agent pack coder") printf '# pack\nfacts\n' ;;
  "agent tools coder") printf 'fs.read\nproject.test\n' ;;
  "agent children coder") printf 'rev-1\tdone\n' ;;
  "agent cancel coder run-1") printf 'cancelled\n' ;;
  "agent status coder") printf 'agent=coder\nsession=default\n' ;;
  "agent attach coder")
    if [[ -f "$CTX_FAKE_ATTACH_OK" ]]; then
      printf 'tsh>\n'
      exit 0
    fi
    printf 'ctx: terminal is not running\nrun: ctx agent start coder --session default\n' >&2
    exit 69
    ;;
  "agent start coder")
    printf 'started\n'
    : >"$CTX_FAKE_ATTACH_OK"
    ;;
  *) printf 'unexpected ctx args: %s\n' "$*" >&2; exit 64 ;;
esac
EOF_CTX
chmod +x "$FAKE_CTX"

bash -n "$BIN"

export CTX_BIN="$FAKE_CTX"
export CTX_FAKE_LOG="$LOG"
export CTX_FAKE_ATTACH_OK="$ROOT/attach.ok"
: >"$LOG"

out=$("$BIN" coder "hello socket")
assert_contains "$out" 'sent'
assert_contains "$(last_call)" 'agent send coder hello socket'

out=$("$BIN" --session focus coder "use focus")
assert_contains "$out" 'sent focus'
assert_contains "$(last_call)" 'agent send coder --session focus use focus'

out=$(printf '/exit\n' | "$BIN" coder)
assert_contains "$out" 'repl'
assert_contains "$(last_call)" 'agent repl coder'
assert_not_contains "$(cat "$LOG")" 'agent attach coder'

out=$(printf '/exit\n' | "$BIN" --session focus coder)
assert_contains "$out" 'repl focus'
assert_contains "$(last_call)" 'agent repl coder --session focus'

out=$(printf '/exit\n' | "$BIN" --chat coder)
assert_contains "$out" 'repl'
assert_contains "$(last_call)" 'agent repl coder'

out=$("$BIN" --resume coder)
assert_contains "$out" 'resumed'
assert_contains "$(last_call)" 'agent resume coder'

out=$("$BIN" --history coder)
assert_contains "$out" '"role":"user"'
assert_contains "$(last_call)" 'agent history coder'

out=$("$BIN" --output coder)
assert_contains "$out" '# latest'
assert_contains "$(last_call)" 'agent output coder'

out=$("$BIN" --pack coder)
assert_contains "$out" '# pack'
assert_contains "$(last_call)" 'agent pack coder'

out=$("$BIN" --tools coder)
assert_contains "$out" 'fs.read'
assert_contains "$out" 'project.test'
assert_contains "$(last_call)" 'agent tools coder'

out=$("$BIN" --children coder)
assert_contains "$out" 'rev-1'
assert_contains "$(last_call)" 'agent children coder'

out=$("$BIN" --cancel coder run-1)
assert_contains "$out" 'cancelled'
assert_contains "$(last_call)" 'agent cancel coder run-1'

out=$("$BIN" --status coder)
assert_contains "$out" 'agent=coder'
assert_contains "$(last_call)" 'agent status coder'

out=$("$BIN" --raw coder raw)
assert_contains "$out" '"type":"delta"'
assert_contains "$(last_call)" 'agent send coder --raw raw'

rm -f "$CTX_FAKE_ATTACH_OK"
out=$("$BIN" --attach coder)
assert_contains "$out" 'tsh>'
assert_contains "$(cat "$LOG")" 'agent attach coder'
assert_contains "$(cat "$LOG")" 'agent start coder'

help=$("$BIN" --help)
assert_contains "$help" 'agent.sh --attach AGENT'
assert_contains "$help" 'agent.sh --output AGENT'
assert_contains "$help" 'With no INPUT, it opens the agent chat REPL'

printf 'agent.sh tests passed\n'
